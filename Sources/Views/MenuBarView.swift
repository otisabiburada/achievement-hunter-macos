import SwiftUI
import AppKit

public struct MenuBarView: View {
    @ObservedObject var state: AppState
    
    private var activeGame: SteamGame? {
        state.nowPlayingGame ?? state.selectedGame ?? state.games.first
    }
    
    private var recentUnlocks: [(achievement: Achievement, gameName: String)] {
        state.unlockedByTime.prefix(3).map { ($0.achievement, $0.gameName) }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                RemoteImageView(url: state.player?.avatarImageURL, fallbackSystemName: "person.crop.circle.fill", cornerRadius: 14)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.player?.personaName ?? "Steam Player")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(state.perfectGamesCount) Perfect Games • \(Int(state.overallCompletionPercentage))% Completed")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }) {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            Divider()
            
            // Active / Now Playing Game Card
            if let game = activeGame {
                VStack(alignment: .leading, spacing: 6) {
                    if state.isInGame {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 0.2, green: 0.9, blue: 0.4))
                                .frame(width: 6, height: 6)
                            Text("NOW PLAYING")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(Color(red: 0.2, green: 0.9, blue: 0.4))
                                .tracking(0.5)
                        }
                    }
                    
                    HStack {
                        Text(game.name)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(game.completionPercentage))%")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(game.isPerfect ? Color(red: 1.0, green: 0.75, blue: 0.1) : .primary)
                    }
                    
                    CustomProgressBar(value: game.completionPercentage, height: 3, isPerfect: game.isPerfect)
                    
                    HStack {
                        Text("\(game.unlockedAchievements) / \(game.totalAchievements) Unlocked")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(game.playtimeHoursFormatted)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .padding(.horizontal, 14)
            } else {
                VStack(spacing: 4) {
                    Text("No Account Connected")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Open Achievement Hunter to connect your Steam account.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                .padding(.horizontal, 14)
            }
            
            // Recent Unlocks
            if !recentUnlocks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT UNLOCKS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    ForEach(recentUnlocks, id: \.achievement.apiName) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.achievement.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text(item.gameName)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if let pct = item.achievement.globalPercent {
                                Text("\(String(format: "%.1f%%", pct))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Open Achievement Hunter") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 300)
    }
}
