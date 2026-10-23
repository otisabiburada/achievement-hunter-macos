import SwiftUI
import AppKit

public struct NowPlayingView: View {
    @ObservedObject var state: AppState
    
    @State private var selectedFilter: NowPlayingFilter = .locked
    @State private var searchQuery: String = ""
    @State private var sortOption: NowPlayingSort = .rarest
    @State private var isSharePresented: Bool = false
    
    public enum NowPlayingFilter: String, CaseIterable, Identifiable {
        case locked = "Locked (To Unlock)"
        case all = "All Achievements"
        case unlocked = "Unlocked"
        case rare = "Rare (< 10%)"
        case pinned = "Pinned Targets"
        
        public var id: String { rawValue }
    }
    
    public enum NowPlayingSort: String, CaseIterable, Identifiable {
        case rarest = "Rarest First"
        case common = "Most Common"
        case name = "Alphabetical"
        case unlockDate = "Unlock Date"
        
        public var id: String { rawValue }
    }
    
    public init(state: AppState) {
        self.state = state
    }
    
    private var activeGame: SteamGame? {
        state.nowPlayingGame
    }
    
    private var filteredAchievements: [Achievement] {
        guard let game = activeGame else { return [] }
        var list = game.trackableAchievements
        
        switch selectedFilter {
        case .locked:
            list = list.filter { !$0.isUnlocked }
        case .all:
            break
        case .unlocked:
            list = list.filter { $0.isUnlocked }
        case .rare:
            list = list.filter { ($0.globalPercent ?? 100.0) < 10.0 }
        case .pinned:
            list = list.filter { state.isTargetPinned(achievement: $0) }
        }
        
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchQuery.lowercased()
            list = list.filter { $0.displayName.lowercased().contains(q) || $0.descriptionText.lowercased().contains(q) }
        }
        
        switch sortOption {
        case .rarest:
            list.sort { ($0.globalPercent ?? 100.0) < ($1.globalPercent ?? 100.0) }
        case .common:
            list.sort { ($0.globalPercent ?? 0.0) > ($1.globalPercent ?? 0.0) }
        case .name:
            list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .unlockDate:
            list.sort { ($0.unlockTimestamp ?? Date.distantPast) > ($1.unlockTimestamp ?? Date.distantPast) }
        }
        
