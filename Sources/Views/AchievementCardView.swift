import SwiftUI
import AppKit

public struct AchievementCardView: View {
    public let achievement: Achievement
    public let gameName: String
    public let appId: Int
    @ObservedObject var state: AppState
    
    @State private var isRevealed: Bool = false
    @State private var isSharePresented: Bool = false
    
    public init(achievement: Achievement, gameName: String = "", appId: Int = 0, state: AppState) {
        self.achievement = achievement
        self.gameName = gameName
        self.appId = appId
        self.state = state
    }
    
    private var isHiddenLocked: Bool {
        achievement.isHidden && !achievement.isUnlocked && !isRevealed
    }
    
    private var isPinned: Bool {
        state.isTargetPinned(achievement: achievement)
    }
    
    /// Achievement Set / DLC / archived badge for this achievement.
    private var setBadge: (text: String, color: Color)? {
        if achievement.isArchived == true { return ("ARCHIVED", .gray) }
        guard let game = state.games.first(where: { $0.appId == appId || $0.appId == achievement.gameAppId }),
              let g = game.group(achievement.groupId), game.hasMultipleSets else { return nil }
        if g.isDLC { return ("DLC · \(g.displayName)", .purple) }
        if g.groupId == 0 { return nil }
        return (g.displayName, .blue)
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon
            ZStack(alignment: .bottomTrailing) {
                RemoteImageView(
                    url: achievement.isUnlocked ? (achievement.iconUrl.flatMap { URL(string: $0) }) : (achievement.grayIconUrl.flatMap { URL(string: $0) } ?? achievement.iconUrl.flatMap { URL(string: $0) }),
                    fallbackSystemName: achievement.isUnlocked ? "trophy.fill" : "lock.fill",
                    cornerRadius: 10
                )
                .frame(width: 56, height: 56)
                .saturation(achievement.isUnlocked ? 1.0 : 0.0)
                .opacity(achievement.isUnlocked ? 1.0 : 0.5)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            achievement.isUnlocked
                                ? (achievement.rarityTier?.color.opacity(0.5) ?? Color.accentColor.opacity(0.3))
                                : Color.secondary.opacity(0.2),
                            lineWidth: achievement.isUnlocked ? 1.5 : 1
                        )
                )
                
                // Status badge
                if achievement.isUnlocked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                        .offset(x: 4, y: 4)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(3)
                        .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                        .offset(x: 4, y: 4)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
                    Text(achievement.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(achievement.isUnlocked ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let tier = achievement.rarityTier {
                        RarityBadge(tier: tier, percentage: achievement.globalPercent, compact: false)
                    }
                    
                    // Pin to Focus Targets Button
                    Button(action: {
                        state.togglePinTarget(achievement: achievement, gameName: gameName, appId: appId)
                    }) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 12))
                            .foregroundColor(isPinned ? .orange : .secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(isPinned ? "Unpin from Focus Targets" : "Pin to Focus Targets Dashboard")
                    
                    // Walkthrough / Guide Button
                    Menu {
                        Section("TrueSteamAchievements") {
                            if let url = WalkthroughLinks.tsaGameURL(gameName: gameName) {
                                Button("Game Walkthrough") { NSWorkspace.shared.open(url) }
                            }
                            Button("Find This Achievement") {
                                NSWorkspace.shared.open(WalkthroughLinks.tsaSearchURL(gameName: gameName, achievement: achievement.displayName))
                            }
                        }
                        Section("More guides") {
                            Button("YouTube Walkthrough Video") {
                                NSWorkspace.shared.open(WalkthroughLinks.youtubeURL(gameName: gameName, achievement: achievement.displayName))
                            }
                            if appId > 0 {
                                Button("Steam Community Guides") {
                                    NSWorkspace.shared.open(WalkthroughLinks.steamGuidesURL(appId: appId, achievement: nil))
                                }
                            }
                            Button("Search Google for Guide") {
                                NSWorkspace.shared.open(WalkthroughLinks.googleURL(gameName: gameName, achievement: achievement.displayName))
                            }
                        }
                    } label: {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                            .padding(4)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Open Achievement Guides & Walkthroughs")
                    
                    // Share Card Button
                    Button(action: {
                        isSharePresented = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Export High-Res Achievement Card")
                }
                
                // Description (with spoiler shield for hidden achievements)
                if isHiddenLocked {
                    HStack(spacing: 6) {
                        Text("Hidden Secret Achievement")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.8))
                            .italic()
                        
                        Button(action: {
                            isRevealed = true
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "eye.fill")
                                Text("Reveal")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 1)
                } else {
                    Text(achievement.descriptionText.isEmpty ? "No description provided." : achievement.descriptionText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
                
                // Tags Bar & Tag Selector
                HStack(spacing: 6) {
                    ForEach(state.getTags(for: achievement.apiName)) { tag in
                        HStack(spacing: 3) {
                            Image(systemName: tag.iconName)
                                .font(.system(size: 9))
                            Text(tag.rawValue)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tag.color.opacity(0.12))
                        .foregroundColor(tag.color)
                        .cornerRadius(4)
                    }
                    
                    // Tag Adder Menu
                    Menu {
                        ForEach(AchievementTag.allCases) { tag in
                            Button(tag.rawValue) {
                                state.toggleTag(tag, for: achievement.apiName)
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                            Text("Tag")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.top, 2)
                
                Spacer(minLength: 2)
                
                // Metadata Footer
                HStack(spacing: 8) {
                    if let unlockDate = achievement.formattedUnlockDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                            Text("Unlocked \(unlockDate)")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.green.opacity(0.85))
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                            Text("Locked")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                    }
                    
                    if let badge = setBadge {
                        Text(badge.text)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badge.color.opacity(0.15))
                            .foregroundColor(badge.color)
                            .clipShape(Capsule())
                    }
                    
                    if achievement.isHidden {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        HStack(spacing: 3) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 9))
                            Text("Hidden")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            achievement.isUnlocked
                                ? Color.primary.opacity(0.08)
                                : Color.primary.opacity(0.04),
                            lineWidth: 1
                        )
                )
        )
        .sheet(isPresented: $isSharePresented) {
            ShareCardSheet(
                achievement: achievement,
                game: state.games.first(where: { $0.appId == appId || $0.appId == achievement.gameAppId }),
                gameName: gameName,
                player: state.player
            )
        }
    }
}
