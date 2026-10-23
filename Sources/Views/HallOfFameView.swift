import SwiftUI

public struct HallOfFameView: View {
    @ObservedObject var state: AppState
    @State private var selectedAchievementForShare: (achievement: Achievement, gameName: String, gameAppId: Int)? = nil
    
    // All unlocked achievements across all games, tagged with game name
    private var rarestUnlockedAchievements: [(achievement: Achievement, gameName: String, gameAppId: Int)] {
        state.unlockedByRarity.map { ($0.achievement, $0.gameName, $0.appId) }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                            Text("Trophy Hall of Fame")
                                .font(.system(size: 24, weight: .bold))
                        }
                        Text("Showcasing the rarest achievements you've ever unlocked across your entire Steam career.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(rarestUnlockedAchievements.count) Unlocked Trophies")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.15))
                        .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.1))
                        .cornerRadius(8)
                }
                
                if rarestUnlockedAchievements.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "crown")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No unlocked achievements found yet.")
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    // Top 3 Podium
                    if rarestUnlockedAchievements.count >= 3 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ALL-TIME RAREST PODIUM")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            HStack(alignment: .bottom, spacing: 14) {
                                // 2nd Place
                                PodiumCard(
                                    item: rarestUnlockedAchievements[1],
                                    rank: 2,
                                    crownColor: Color(white: 0.8),
                                    onShare: {
                                        selectedAchievementForShare = (rarestUnlockedAchievements[1].achievement, rarestUnlockedAchievements[1].gameName, rarestUnlockedAchievements[1].gameAppId)
                                    }
                                )
                                
                                // 1st Place (Center, elevated)
                                PodiumCard(
                                    item: rarestUnlockedAchievements[0],
                                    rank: 1,
                                    crownColor: Color(red: 1.0, green: 0.82, blue: 0.2),
                                    onShare: {
                                        selectedAchievementForShare = (rarestUnlockedAchievements[0].achievement, rarestUnlockedAchievements[0].gameName, rarestUnlockedAchievements[0].gameAppId)
                                    }
                                )
                                .padding(.bottom, 16)
                                
                                // 3rd Place
                                PodiumCard(
                                    item: rarestUnlockedAchievements[2],
                                    rank: 3,
                                    crownColor: Color(red: 0.8, green: 0.5, blue: 0.2),
                                    onShare: {
                                        selectedAchievementForShare = (rarestUnlockedAchievements[2].achievement, rarestUnlockedAchievements[2].gameName, rarestUnlockedAchievements[2].gameAppId)
                                    }
                                )
                            }
                        }
                    }
                    
                    // Top 20 Rarest Gallery
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TOP RAREST UNLOCKS GALLERY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        LazyVStack(spacing: 10) {
                            ForEach(Array(rarestUnlockedAchievements.prefix(20).enumerated()), id: \.element.achievement.apiName) { idx, item in
                                HStack(spacing: 14) {
                                    Text("#\(idx + 1)")
                                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 32)
                                    
                                    RemoteImageView(
                                        url: item.achievement.iconUrl.flatMap { URL(string: $0) },
                                        fallbackSystemName: "trophy.fill",
                                        cornerRadius: 8
                                    )
                                    .frame(width: 44, height: 44)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.achievement.displayName)
                                                .font(.system(size: 14, weight: .bold))
                                            
                                            if let tier = item.achievement.rarityTier {
                                                RarityBadge(tier: tier, percentage: item.achievement.globalPercent, compact: true)
                                            }
                                        }
                                        
                                        HStack(spacing: 6) {
                                            Text(item.gameName)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.accentColor)
                                            
                                            Text("•")
                                                .foregroundColor(.secondary.opacity(0.4))
                                            
                                            if let date = item.achievement.formattedUnlockDate {
                                                Text("Unlocked \(date)")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        selectedAchievementForShare = (item.achievement, item.gameName, item.gameAppId)
                                    }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                                .cornerRadius(10)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(item: Binding(
            get: { selectedAchievementForShare.map { ShareItem(achievement: $0.achievement, gameName: $0.gameName, gameAppId: $0.gameAppId) } },
            set: { if $0 == nil { selectedAchievementForShare = nil } }
        )) { item in
            ShareCardSheet(
                achievement: item.achievement,
                game: state.games.first(where: { $0.appId == item.gameAppId || $0.appId == item.achievement.gameAppId }),
                gameName: item.gameName,
                player: state.player
            )
        }
    }
}

private struct ShareItem: Identifiable {
    var id: String { "\(gameAppId)_\(achievement.apiName)" }
    let achievement: Achievement
    let gameName: String
    let gameAppId: Int
}

private struct PodiumCard: View {
    let item: (achievement: Achievement, gameName: String, gameAppId: Int)
    let rank: Int
    let crownColor: Color
    let onShare: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .foregroundColor(crownColor)
                    .font(.system(size: rank == 1 ? 16 : 13))
                Text("Rank #\(rank)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(crownColor)
            }
            
            RemoteImageView(
                url: item.achievement.iconUrl.flatMap { URL(string: $0) },
                fallbackSystemName: "trophy.fill",
                cornerRadius: 12
            )
            .frame(width: rank == 1 ? 64 : 52, height: rank == 1 ? 64 : 52)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(crownColor, lineWidth: rank == 1 ? 2 : 1)
            )
            
            Text(item.achievement.displayName)
                .font(.system(size: 13, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
            
            Text(item.gameName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            if let pct = item.achievement.globalPercent {
                Text("\(String(format: "%.1f%%", pct)) Rarity")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(crownColor)
            }
            
            Button(action: onShare) {
                Text("Export Card")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(crownColor.opacity(0.15))
                    .foregroundColor(crownColor)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(crownColor.opacity(0.3), lineWidth: rank == 1 ? 1.5 : 0.8)
        )
    }
}
