import SwiftUI
import AppKit

public enum AchievementFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unlocked = "Unlocked"
    case locked = "Locked"
    case hidden = "Secret"
    
    public var id: String { rawValue }
}

public enum AchievementSort: String, CaseIterable, Identifiable {
    case defaultOrder = "Default"
    case rarestFirst = "Rarest First"
    case recentFirst = "Recent Unlocks"
    case nameAscending = "Name (A-Z)"
    
    public var id: String { rawValue }
}

public struct GameDetailView: View {
    public let game: SteamGame
    @ObservedObject var state: AppState
    
    @State private var filter: AchievementFilter = .all
    @State private var sort: AchievementSort = .defaultOrder
    @State private var searchQuery: String = ""
    @State private var isSharePresented: Bool = false
    @State private var selectedSetId: Int? = nil
    
    public init(game: SteamGame, state: AppState) {
        self.game = game
        self.state = state
    }
    
    private var filteredAchievements: [Achievement] {
        // Selecting a set shows all of its achievements (even DLC you don't own); otherwise only the ones
        // that count toward this game's completion (Steam hides archived ones you missed).
        var list = selectedSetId == nil
            ? game.trackableAchievements
            : game.achievements.filter { ($0.groupId ?? 0) == selectedSetId }
        
        switch filter {
        case .all:
            break
        case .unlocked:
            list = list.filter { $0.isUnlocked }
        case .locked:
            list = list.filter { !$0.isUnlocked }
        case .hidden:
            list = list.filter { $0.isHidden }
        }
        
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchQuery.lowercased()
            list = list.filter {
                $0.displayName.lowercased().contains(q) ||
                $0.descriptionText.lowercased().contains(q)
            }
        }
        
        switch sort {
        case .defaultOrder:
            break
        case .rarestFirst:
            list = list.sorted {
                ($0.globalPercent ?? 100.0) < ($1.globalPercent ?? 100.0)
            }
        case .recentFirst:
            list = list.sorted {
                let d0 = $0.unlockTimestamp ?? Date.distantPast
                let d1 = $1.unlockTimestamp ?? Date.distantPast
                return d0 > d1
            }
        case .nameAscending:
            list = list.sorted { $0.displayName < $1.displayName }
        }
        
