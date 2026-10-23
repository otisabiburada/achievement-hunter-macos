import SwiftUI

public struct ProfileHeaderView: View {
    @ObservedObject var state: AppState
    
    public var body: some View {
        VStack(spacing: 8) {
            // Profile Top Bar
            HStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    RemoteImageView(
                        url: state.player?.avatarImageURL,
                        fallbackSystemName: state.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle.badge.questionmark",
                        cornerRadius: 22
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    
                    // Online status dot
                    Circle()
                        .fill(state.player?.personaState == 1 ? Color.green : (state.isAuthenticated ? Color.blue : Color.gray))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 2))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(state.player?.personaName ?? "Steam Player")
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        
                        if state.isAuthenticated {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Text("\(state.player?.statusText ?? "Ready") • \(state.visibleGames.count) Games")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // If not logged in, show direct "Connect Steam Account" button
            if !state.isAuthenticated {
                Button(action: {
                    state.isLoginPresented = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 12))
                        Text("Connect Steam Account")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            // Overall Stats Card
            if !state.visibleGames.isEmpty {
                VStack(spacing: 6) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                                .font(.system(size: 12))
                            Text("\(state.perfectGamesCount) Perfect")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        
                        Spacer()
                        
                        Text("\(state.totalUnlockedCount) / \(state.totalAchievementsCount) (\(Int(state.overallCompletionPercentage))%)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    CustomProgressBar(
                        value: state.overallCompletionPercentage,
                        height: 5,
                        isPerfect: state.overallCompletionPercentage >= 100.0 && state.totalAchievementsCount > 0
                    )
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(10)
                
                Button(action: { state.isProfileSharePresented = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Profile Card")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Create a shareable image of your stats, games and rarest unlocks (⌘⇧P)")
            }
        }

        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
