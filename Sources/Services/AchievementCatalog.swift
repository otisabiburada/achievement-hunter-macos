import Foundation

/// One achievement as described by Steam's public catalog (IPlayerService/GetGameAchievements, no API key).
public struct CatalogEntry: Codable, Hashable, Sendable {
    public let apiName: String
    public let displayName: String
    public let description: String
    public let iconUrl: String?
    public let grayIconUrl: String?
    public let isHidden: Bool
    public let percent: Double?
    public let groupId: Int
    public let isArchived: Bool
    /// Steam's numeric id for the achievement; the player-specific endpoint identifies achievements by it.
    public let internalKey: Int?
    
    public init(apiName: String, displayName: String, description: String, iconUrl: String?, grayIconUrl: String?,
                isHidden: Bool, percent: Double?, groupId: Int, isArchived: Bool, internalKey: Int? = nil) {
        self.apiName = apiName
        self.displayName = displayName
        self.description = description
        self.iconUrl = iconUrl
        self.grayIconUrl = grayIconUrl
        self.isHidden = isHidden
        self.percent = percent
        self.groupId = groupId
        self.isArchived = isArchived
        self.internalKey = internalKey
    }
}

/// Everything Steam publishes about a game's achievements, including Achievement Sets.
public struct AchievementCatalog: Codable, Sendable {
    public var entries: [CatalogEntry]
    public var groups: [AchievementGroup]
    public var schemaHash: Int?
    
    public init(entries: [CatalogEntry], groups: [AchievementGroup], schemaHash: Int? = nil) {
        self.entries = entries
        self.groups = groups
        self.schemaHash = schemaHash
    }
    
    public var isEmpty: Bool { entries.isEmpty }
    
    /// Parses the GetGameAchievements response. Tolerant of fields that older/future schemas lack.
    public static func parse(response: [String: Any], appId: Int) -> AchievementCatalog {
        func imageURL(_ file: String?) -> String? {
            guard let file = file, !file.isEmpty else { return nil }
            if file.hasPrefix("http") { return file }
            return "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/\(appId)/\(file)"
        }
        func number(_ v: Any?) -> Int? {
            if let n = v as? Int { return n }
            if let n = v as? NSNumber { return n.intValue }
            if let s = v as? String { return Int(s) }
            return nil
        }
        func flag(_ v: Any?) -> Bool {
            if let b = v as? Bool { return b }
            if let n = v as? NSNumber { return n.intValue != 0 }
            return false
        }
        
        var entries: [CatalogEntry] = []
        for item in (response["achievements"] as? [[String: Any]]) ?? [] {
            guard let name = item["internal_name"] as? String, !name.isEmpty else { continue }
            let percent: Double? = (item["player_percent_unlocked"] as? String).flatMap { Double($0) }
                ?? (item["player_percent_unlocked"] as? Double)
            entries.append(CatalogEntry(
                apiName: name,
                displayName: item["localized_name"] as? String ?? name,
                description: item["localized_desc"] as? String ?? "",
                iconUrl: imageURL(item["icon"] as? String),
                grayIconUrl: imageURL(item["icon_gray"] as? String),
                isHidden: flag(item["hidden"]),
                percent: percent,
                groupId: number(item["groupid"]) ?? 0,
                isArchived: flag(item["archived"]),
                internalKey: number(item["internal_key"])
            ))
        }
        
        var groups: [AchievementGroup] = []
        for item in (response["groups"] as? [[String: Any]]) ?? [] {
            guard let id = number(item["groupid"]) else { continue }
            groups.append(AchievementGroup(
                groupId: id,
                name: item["localized_name"] as? String ?? "",
                dlcAppId: number(item["dlcappid"]) ?? 0,
                isArchived: flag(item["archived"]),
                isDeveloperOnly: flag(item["developeronly"]),
                order: number(item["order"]) ?? 0,
                totalCount: number(item["total_achievements"]) ?? entries.filter { $0.groupId == id }.count
            ))
        }
        groups.sort { ($0.order, $0.groupId) < ($1.order, $1.groupId) }
        return AchievementCatalog(entries: entries, groups: groups, schemaHash: number(response["schema_hash"]))
    }
}

/// What a player-specific source (Web API with key, or the community stats page) knows about one achievement.
public struct PlayerAchievementRow: Sendable {
    public var apiName: String
    public var name: String?
    public var description: String?
    public var iconUrl: String?
    public var grayIconUrl: String?
    public var isUnlocked: Bool
    public var unlockTime: Date?
    
    public init(apiName: String, name: String? = nil, description: String? = nil, iconUrl: String? = nil,
                grayIconUrl: String? = nil, isUnlocked: Bool, unlockTime: Date? = nil) {
        self.apiName = apiName
        self.name = name
        self.description = description
        self.iconUrl = iconUrl
        self.grayIconUrl = grayIconUrl
        self.isUnlocked = isUnlocked
        self.unlockTime = unlockTime
    }
}

/// One row of `IPlayerService/GetUserAchievements`: a player's state for one achievement, by Steam's numeric key.
public struct UserAchievementRow: Sendable, Equatable {
    public var internalKey: Int
    public var unlocked: Bool
    public var unlockTime: Date?
    
    public init(internalKey: Int, unlocked: Bool, unlockTime: Date? = nil) {
        self.internalKey = internalKey
        self.unlocked = unlocked
        self.unlockTime = unlockTime
    }
}

/// A player's achievements for one game plus the achievement sets Steam lists for THEM (their access: base game and
/// the DLC they own; unowned DLC sets are left out).
public struct UserAchievementsResult: Sendable {
    public var rows: [UserAchievementRow]
    public var accessibleGroupIds: Set<Int>?
}

