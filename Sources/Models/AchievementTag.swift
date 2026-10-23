import SwiftUI

public enum AchievementTag: String, CaseIterable, Identifiable, Codable, Sendable {
    case missable = "Missable"
    case multiplayer = "Multiplayer"
    case difficulty = "Difficulty"
    case grind = "Grind"
    case story = "Story / Unmissable"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .missable:
            return "exclamationmark.triangle.fill"
        case .multiplayer:
            return "person.2.fill"
        case .difficulty:
            return "flame.fill"
        case .grind:
            return "hourglass"
        case .story:
            return "book.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .missable:
            return .red
        case .multiplayer:
            return .blue
        case .difficulty:
            return .orange
        case .grind:
            return .purple
        case .story:
            return .green
        }
    }
}
