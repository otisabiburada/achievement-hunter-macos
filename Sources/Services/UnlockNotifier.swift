import Foundation
import UserNotifications

/// Posts macOS notifications for newly detected unlocks. Asks for permission lazily, the first
/// time there is something to announce, and can be switched off in Settings.
final class UnlockNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UnlockNotifier()
    static let enabledKey = "notify_unlocks"
    
    private var center: UNUserNotificationCenter? {
        // Notifications need a real app bundle; skip quietly when run as a bare binary.
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }
    
    static let policyKey = "notification_policy"
    private static let pendingKey = "notification_pending"
    private static let lastSummaryKey = "notification_last_summary"
    
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    
    /// Delivery rules. Falls back to the old on/off switch when nothing else has been saved.
    static var policy: NotificationPolicy {
        get {
            if let data = UserDefaults.standard.data(forKey: policyKey), let p = try? JSONDecoder().decode(NotificationPolicy.self, from: data) { return p }
            var p = NotificationPolicy(); p.enabled = isEnabled; return p
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: policyKey) }
            isEnabled = newValue.enabled
        }
    }
    
    private var pending: [UnlockEvent] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.pendingKey) else { return [] }
            return (try? JSONDecoder().decode([UnlockEvent].self, from: data)) ?? []
        }
        set {
            let capped = Array(newValue.suffix(300))
            if capped.isEmpty { UserDefaults.standard.removeObject(forKey: Self.pendingKey) }
            else if let data = try? JSONEncoder().encode(capped) { UserDefaults.standard.set(data, forKey: Self.pendingKey) }
        }
    }
    
    private var timer: Timer?
    
    func configure() {
        center?.delegate = self
        timer?.invalidate()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.flushIfDue() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    /// Delivers held events as one summary when the rules say it's time (end of quiet hours, or the daily summary hour).
    func flushIfDue(now: Date = Date()) {
        let held = pending
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: Self.lastSummaryKey) as? Date
        guard Self.policy.summaryDue(pending: held, lastSummary: last, now: now) else { return }
        pending = []
        defaults.set(now, forKey: Self.lastSummaryKey)
        let text = NotificationPolicy.summaryText(held)
        withPermission { center in
            let content = UNMutableNotificationContent()
            content.title = text.title; content.body = text.body; content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
    
    /// Routes new unlocks through the policy. Returns the ultra-rare ones for an in-app celebration.
    @discardableResult
    func notify(_ events: [UnlockEvent]) -> [UnlockEvent] {
        guard !events.isEmpty else { return [] }
        let policy = Self.policy
        let routing = policy.route(events, at: Date())
        if !routing.queue.isEmpty { pending += routing.queue }
        if !routing.post.isEmpty {
            let rare = routing.post.filter { policy.celebrateUltraRare && policy.isUltraRare($0) }
            let normal = routing.post.filter { e in !rare.contains { $0.id == e.id } }
            withPermission { center in
                if !normal.isEmpty { Self.post(normal, on: center) }
                for e in rare { Self.postCelebration(e, on: center) }
            }
        }
        return routing.celebrate
    }
    
    private func withPermission(_ send: @escaping (UNUserNotificationCenter) -> Void) {
        guard let center = center else { return }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { send(center) }
                }
            case .authorized, .provisional:
                send(center)
            default:
                break
            }
        }
    }
    
    /// Friend news (a rare unlock or a finished game). Respects quiet hours by simply not posting; the in-app list keeps them.
    func postFriendAlerts(_ alerts: [FriendAlert]) {
        guard !alerts.isEmpty, !Self.policy.isQuiet(at: Date()) else { return }
        withPermission { center in
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.title = alerts.count == 1 ? "Friend news" : "\(alerts.count) friend updates"
            content.body = alerts.prefix(3).map { $0.text }.joined(separator: "\n")
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
    
    private static func postCelebration(_ e: UnlockEvent, on center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.title = "Ultra-rare unlock: \(e.achievement.displayName)"
        content.body = e.gameName + (e.achievement.globalPercent.map { String(format: " - only %.2f%% of players have this!", $0) } ?? "")
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    
    private static func post(_ events: [UnlockEvent], on center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if events.count == 1, let e = events.first {
            content.title = "Achievement unlocked: \(e.achievement.displayName)"
            var body = e.gameName
            if let pct = e.achievement.globalPercent {
                body += String(format: " - only %.1f%% of players have this", pct)
            }
            content.body = body
        } else {
            content.title = "\(events.count) new achievements"
            content.body = events.prefix(3).map { "\($0.achievement.displayName) (\($0.gameName))" }.joined(separator: ", ")
                + (events.count > 3 ? " and more" : "")
        }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    
    // Show banners even while the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
