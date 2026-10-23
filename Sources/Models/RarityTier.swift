import SwiftUI

public enum RarityTier: String, CaseIterable, Codable {
    case legendary = "Legendary"
    case ultraRare = "Ultra Rare"
    case rare = "Rare"
    case uncommon = "Uncommon"
    case common = "Common"
    
    public init(percentage: Double) {
        switch percentage {
        case ..<3.0:
            self = .legendary
        case 3.0..<10.0:
            self = .ultraRare
        case 10.0..<25.0:
            self = .rare
        case 25.0..<50.0:
            self = .uncommon
        default:
            self = .common
        }
    }
    
    public var color: Color {
        switch self {
        case .legendary:
            return Color(red: 1.0, green: 0.8, blue: 0.2) // Gold / Amber
        case .ultraRare:
            return Color(red: 0.85, green: 0.45, blue: 1.0) // Diamond Purple
        case .rare:
            return Color(red: 0.3, green: 0.65, blue: 1.0) // Vibrant Blue
        case .uncommon:
            return Color(red: 0.3, green: 0.85, blue: 0.5) // Emerald Green
        case .common:
            return Color.secondary
        }
    }
    
    public var iconName: String {
        switch self {
        case .legendary:
            return "crown.fill"
        case .ultraRare:
            return "sparkles"
        case .rare:
            return "diamond.fill"
        case .uncommon:
            return "trophy.fill"
        case .common:
            return "circle.fill"
        }
    }
}
