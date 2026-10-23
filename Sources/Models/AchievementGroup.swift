import Foundation

/// A Steam "Achievement Set": a developer-defined group of achievements. Group 0 is the base game;
/// groups with a `dlcAppId` hold achievements that need that DLC. Whole sets can be archived.
public struct AchievementGroup: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { groupId }
    public let groupId: Int
    public var name: String
    /// 0 for base-game sets, otherwise the DLC app that unlocks the set.
    public var dlcAppId: Int
    public var isArchived: Bool
    public var isDeveloperOnly: Bool
    public var order: Int
    public var totalCount: Int
    /// Whether THIS player can earn the set, as Steam reports it: a player's own achievement list only contains the sets
    /// they have access to (base game, DLC they own). nil = not known (older data, or a source that doesn't say).
    public var ownedByPlayer: Bool?
    
    public init(groupId: Int, name: String, dlcAppId: Int = 0, isArchived: Bool = false,
                isDeveloperOnly: Bool = false, order: Int = 0, totalCount: Int = 0, ownedByPlayer: Bool? = nil) {
        self.groupId = groupId
        self.name = name
        self.dlcAppId = dlcAppId
        self.isArchived = isArchived
        self.isDeveloperOnly = isDeveloperOnly
        self.order = order
        self.totalCount = totalCount
        self.ownedByPlayer = ownedByPlayer
    }
    
    public var isDLC: Bool { dlcAppId != 0 }
    
    public var displayName: String {
        if !name.isEmpty { return name }
        return groupId == 0 ? "Base Game" : "Set \(groupId)"
    }
}
