import Foundation

/// Something a friend did that is worth a heads-up.
public struct FriendAlert: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case rare, finished }
    public var id: String { "\(friendId)-\(appId)-\(kind.rawValue)-\(achievementName ?? "")" }
    public let friendId: String
    public let friendName: String
    public let appId: Int
    public let gameName: String
    public let kind: Kind
    public let achievementName: String?
    public let percent: Double?
    public let date: Date
    
    public var text: String {
        switch kind {
        case .rare: return "\(friendName) unlocked \(achievementName ?? "a rare achievement") in \(gameName)" + (percent.map { String(format: " (%.1f%% of players)", $0) } ?? "")
        case .finished: return "\(friendName) finished \(gameName) (100%)"
        }
    }
}

public enum FriendWatch {
    /// Compares what a friend has now with what we saw last time (internal keys of unlocked achievements).
    /// `previous == nil` is the first look: it only records a baseline and never alerts.
    public static func alerts(
        friendId: String, friendName: String, appId: Int, gameName: String,
        previous: Set<Int>?, rows: [UserAchievementRow], entries: [CatalogEntry],
        rarePercent: Double = 5, now: Date = Date()
    ) -> (alerts: [FriendAlert], unlocked: Set<Int>) {
        let countable = entries.filter { !$0.isArchived && $0.internalKey != nil }
        let unlocked = Set(rows.filter { $0.unlocked }.map { $0.internalKey })
        guard let previous = previous else { return ([], unlocked) }
        var out: [FriendAlert] = []
        let fresh = unlocked.subtracting(previous)
        for e in countable where e.internalKey.map({ fresh.contains($0) }) == true {
            if let p = e.percent, p > 0, p <= rarePercent {
                out.append(FriendAlert(friendId: friendId, friendName: friendName, appId: appId, gameName: gameName, kind: .rare, achievementName: e.displayName, percent: p, date: now))
            }
        }
        let keys = Set(countable.compactMap { $0.internalKey })
        if !keys.isEmpty, !fresh.isEmpty, keys.isSubset(of: unlocked), !keys.isSubset(of: previous) {
            out.append(FriendAlert(friendId: friendId, friendName: friendName, appId: appId, gameName: gameName, kind: .finished, achievementName: nil, percent: nil, date: now))
        }
        return (out, unlocked)
    }
    
    /// Games worth checking for a friend: the one they're in now, if you own it and it has achievements.
    public static func gamesToCheck(friendGameId: Int?, lastSeen: [Int], owned: Set<Int>) -> [Int] {
        var ids: [Int] = []
        for id in ([friendGameId].compactMap { $0 } + lastSeen) where owned.contains(id) && !ids.contains(id) { ids.append(id) }
        return Array(ids.prefix(3))
    }
}
