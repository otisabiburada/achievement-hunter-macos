import Foundation

/// When and how unlock notifications are delivered. Pure logic (no system calls) so it can be tested.
public struct NotificationPolicy: Equatable, Codable, Sendable {
    public var enabled = true
    /// No banners between `quietStartMinute` and `quietEndMinute` (minutes after midnight; may wrap past midnight).
    public var quietHoursEnabled = false
    public var quietStartMinute = 22 * 60
    public var quietEndMinute = 8 * 60
    /// One summary a day instead of a banner per unlock (ultra-rare unlocks still get their own).
    public var dailySummary = false
    public var summaryMinute = 20 * 60
    /// A bigger celebration (in-app card plus a distinct banner) for unlocks almost nobody has.
    public var celebrateUltraRare = true
    public var ultraRarePercent = 1.0
    
    public init() {}
    
    public struct Routing: Equatable {
        public var post: [UnlockEvent] = []        // banner now
        public var queue: [UnlockEvent] = []       // hold for a summary
        public var celebrate: [UnlockEvent] = []   // in-app celebration
    }
    
    public func isUltraRare(_ event: UnlockEvent) -> Bool {
        guard let p = event.achievement.globalPercent else { return false }
        return p > 0 && p <= ultraRarePercent
    }
    
    private func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    
    public func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled, quietStartMinute != quietEndMinute else { return false }
        let m = minuteOfDay(date, calendar)
        if quietStartMinute < quietEndMinute { return m >= quietStartMinute && m < quietEndMinute }
        return m >= quietStartMinute || m < quietEndMinute
    }
    
    public func route(_ events: [UnlockEvent], at date: Date, calendar: Calendar = .current) -> Routing {
        var r = Routing()
        if celebrateUltraRare { r.celebrate = events.filter(isUltraRare) }
        guard enabled else { return r }
        let quiet = isQuiet(at: date, calendar: calendar)
        for e in events {
            if quiet { r.queue.append(e) }
            else if dailySummary && !(celebrateUltraRare && isUltraRare(e)) { r.queue.append(e) }
            else { r.post.append(e) }
        }
        return r
    }
    
    /// Whether the held events should be delivered now, as one summary.
    public func summaryDue(pending: [UnlockEvent], lastSummary: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, !pending.isEmpty, !isQuiet(at: now, calendar: calendar) else { return false }
        if let oldest = pending.map({ $0.detectedAt }).min(), now.timeIntervalSince(oldest) > 86_400 { return true }
        guard dailySummary else { return true }          // held only because of quiet hours, which are over
        let summarizedToday = lastSummary.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        return !summarizedToday && minuteOfDay(now, calendar) >= summaryMinute
    }
    
    public static func summaryText(_ events: [UnlockEvent]) -> (title: String, body: String) {
        let games = Set(events.map { $0.appId }).count
        let title = events.count == 1 ? "1 new achievement" : "\(events.count) new achievements" + (games > 1 ? " in \(games) games" : "")
        let rarest = events.filter { $0.achievement.globalPercent != nil }.sorted { ($0.achievement.globalPercent ?? 100) < ($1.achievement.globalPercent ?? 100) }.first
        var body = events.prefix(3).map { "\($0.achievement.displayName) (\($0.gameName))" }.joined(separator: ", ")
        if events.count > 3 { body += " and \(events.count - 3) more" }
        if let r = rarest, let p = r.achievement.globalPercent, p < 10 {
            body += String(format: ". Rarest: %@, %.1f%% of players", r.achievement.displayName, p)
        }
        return (title, body)
    }
}
