import Foundation

public struct Achievement: Identifiable, Hashable, Codable, Sendable {
    public var id: String { apiName }
    public let apiName: String
    public let displayName: String
    public let descriptionText: String
    public let iconUrl: String?
    public let grayIconUrl: String?
    public var isUnlocked: Bool
    public var unlockTimestamp: Date?
    public var globalPercent: Double?
    public let isHidden: Bool
    public var tags: [AchievementTag]
    public var gameAppId: Int?
    public var gameName: String?
    /// Steam Achievement Set this belongs to (0 / nil = base game).
    public var groupId: Int?
    /// Archived by the developer: can no longer be earned.
    public var isArchived: Bool?
    
    public init(
        apiName: String,
        displayName: String,
        descriptionText: String,
        iconUrl: String? = nil,
        grayIconUrl: String? = nil,
        isUnlocked: Bool = false,
        unlockTimestamp: Date? = nil,
        globalPercent: Double? = nil,
        isHidden: Bool = false,
        tags: [AchievementTag] = [],
        gameAppId: Int? = nil,
        gameName: String? = nil,
        groupId: Int? = nil,
        isArchived: Bool? = nil
    ) {
        self.apiName = apiName
        self.displayName = displayName
        self.descriptionText = descriptionText
        self.iconUrl = iconUrl
        self.grayIconUrl = grayIconUrl
        self.isUnlocked = isUnlocked
        self.unlockTimestamp = unlockTimestamp
        self.globalPercent = globalPercent
        self.isHidden = isHidden
        self.tags = tags
        self.gameAppId = gameAppId
        self.gameName = gameName
        self.groupId = groupId
        self.isArchived = isArchived
    }
    
    public var rarityTier: RarityTier? {
        guard let globalPercent = globalPercent else { return nil }
        return RarityTier(percentage: globalPercent)
    }
    
    public var formattedUnlockDate: String? {
        guard let unlockTimestamp = unlockTimestamp else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: unlockTimestamp)
    }
    
    public var formattedRarity: String {
        if let globalPercent = globalPercent {
            return String(format: "%.1f%%", globalPercent)
        }
        return "--"
    }
}
