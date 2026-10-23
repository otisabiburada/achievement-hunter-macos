import Foundation

/// An achievement that was locked in the previous sync and is unlocked now.
public struct UnlockEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(appId)-\(achievement.apiName)" }
    public let appId: Int
    public let gameName: String
    public let achievement: Achievement
    public let detectedAt: Date
    public var isSeen: Bool
    
    /// The real unlock time if Steam gave one, otherwise when we noticed it.
    public var happenedAt: Date { achievement.unlockTimestamp ?? detectedAt }
}

extension UnlockEvent {
    /// Real unlocks trickle in; dozens detected within a minute are a data import (e.g. a library repaired after an
    /// earlier bug), not play. Such bursts are dropped from the feed.
    public static func removingImportBursts(from events: [UnlockEvent], window: TimeInterval = 60, limit: Int = 40) -> [UnlockEvent] {
        guard events.count > limit else { return events }
        let sorted = events.sorted { $0.detectedAt < $1.detectedAt }
        var drop = Set<String>()
        var start = 0
        for end in sorted.indices {
            while sorted[end].detectedAt.timeIntervalSince(sorted[start].detectedAt) > window { start += 1 }
            if end - start + 1 > limit {
                for k in start...end { drop.insert(sorted[k].id) }
            }
        }
        return drop.isEmpty ? events : events.filter { !drop.contains($0.id) }
    }
}

/// Decides which of a game's unlocked achievements are NEW since the last time we looked.
public enum UnlockDetector {
    /// - `previous`: what was saved for the game before this fetch (nil if the game wasn't known).
    /// - `previousSyncAt`: when the previous sync finished (nil on the very first sync: everything is baseline).
    ///
    /// With a real baseline (the game had saved achievements AND some were unlocked) the answer is the difference.
    /// Without one (a game added since the last sync, or one that had nothing unlocked yet) a diff would be
    /// everything or nothing, so the unlock TIME decides: only unlocks made after the previous sync are new. That
    /// also keeps a repaired or re-imported library from flooding the feed with old unlocks.
    public static func newUnlocks(previous: SteamGame?, fresh: [Achievement], previousSyncAt: Date?, tolerance: TimeInterval = 120, importLimit: Int = 200) -> [Achievement] {
        let unlocked = fresh.filter { $0.isUnlocked }
        let known = Set((previous?.achievements ?? []).filter { $0.isUnlocked }.map { $0.apiName.lowercased() })
        let hasBaseline = previous?.hasAchievementsLoaded == true && !(previous?.achievements.isEmpty ?? true) && !known.isEmpty
        
        var result: [Achievement]
        if hasBaseline {
            result = unlocked.filter { !known.contains($0.apiName.lowercased()) }
        } else {
            guard let since = previousSyncAt else { return [] }
            result = unlocked.filter { !known.contains($0.apiName.lowercased()) && ($0.unlockTimestamp ?? .distantPast) > since.addingTimeInterval(-tolerance) }
        }
        if result.count > importLimit { return [] }
        return result.sorted { ($0.unlockTimestamp ?? .distantPast) > ($1.unlockTimestamp ?? .distantPast) }
    }
}

/// One calendar day of the activity feed.
public struct ActivityDay: Identifiable {
    public var id: Date { day }
    public let day: Date
    public let events: [UnlockEvent]
    public var count: Int { events.count }
}

public enum ActivityWindow {
    /// The `maxDays` most recent days that have activity (empty days are skipped), newest first, each day's events
    /// newest first. `hasMore` says whether older days exist. Input must already be sorted newest first.
    public static func recentDays(from sortedEvents: [UnlockEvent], maxDays: Int, calendar: Calendar = .current) -> (days: [ActivityDay], hasMore: Bool) {
        var days: [ActivityDay] = []
        var currentDay: Date?
        var bucket: [UnlockEvent] = []
        var hasMore = false
        
        for event in sortedEvents {
            let day = calendar.startOfDay(for: event.happenedAt)
            if day != currentDay {
                if let finished = currentDay { days.append(ActivityDay(day: finished, events: bucket)) }
                if days.count >= maxDays { hasMore = true; bucket = []; currentDay = nil; break }
                currentDay = day
                bucket = []
            }
            bucket.append(event)
        }
        if let finished = currentDay, !bucket.isEmpty { days.append(ActivityDay(day: finished, events: bucket)) }
        return (days, hasMore)
    }
}