        return list
    }
    
    private var rarestUnlockedAchievement: Achievement? {
        game.achievements
            .filter { $0.isUnlocked && $0.globalPercent != nil }
            .min { ($0.globalPercent ?? 100.0) < ($1.globalPercent ?? 100.0) }
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero Header
                ZStack(alignment: .bottomLeading) {
                    // Artwork: Color.clear gives the banner a fixed size, so a scaled-to-fill image can't
                    // widen the layout or push the buttons out of view.
                    Color.clear
                        .overlay(
                            RemoteImageView(
                                url: game.heroBannerUrl,
                                fallbackSystemName: "gamecontroller.fill",
                                cornerRadius: 0
                            )
                        )
                        .clipped()
                    
                    // Scrim for text legibility: transparent on top, deep at the bottom
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.0), location: 0.0),
                            .init(color: Color.black.opacity(0.30), location: 0.45),
                            .init(color: Color.black.opacity(0.88), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(game.name)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .shadow(color: Color.black.opacity(0.55), radius: 4, x: 0, y: 1)
                            
                            if game.isPerfect {
                                HStack(spacing: 4) {
                                    Image(systemName: "crown.fill")
                                    Text("100% PERFECT")
                                }
                                .font(.system(size: 11, weight: .heavy))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 1.0, green: 0.82, blue: 0.2))
                                .foregroundColor(.black)
                                .clipShape(Capsule())
                                .fixedSize()
                            }
                        }
                        
                        HStack(spacing: 10) {
                            Label(game.playtimeHoursFormatted, systemImage: "clock.fill")
                            Text("•").opacity(0.5)
                            Text("App ID: \(game.appId)")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.88))
                        .shadow(color: Color.black.opacity(0.6), radius: 3, x: 0, y: 1)
                        
                        HStack(spacing: 8) {
                            BannerButton(
                                title: game.isPerfect ? "Share 100% Card" : "Share Card",
                                icon: "square.and.arrow.up.fill",
                                style: game.isPerfect ? .gold : .glass
                            ) {
                                isSharePresented = true
                            }
                            
                            if let storeUrl = game.storeUrl {
                                BannerButton(title: "Store", icon: "cart.fill", style: .glass) {
                                    NSWorkspace.shared.open(storeUrl)
                                }
                            }
                            
                            BannerMenuButton(title: "Walkthroughs", icon: "play.tv.fill") {
                                if let url = WalkthroughLinks.tsaGameURL(gameName: game.name) {
                                    Button("TrueSteamAchievements Walkthrough") { NSWorkspace.shared.open(url) }
                                }
                                Button("Find on TrueSteamAchievements") {
                                    NSWorkspace.shared.open(WalkthroughLinks.tsaSearchURL(gameName: game.name, achievement: nil))
                                }
                                Divider()
                                Button("Steam Community Guides") {
                                    NSWorkspace.shared.open(WalkthroughLinks.steamGuidesURL(appId: game.appId, achievement: nil))
                                }
                                Button("YouTube Achievement Guides") {
                                    NSWorkspace.shared.open(WalkthroughLinks.youtubeURL(gameName: game.name, achievement: nil))
                                }
                            }
                            
                            if let clientUrl = game.steamClientUrl {
                                BannerButton(title: "Open in Steam", icon: "arrow.up.right.square.fill", style: .accent) {
                                    NSWorkspace.shared.open(clientUrl)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                // One soft shadow for the whole banner (it used to be on the image only, which looked uneven)
                .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 8)
                .padding(.bottom, 6)
                
                if let error = game.loadError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.hasAchievementsLoaded ? "Couldn't refresh achievements (showing saved data)" : "Couldn't load achievements")
                                .font(.system(size: 12, weight: .semibold))
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Retry") {
                            Task { await state.loadAchievements(for: game.appId) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(10)
                } else if !game.hasAchievementsLoaded {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.6)
                        Text("Loading achievements...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(10)
                }
                
                // Statistics Summary Cards
                HStack(spacing: 14) {
                    // Progress Gauge Card
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(max(0.0, min(100.0, game.completionPercentage)) / 100.0))
                                .stroke(
                                    game.isPerfect
                                        ? Color(red: 1.0, green: 0.82, blue: 0.2)
                                        : Color.accentColor,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                            
                            VStack(spacing: 1) {
                                Text("\(Int(game.completionPercentage))%")
                                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                            }
                        }
                        .frame(width: 58, height: 58)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Completion Rate")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("\(game.unlockedAchievements) of \(game.totalAchievements) Unlocked")
                                .font(.system(size: 14, weight: .bold))
                            Text("\(game.lockedAchievements) remaining")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(12)
                    
                    // Rarest Achievement Card
                    if let rarest = rarestUnlockedAchievement {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.15))
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                            }
                            .frame(width: 44, height: 44)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Rarest Unlocked")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(rarest.displayName)
                                    .font(.system(size: 13, weight: .bold))
                                    .lineLimit(1)
                                if let pct = rarest.globalPercent {
                                    Text("Only \(String(format: "%.1f%%", pct)) of players have this")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.1))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(12)
                    }
                }
                
                if game.hasMultipleSets {
                    AchievementSetsPanel(game: game, state: state, selectedSetId: $selectedSetId)
                }
                
                // Toolbar (Filter, Search, Sort)
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Picker("Filter", selection: $filter) {
                            Text("All (\(game.totalAchievements))").tag(AchievementFilter.all)
                            Text("Unlocked (\(game.unlockedAchievements))").tag(AchievementFilter.unlocked)
                            Text("Locked (\(game.lockedAchievements))").tag(AchievementFilter.locked)
                            Text("Secret (\(game.trackableAchievements.filter { $0.isHidden }.count))").tag(AchievementFilter.hidden)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("Filter achievements")
                        .frame(maxWidth: 460)
                        
                        Spacer()
                        
                        Menu {
                            Picker("Sort By", selection: $sort) {
                                ForEach(AchievementSort.allCases) { s in
                                    Text(s.rawValue).tag(s)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(sort.rawValue)
                            }
                            .font(.system(size: 12))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        
                        TextField("Search achievements by title or description...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                        
                        if !searchQuery.isEmpty {
                            Button(action: { searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
                
                // Achievements List
                if filteredAchievements.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "trophy")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(game.totalAchievements == 0 ? "No achievements available for this game." : "No achievements match your filters.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredAchievements) { achievement in
                            AchievementCardView(
                                achievement: achievement,
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
        .onAppear {
            DiscordRPCService.shared.updatePresence(game: game, player: state.player)
        }
    }
}

/// Pill buttons for the game banner: consistent size, a hairline border and a soft shadow so they stay
/// readable on any artwork.
private struct BannerButton: View {
    enum Style { case glass, accent, gold }
    
    let title: String
    let icon: String
    let style: Style
    let action: () -> Void
    
    @State private var hovering = false
    
    private var fill: Color {
        switch style {
        case .glass: return Color.white.opacity(hovering ? 0.28 : 0.18)
        case .accent: return Color(red: 0.12, green: 0.55, blue: 1.0).opacity(hovering ? 1.0 : 0.92)
        case .gold: return Color(red: 1.0, green: 0.82, blue: 0.2).opacity(hovering ? 1.0 : 0.94)
        }
    }
    
    private var foreground: Color {
        style == .gold ? .black : .white
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(style == .glass ? 0.22 : 0.12), lineWidth: 1)
            )
            .foregroundColor(foreground)
            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Same look as `BannerButton`, but opens a menu.
private struct BannerMenuButton<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    @State private var hovering = false
    
    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.white.opacity(hovering ? 0.28 : 0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

/// Steam Achievement Sets: one progress card per set (base game, DLC, archived), tap to filter the list.
private struct AchievementSetsPanel: View {
    let game: SteamGame
    @ObservedObject var state: AppState
    @Binding var selectedSetId: Int?
    
    private var groups: [AchievementGroup] {
        (game.achievementGroups ?? []).filter { !$0.isDeveloperOnly }
    }
    
    private func stats(_ g: AchievementGroup) -> (unlocked: Int, total: Int, accessible: Bool) {
        let all = game.achievements.filter { ($0.groupId ?? 0) == g.groupId }
        let counted = all.filter { !($0.isArchived == true && !$0.isUnlocked) }
        return (counted.filter { $0.isUnlocked }.count, counted.count, game.isGroupAccessible(g.groupId))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACHIEVEMENT SETS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                if selectedSetId != nil {
                    Button("Show all") { selectedSetId = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(groups) { g in
                        card(g)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    private func card(_ g: AchievementGroup) -> some View {
        let st = stats(g)
        let isSelected = selectedSetId == g.groupId
        let tint: Color = g.isDLC ? .purple : .accentColor
        let complete = st.total > 0 && st.unlocked == st.total
        let pct = st.total > 0 ? Double(st.unlocked) / Double(st.total) * 100 : 0
        
        return Button(action: { selectedSetId = isSelected ? nil : g.groupId }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    if complete {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                    }
                    Text(g.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if g.isDLC {
                        Text("DLC").font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.2)).foregroundColor(.purple).clipShape(Capsule())
                    }
                    if g.isArchived {
                        Text("ARCHIVED").font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.gray.opacity(0.2)).foregroundColor(.gray).clipShape(Capsule())
                    }
                }
                CustomProgressBar(value: pct, height: 4, isPerfect: complete)
                HStack {
                    Text("\(st.unlocked) / \(st.total)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer()
                    if g.isDLC && !st.accessible {
                        Text("Not owned")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else if g.isDLC, game.dlcOverrides?["\(g.groupId)"] == nil, g.ownedByPlayer == true {
                        Label("Owned", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.purple)
                            .help("Steam lists this DLC set for your account")
                    } else {
                        Text("\(Int(pct))%").font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                }
                .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(width: 200)
            .opacity(g.isDLC && !st.accessible ? 0.65 : 1)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.14) : Color(NSColor.controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if g.isDLC {
                Button("I own this DLC") { state.setDLCOwned(true, groupId: g.groupId, appId: game.appId) }
                Button("I don't own this DLC") { state.setDLCOwned(false, groupId: g.groupId, appId: game.appId) }
                Button("Use what Steam says") { state.setDLCOwned(nil, groupId: g.groupId, appId: game.appId) }
            }
        }
        .help(g.isDLC ? "Right-click to say whether you own this DLC. DLC sets only count toward completion when you have access to them." : "Show only this set")
    }
}