extension AchievementCatalog {
    /// The sets with this player's ownership filled in (DLC sets only; base sets are always theirs).
    public func groups(markingOwnedBy accessible: Set<Int>?) -> [AchievementGroup] {
        guard let accessible = accessible else { return groups }
        return groups.map { g in
            var copy = g
            if g.dlcAppId != 0 { copy.ownedByPlayer = accessible.contains(g.groupId) }
            return copy
        }
    }
    
    public var hasDLCSets: Bool { groups.contains { $0.dlcAppId != 0 && !$0.isDeveloperOnly } }
    
    /// Translates the player endpoint's numeric keys into the achievements' API names.
    /// Returns nil if the catalog lacks the numeric keys (an older cached copy): refetch it.
    public func playerRows(from rows: [UserAchievementRow]) -> [PlayerAchievementRow]? {
        let byKey = Dictionary(entries.compactMap { e in e.internalKey.map { ($0, e) } }, uniquingKeysWith: { first, _ in first })
        if !rows.isEmpty && byKey.isEmpty { return nil }
        return rows.compactMap { row in
            byKey[row.internalKey].map {
                PlayerAchievementRow(apiName: $0.apiName, isUnlocked: row.unlocked, unlockTime: row.unlocked ? row.unlockTime : nil)
            }
        }
    }
}

public enum AchievementMerger {
    /// Combines the player's unlock state with the catalog (names, icons, rarity, set membership).
    /// Catalog achievements the player source doesn't list (e.g. DLC sets, archived ones) are added as locked,
    /// so the full set structure is visible. Result order follows the catalog.
    public static func merge(
        rows: [PlayerAchievementRow],
        catalog: AchievementCatalog?,
        appId: Int,
        gameName: String? = nil
    ) -> [Achievement] {
        // Steam's community pages return API names in lower case (ach_foo) while the Web API/catalog use the
        // developer's casing (ACH_FOO), so matching is case-insensitive and the catalog's spelling wins.
        let entryByName = Dictionary((catalog?.entries ?? []).map { ($0.apiName.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let order = Dictionary((catalog?.entries ?? []).enumerated().map { ($1.apiName, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [Achievement] = []
        
        for row in rows {
            guard seen.insert(row.apiName.lowercased()).inserted else { continue }
            let entry = entryByName[row.apiName.lowercased()]
            result.append(Achievement(
                apiName: entry?.apiName ?? row.apiName,
                displayName: entry?.displayName ?? row.name ?? row.apiName,
                descriptionText: entry?.description.isEmpty == false ? entry!.description : (row.description ?? ""),
                iconUrl: entry?.iconUrl ?? row.iconUrl,
                grayIconUrl: entry?.grayIconUrl ?? row.grayIconUrl,
                isUnlocked: row.isUnlocked,
                unlockTimestamp: row.isUnlocked ? row.unlockTime : nil,
                globalPercent: entry?.percent,
                isHidden: entry?.isHidden ?? false,
                gameAppId: appId,
                gameName: gameName,
                groupId: entry?.groupId,
                isArchived: entry?.isArchived
            ))
        }
        
        for entry in catalog?.entries ?? [] where !seen.contains(entry.apiName.lowercased()) {
            result.append(Achievement(
                apiName: entry.apiName,
                displayName: entry.displayName,
                descriptionText: entry.description,
                iconUrl: entry.iconUrl,
                grayIconUrl: entry.grayIconUrl,
                isUnlocked: false,
                globalPercent: entry.percent,
                isHidden: entry.isHidden,
                gameAppId: appId,
                gameName: gameName,
                groupId: entry.groupId,
                isArchived: entry.isArchived
            ))
        }
        
        if !order.isEmpty {
            result.sort { (order[$0.apiName] ?? Int.max) < (order[$1.apiName] ?? Int.max) }
        }
        return result
    }
}

/// What to do when the player-specific source (API, community page) returned no achievements for a game.
public enum EmptyPlayerResult: Equatable {
    /// Steam's catalog says the game has achievements: the player simply has none unlocked (or can't be read).
    case lockedFromCatalog
    /// The catalog confirms the game has no achievements.
    case noAchievements
    /// Neither source could be checked, so we must not claim the game has no achievements.
    case unknown
    
    /// `catalog` is nil when the catalog request failed.
    public static func resolve(catalog: AchievementCatalog?) -> EmptyPlayerResult {
        guard let catalog = catalog else { return .unknown }
        return catalog.isEmpty ? .noAchievements : .lockedFromCatalog
    }
}

/// Shared by the concurrent fetches of one sync: remembers when a profile's achievements turn out to be private,
/// so the rest of the library doesn't hammer Steam with requests that will all be refused.
public final class SyncHealth: @unchecked Sendable {
    private let lock = NSLock()
    private var privateHits = 0
    private var successes = 0
    private var tokenRejected = false
    
    public init() {}
    
    public func recordPrivate() { lock.lock(); privateHits += 1; lock.unlock() }
    public func recordSuccess() { lock.lock(); successes += 1; lock.unlock() }
    
    /// Set when Steam refuses the sign-in token for per-game achievements, so the rest of the sync goes straight to the
    /// community pages instead of failing once per game first.
    public var tokenAPIRejected: Bool {
        get { lock.lock(); defer { lock.unlock() }; return tokenRejected }
        set { lock.lock(); tokenRejected = newValue; lock.unlock() }
    }
    
    public var privateCount: Int { lock.lock(); defer { lock.unlock() }; return privateHits }
    
    /// After a few refusals and no success, stop asking the community pages for player data.
    public var communityBlocked: Bool {
        lock.lock(); defer { lock.unlock() }
        return privateHits >= 3 && successes == 0
    }
}
