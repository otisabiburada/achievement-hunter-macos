import SwiftUI

public struct SidebarView: View {
    @ObservedObject var state: AppState
    @FocusState private var searchFocused: Bool
    
    // MARK: Collapsible navigation
    
    @AppStorage("sidebar_collapsed_groups") private var collapsedGroupsRaw: String = "Insights,Share & Compare"
    @AppStorage("sidebar_games_collapsed") private var gamesCollapsed: Bool = false
    
    private var collapsedGroupSet: Set<String> {
        Set(collapsedGroupsRaw.split(separator: ",").map(String.init))
    }
    
    private func toggleGroup(_ name: String) {
        var set = collapsedGroupSet
        if set.contains(name) { set.remove(name) } else { set.insert(name) }
        collapsedGroupsRaw = set.sorted().joined(separator: ",")
    }
    
    @ViewBuilder
    private func navRow(_ section: NavigationSection) -> some View {
                    let isSelected = state.selectedSection == section
                    Button(action: {
                        state.selectedSection = section
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: section.iconName)
                                .font(.system(size: 13))
                                .foregroundColor(isSelected ? .white : (section == .nowPlaying && state.isInGame ? Color(red: 0.2, green: 0.9, blue: 0.4) : .accentColor))
                                .frame(width: 18)
                            
                            Text(section.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            
                            Spacer()
                            
                            if section == .nowPlaying && state.isInGame {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(Color(red: 0.2, green: 0.9, blue: 0.4))
                                        .frame(width: 5, height: 5)
                                    Text("LIVE")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundColor(isSelected ? .white : Color(red: 0.2, green: 0.9, blue: 0.4))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.25) : Color(red: 0.2, green: 0.9, blue: 0.4).opacity(0.2))
                                .cornerRadius(4)
                            }
                            
                            if section == .activity && state.unseenUnlockCount > 0 {
                                Text("\(state.unseenUnlockCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? Color.white.opacity(0.3) : Color.orange)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                            
                            if section == .focusTargets && !state.pinnedTargets.isEmpty {
                                Text("\(state.pinnedTargets.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? Color.white.opacity(0.3) : Color.orange)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Profile & overall stats
            ProfileHeaderView(state: state)
            
            // If user is currently in game, display a prominent live banner
            if let game = state.nowPlayingGame {
                Button(action: {
                    state.selectedSection = .nowPlaying
                }) {
                    HStack(spacing: 10) {
                        RemoteImageView(
                            url: game.headerImageUrl,
                            fallbackSystemName: "gamecontroller.fill",
                            cornerRadius: 6
                        )
                        .frame(width: 44, height: 24)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(red: 0.2, green: 0.9, blue: 0.4))
                                    .frame(width: 6, height: 6)
                                Text("NOW PLAYING")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundColor(Color(red: 0.2, green: 0.9, blue: 0.4))
                                    .tracking(0.5)
                            }
                            Text(game.name)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Text("\(Int(game.completionPercentage))%")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color.accentColor)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.2, green: 0.9, blue: 0.4).opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color(red: 0.2, green: 0.9, blue: 0.4).opacity(0.4), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
            
            // Section Navigation: groups can be collapsed to give the game list more room
            VStack(spacing: 1) {
                ForEach(["Library", "Hunt", "Insights", "Share & Compare"], id: \.self) { groupName in
                    let members = NavigationSection.allCases.filter { $0.group == groupName }
                    let isCollapsed = collapsedGroupSet.contains(groupName)
                    
                    Button(action: { toggleGroup(groupName) }) {
                        HStack(spacing: 4) {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .frame(width: 10)
                            Text(groupName.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .kerning(0.8)
                            Spacer()
                            if isCollapsed {
                                // collapsed: the group's sections stay reachable as small icons
                                HStack(spacing: 8) {
                                    ForEach(members) { section in
                                        Button(action: { state.selectedSection = section }) {
                                            Image(systemName: section.iconName)
                                                .font(.system(size: 11))
                                                .foregroundColor(state.selectedSection == section ? .accentColor : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(section.rawValue)
                                    }
                                }
                            }
                        }
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.top, groupName == "Library" ? 0 : 5)
                        .padding(.bottom, 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Show \(groupName)" : "Hide \(groupName)")
                    
                    if !isCollapsed {
                        ForEach(members) { section in
                            navRow(section)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            
            Divider()
            
            // If in Library section, show Game Search, Filter, and Game List
            if state.selectedSection == .library {
                // Header: collapse the whole game list to a single line
                Button(action: { withAnimation(.easeInOut(duration: 0.18)) { gamesCollapsed.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: gamesCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 10)
                        Text("GAMES")
                            .font(.system(size: 9, weight: .heavy))
                            .kerning(0.8)
                        Text("\(state.filteredGames.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                        Spacer()
                        Text(gamesCollapsed ? "Show" : "Hide")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(gamesCollapsed ? "Show the game list" : "Hide the game list")
                
                if !gamesCollapsed {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    
                    TextField("Find a game...  (⌘F)", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($searchFocused)
                        .onSubmit {
                            if let first = state.filteredGames.first { state.openGame(first.appId) }
                        }
                    
                    if !state.searchQuery.isEmpty {
                        Button(action: { state.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .onChange(of: state.searchFocusToken) { _, _ in
                    DispatchQueue.main.async { searchFocused = true }
                }
                
                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(GameFilter.allCases) { filter in
                            let isSelected = state.selectedFilter == filter
                            Button(action: {
                                state.selectedFilter = filter
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: filter.iconName)
                                        .font(.system(size: 10))
                                    Text(filter.rawValue)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                                )
                                .foregroundColor(isSelected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 4)
                
                HStack(spacing: 8) {
                    Menu {
                        Picker("Sort by", selection: $state.gameSort) {
                            ForEach(GameSort.allCases) { sort in
                                Label(sort.rawValue, systemImage: sort.iconName).tag(sort)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(state.gameSort.rawValue)
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    
                    Spacer()
                    
                    Button(action: { state.hideGamesWithoutAchievements.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: state.hideGamesWithoutAchievements ? "eye.slash.fill" : "eye.fill")
                            Text(state.hideGamesWithoutAchievements
                                 ? (state.hiddenGamesCount > 0 ? "\(state.hiddenGamesCount) hidden" : "No-achievement games hidden")
                                 : "Showing all games")
                        }
                        .font(.system(size: 10))
                        .foregroundColor(state.hideGamesWithoutAchievements ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(state.hideGamesWithoutAchievements
                          ? "Games without achievements are hidden and not re-synced. Click to show them."
                          : "Click to hide games that have no achievements (and skip syncing them).")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
                
                Divider()
                
                // Game List
                if state.filteredGames.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No games match filter")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // A lazy stack instead of a List: no NSTableView re-entrancy warnings, cheaper updates with
                    // thousands of games, and the rows draw their own selection.
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(state.filteredGames, id: \.appId) { game in
                                GameRowView(
                                    game: game,
                                    isSelected: state.selectedGameId == game.appId
                                )
                                .onTapGesture {
                                    state.selectedGameId = game.appId
                                    Task {
                                        await state.loadAchievements(for: game.appId)
                                    }
                                }
                                .contextMenu {
                                    if let url = game.storeUrl { Button("Open Store Page") { NSWorkspace.shared.open(url) } }
                                    if let url = game.steamClientUrl { Button("Open in Steam") { NSWorkspace.shared.open(url) } }
                                    if let url = WalkthroughLinks.tsaGameURL(gameName: game.name) { Button("TrueSteamAchievements Walkthrough") { NSWorkspace.shared.open(url) } }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                }
                } else {
                    Spacer()
                }
            } else {
                Spacer()
            }
            
            Divider()
            
            // Bottom Action Bar
            HStack(spacing: 8) {
                Button(action: {
                    state.isSettingsPresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                if state.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                }
                
                Button(action: {
                    if state.isAuthenticated, let id = state.authenticatedSteamId {
                        Task {
                            await state.fetchDirectlyFromAccount(steamId: id)
                        }
                    } else {
                        Task {
                            await state.syncWithSteam()
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(state.isLoading ? 360 : 0))
                            .animation(state.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: state.isLoading)
                        Text("Sync")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(state.isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
}
