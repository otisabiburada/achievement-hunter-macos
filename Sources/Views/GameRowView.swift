import SwiftUI

public struct GameRowView: View {
    public let game: SteamGame
    public let isSelected: Bool
    @State private var hovering = false
    
    public var body: some View {
        HStack(spacing: 10) {
            // Game Artwork Thumbnail
            RemoteImageView(
                url: game.headerImageUrl,
                fallbackSystemName: "gamecontroller.fill",
                cornerRadius: 6
            )
            .frame(width: 52, height: 26)
            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(game.name)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if game.loadError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .help(game.loadError ?? "")
                    }
                    
                    if game.hasMultipleSets {
                        Text("\(game.achievementGroups?.count ?? 0) sets")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.14), in: Capsule())
                            .foregroundColor(.purple)
                    }
                    
                    if game.isPerfect {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                    }
                }
                
                HStack(spacing: 6) {
                    Text(game.playtimeHoursFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    if game.totalAchievements > 0 {
                        Text("\(game.unlockedAchievements)/\(game.totalAchievements)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(game.isPerfect ? Color(red: 1.0, green: 0.75, blue: 0.1) : .secondary)
                    } else {
                        Text(game.hasAchievementsLoaded ? "No achievements" : "Not synced yet")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    if game.totalAchievements > 0 {
                        Text("\(Int(game.completionPercentage))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(game.isPerfect ? Color(red: 1.0, green: 0.75, blue: 0.1) : .primary.opacity(0.8))
                    }
                }
                
                if game.totalAchievements > 0 {
                    CustomProgressBar(
                        value: game.completionPercentage,
                        height: 3,
                        isPerfect: game.isPerfect
                    )
                    .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : (hovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(game.isPerfect ? Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