        return list
    }
    
    public var body: some View {
        Group {
            if let game = activeGame {
                activeGameView(game: game)
            } else {
                noGameView
            }
        }
        .onAppear {
            if let g = activeGame, !g.hasAchievementsLoaded {
                Task {
                    await state.loadAchievements(for: g.appId)
                }
            }
        }
    }
    
    // MARK: - Active In-Game View
    
    @ViewBuilder
    private func activeGameView(game: SteamGame) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero In-Game Live Banner
                ZStack(alignment: .bottomLeading) {
                    // Blurred banner art
                    RemoteImageView(
                        url: game.heroBannerUrl ?? game.headerImageUrl,
                        fallbackSystemName: "gamecontroller.fill",
                        cornerRadius: 18
                    )
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    
                    // Gradient overlay
                    LinearGradient(
                        colors: [Color.black.opacity(0.15), Color.black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    VStack(alignment: .leading, spacing: 10) {
                        // Live Radar Badge & Status
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(red: 0.2, green: 0.9, blue: 0.4))
                                    .frame(width: 8, height: 8)
                                    .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.4), radius: 4)
                                
                                Text("LIVE IN-GAME SESSION")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundColor(Color(red: 0.2, green: 0.9, blue: 0.4))
                                    .tracking(1.2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(red: 0.2, green: 0.9, blue: 0.4).opacity(0.4), lineWidth: 1)
                            )
                            
                            Spacer()
                            
                            // Share Social Card Button
                            Button(action: {
                                isSharePresented = true
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share Card")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.55))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            // Steam Client Launcher
                            if let clientUrl = game.steamClientUrl {
                                Button(action: {
                                    NSWorkspace.shared.open(clientUrl)
                                }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.up.right.square")
                                        Text("Steam Overlay")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.55))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Game Title
                        Text(game.name)
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                        
                        // Playtime and AppID metadata
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.white.opacity(0.7))
                                Text(game.playtimeHoursFormatted)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            
                            Text("•")
                                .foregroundColor(.white.opacity(0.4))
                            
                            Text("App ID: \(game.appId)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(20)
                }
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                
                // Session HUD Metrics Bar
                HStack(spacing: 14) {
                    HudMetricBox(
                        title: "COMPLETION",
                        value: "\(Int(game.completionPercentage))%",
                        subtext: "\(game.unlockedAchievements)/\(game.totalAchievements) Unlocked",
                        color: game.isPerfect ? Color(red: 1.0, green: 0.82, blue: 0.2) : .cyan,
                        icon: "trophy.fill"
                    )
                    
                    HudMetricBox(
                        title: "REMAINING",
                        value: "\(game.lockedAchievements)",
                        subtext: "To 100% Perfect",
                        color: game.lockedAchievements == 0 ? .green : .orange,
                        icon: "lock.open.fill"
                    )
                    
                    HudMetricBox(
                        title: "HUNTING VELOCITY",
                        value: String(format: "%.1f", Double(game.unlockedAchievements) / max(1.0, Double(game.playtimeMinutes) / 60.0)),
                        subtext: "Unlocks / hour",
                        color: Color(red: 0.2, green: 0.85, blue: 0.5),
                        icon: "bolt.fill"
                    )
                    
                    HudMetricBox(
                        title: "DISCORD STATUS",
                        value: "Broadcasting",
                        subtext: "Rich Presence Active",
                        color: Color(red: 0.35, green: 0.45, blue: 1.0),
                        icon: "antenna.radiowaves.left.and.right"
                    )
                }
                
                // "Grind Radar / Next to Unlock" Priority Carousel
                if game.lockedAchievements > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "target")
                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.3))
                            Text("NEXT TO UNLOCK (SESSION RADAR)")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.3))
                                .tracking(1.0)
                            Spacer()
                            Text("Rarest Locked Targets")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        let nextTargets = game.trackableAchievements
                            .filter { !$0.isUnlocked }
                            .sorted { ($0.globalPercent ?? 100) < ($1.globalPercent ?? 100) }
                            .prefix(3)
                        
                        HStack(spacing: 12) {
                            ForEach(Array(nextTargets), id: \.apiName) { ach in
                                NextTargetQuickCard(achievement: ach, gameName: game.name, appId: game.appId, state: state)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Achievement Search & Filter Toolbar
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("ACTIVE GAME ACHIEVEMENTS (\(filteredAchievements.count))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Sort Dropdown
                        Picker("Sort", selection: $sortOption) {
                            ForEach(NowPlayingSort.allCases) { opt in
                                Text(opt.rawValue).tag(opt)
                            }
                        }
                        .frame(width: 170)
                    }
                    
                    HStack(spacing: 10) {
                        // Filter Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(NowPlayingFilter.allCases) { f in
                                    let isSel = selectedFilter == f
                                    Button(action: { selectedFilter = f }) {
                                        Text(f.rawValue)
                                            .font(.system(size: 11, weight: isSel ? .bold : .medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(isSel ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.6))
                                            .foregroundColor(isSel ? .white : .primary)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Search Field
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            TextField("Search achievements...", text: $searchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(6)
                        .frame(width: 200)
                    }
                }
                
                // Achievements List
                if filteredAchievements.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No achievements match this filter.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredAchievements) { ach in
                            AchievementCardView(
                                achievement: ach,
                                gameName: game.name,
                                appId: game.appId,
                                state: state
                            )
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $isSharePresented) {
            ShareCardSheet(game: game, player: state.player)
        }
    }
    
    // MARK: - No Game Detected Fallback Screen
    
    private var noGameView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 110, height: 110)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Color.secondary.opacity(0.5))
            }
            
            VStack(spacing: 6) {
                Text("No Active In-Game Session Detected")
                    .font(.system(size: 20, weight: .bold))
                Text("Launch a Steam game on this Mac, PC, or Steam Deck. Achievement Hunter will detect it in real time and display your live hunting session and achievements right here.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            
            // So a stall is visible instead of guessed at: when Steam's status was last read, and a way to ask again.
            HStack(spacing: 10) {
                if let checked = state.lastStatusCheckAt {
                    Text("Steam status checked \(checked.formatted(.relative(presentation: .named)))")
                } else {
                    Text(state.lastStatusCheckFailed ? "Couldn't reach Steam" : "Checking Steam...")
                }
                Button("Check now") { Task { await state.refreshPlayerStatus() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - HUD Metric Box

private struct HudMetricBox: View {
    let title: String
    let value: String
    let subtext: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.secondary)
                    .tracking(1.0)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
            }
            
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
            
            Text(subtext)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Next Target Quick Card

private struct NextTargetQuickCard: View {
    let achievement: Achievement
    let gameName: String
    let appId: Int
    @ObservedObject var state: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            RemoteImageView(
                url: achievement.iconUrl.flatMap { URL(string: $0) },
                fallbackSystemName: "lock.fill",
                cornerRadius: 10
            )
            .frame(width: 44, height: 44)
            .saturation(0.0)
            .opacity(0.7)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(achievement.rarityTier?.color.opacity(0.5) ?? Color.secondary.opacity(0.2), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(achievement.descriptionText.isEmpty ? "Secret achievement" : achievement.descriptionText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let pct = achievement.globalPercent {
                    Text("\(String(format: "%.1f%%", pct)) of players")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(achievement.rarityTier?.color ?? .secondary)
                }
            }
            
            Spacer()
            
            // Quick pin target button
            Button(action: {
                state.togglePinTarget(achievement: achievement, gameName: gameName, appId: appId)
            }) {
                Image(systemName: state.isTargetPinned(achievement: achievement) ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundColor(state.isTargetPinned(achievement: achievement) ? .orange : .secondary)
                    .padding(6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            // Guide walkthrough button
            Button(action: {
                state.openWalkthrough(for: achievement, gameName: gameName)
            }) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
