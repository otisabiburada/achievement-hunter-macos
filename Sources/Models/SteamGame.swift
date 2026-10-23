import Foundation

public struct SteamGame: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { appId }
    public let appId: Int
    public var name: String
    public var playtimeMinutes: Int
    public var iconHash: String?
    public var customHeaderUrl: String?
    public var achievements: [Achievement] { didSet { refreshCounts() } }
    public var hasAchievementsLoaded: Bool
    /// Set when the last attempt to load achievements failed; cleared on success.
    public var loadError: String?
    /// When achievements were last fetched successfully (drives incremental sync).
    public var lastFetchedAt: Date?
    /// false when the playtime was not provided by the source (scraped pages); nil means known.
    public var playtimeIsKnown: Bool?
    /// Steam Achievement Sets for this game (nil until fetched, or for games that don't use sets).
    public var achievementGroups: [AchievementGroup]? { didSet { refreshCounts() } }
    /// Manual "I own this DLC" overrides for DLC sets, keyed by group id as a string.
    public var dlcOverrides: [String: Bool]? { didSet { refreshCounts() } }
    
    // Cached progress counts. The game list reads these for every row on every redraw, so they are computed
    // once when the data changes instead of filtering the achievement list each time.
    public private(set) var cachedTotal: Int = 0
    public private(set) var cachedUnlocked: Int = 0
    
    private enum CodingKeys: String, CodingKey {
        case appId, name, playtimeMinutes, iconHash, customHeaderUrl, achievements, hasAchievementsLoaded
        case loadError, lastFetchedAt, playtimeIsKnown, achievementGroups, dlcOverrides
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appId = try c.decode(Int.self, forKey: .appId)
        name = try c.decode(String.self, forKey: .name)
        playtimeMinutes = try c.decodeIfPresent(Int.self, forKey: .playtimeMinutes) ?? 0
        iconHash = try c.decodeIfPresent(String.self, forKey: .iconHash)
        customHeaderUrl = try c.decodeIfPresent(String.self, forKey: .customHeaderUrl)
        achievements = try c.decodeIfPresent([Achievement].self, forKey: .achievements) ?? []
        hasAchievementsLoaded = try c.decodeIfPresent(Bool.self, forKey: .hasAchievementsLoaded) ?? false
        loadError = try c.decodeIfPresent(String.self, forKey: .loadError)
        lastFetchedAt = try c.decodeIfPresent(Date.self, forKey: .lastFetchedAt)
        playtimeIsKnown = try c.decodeIfPresent(Bool.self, forKey: .playtimeIsKnown)
        achievementGroups = try c.decodeIfPresent([AchievementGroup].self, forKey: .achievementGroups)
        dlcOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .dlcOverrides)
        refreshCounts()
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(appId, forKey: .appId)
        try c.encode(name, forKey: .name)
        try c.encode(playtimeMinutes, forKey: .playtimeMinutes)
        try c.encodeIfPresent(iconHash, forKey: .iconHash)
        try c.encodeIfPresent(customHeaderUrl, forKey: .customHeaderUrl)
        try c.encode(achievements, forKey: .achievements)
        try c.encode(hasAchievementsLoaded, forKey: .hasAchievementsLoaded)
        try c.encodeIfPresent(loadError, forKey: .loadError)
        try c.encodeIfPresent(lastFetchedAt, forKey: .lastFetchedAt)
        try c.encodeIfPresent(playtimeIsKnown, forKey: .playtimeIsKnown)
        try c.encodeIfPresent(achievementGroups, forKey: .achievementGroups)
        try c.encodeIfPresent(dlcOverrides, forKey: .dlcOverrides)
    }
    
    private mutating func refreshCounts() {
        let trackable = trackableAchievements
        cachedTotal = trackable.count
        cachedUnlocked = trackable.reduce(0) { $0 + ($1.isUnlocked ? 1 : 0) }
    }
    
    public init(
        appId: Int,
        name: String,
        playtimeMinutes: Int = 0,
        iconHash: String? = nil,
        customHeaderUrl: String? = nil,
        achievements: [Achievement] = [],
        hasAchievementsLoaded: Bool = false,
        loadError: String? = nil,
        lastFetchedAt: Date? = nil,
        playtimeIsKnown: Bool? = nil
    ) {
        self.appId = appId
        self.name = name
        self.playtimeMinutes = playtimeMinutes
        self.iconHash = iconHash
        self.customHeaderUrl = customHeaderUrl
        self.achievements = achievements
        self.hasAchievementsLoaded = hasAchievementsLoaded
        self.loadError = loadError
        self.lastFetchedAt = lastFetchedAt
        self.playtimeIsKnown = playtimeIsKnown
        refreshCounts()
    }
    
    // MARK: Achievement Sets
    //
    // Rules (from Valve's Achievement Sets announcement):
    //  - archived achievements don't count for players who missed them, but stay visible if unlocked;
    //  - DLC set achievements don't count until the player has access to the DLC;
    //  - developer-only sets never count.
    // DLC access can't be read from the API, so a DLC set counts once you've unlocked something in it,
    // or when you mark it as owned (`dlcOverrides`).
    
    public func group(_ id: Int?) -> AchievementGroup? {
        guard let id = id else { return nil }
        return achievementGroups?.first { $0.groupId == id }
    }
    
    public func isGroupAccessible(_ id: Int?) -> Bool {
        guard let g = group(id) else { return true }
        if g.isDeveloperOnly { return false }
        if !g.isDLC { return true }
        if let override = dlcOverrides?["\(g.groupId)"] { return override }          // the user's own word wins
        if let owned = g.ownedByPlayer { return owned }                            // what Steam says about this player
        return achievements.contains { $0.groupId == g.groupId && $0.isUnlocked }  // last resort: proof of access
    }
    
    public func countsTowardCompletion(_ a: Achievement) -> Bool {
        if a.isArchived == true && !a.isUnlocked { return false }
        return isGroupAccessible(a.groupId)
    }
    
    /// Achievements that count toward this game's progress and completion.
    public var trackableAchievements: [Achievement] {
        guard let groups = achievementGroups, groups.contains(where: { $0.isDLC || $0.isDeveloperOnly }) else {
            // Fast path (most games): only archive rules apply.
            return achievements.filter { !($0.isArchived == true && !$0.isUnlocked) }
        }
        let accessible = Dictionary(uniqueKeysWithValues: groups.map { ($0.groupId, isGroupAccessible($0.groupId)) })
        return achievements.filter { a in
            if a.isArchived == true && !a.isUnlocked { return false }
            return accessible[a.groupId ?? 0] ?? true
        }
    }
    
    public var totalAchievements: Int { cachedTotal }
    
    public var unlockedAchievements: Int { cachedUnlocked }
    
    /// True once achievements have been fetched and the game has none that matter.
    public var hasNoAchievements: Bool {
        hasAchievementsLoaded && loadError == nil && totalAchievements == 0
    }
    
    public var hasMultipleSets: Bool {
        (achievementGroups?.count ?? 0) > 1
    }
    
    public var lockedAchievements: Int {
        totalAchievements - unlockedAchievements
    }
    
    public var completionPercentage: Double {
        guard totalAchievements > 0 else { return 0.0 }
        return (Double(unlockedAchievements) / Double(totalAchievements)) * 100.0
    }
    
    public var isPerfect: Bool {
        totalAchievements > 0 && unlockedAchievements == totalAchievements
    }
    
    public var playtimeHoursFormatted: String {
        if playtimeIsKnown == false {
            return "Playtime unknown"
        }
        if playtimeMinutes == 0 {
            return "Never played"
        }
        let hours = Double(playtimeMinutes) / 60.0
        if hours < 1.0 {
            return "\(playtimeMinutes) mins"
        }
        return String(format: "%.1f hrs", hours)
    }
    
    // High-Resolution Hero Banner for Game Detail Header (1920x620 or 460x215)
    public var heroBannerUrl: URL? {
        URL(string: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(appId)/library_hero.jpg")
            ?? headerImageUrl
    }
    
    // Crisp 460x215 Header Image for Rows, Cards, and Highlights
    public var headerImageUrl: URL? {
        if let custom = customHeaderUrl, !custom.isEmpty {
            if custom.contains("capsule_184x69") {
                let upgraded = custom.replacingOccurrences(of: "capsule_184x69.jpg", with: "header.jpg")
                    .replacingOccurrences(of: "capsule_184x69", with: "header")
                if let url = URL(string: upgraded) {
                    return url
                }
            } else if let url = URL(string: custom) {
                return url
            }
        }
        return URL(string: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(appId)/header.jpg")
    }
    
    public var iconUrl: URL? {
        if let hash = iconHash, !hash.isEmpty {
            return URL(string: "https://media.steampowered.com/steamcommunity/public/images/apps/\(appId)/\(hash).jpg")
        }
        return headerImageUrl
    }
    
    public var storeUrl: URL? {
        URL(string: "https://store.steampowered.com/app/\(appId)")
    }
    
    public var steamClientUrl: URL? {
        URL(string: "steam://nav/games/details/\(appId)")
    }
}
