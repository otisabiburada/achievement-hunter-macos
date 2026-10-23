import Foundation

public struct PinnedTarget: Identifiable, Hashable, Codable {
    public var id: String { "\(appId)_\(achievement.apiName)" }
    public let appId: Int
    public let gameName: String
    public var achievement: Achievement
    public let pinnedAt: Date
    public var notes: String
    
    public init(
        appId: Int,
        gameName: String,
        achievement: Achievement,
        pinnedAt: Date = Date(),
        notes: String = ""
    ) {
        self.appId = appId
        self.gameName = gameName
        self.achievement = achievement
        self.pinnedAt = pinnedAt
        self.notes = notes
    }
}
