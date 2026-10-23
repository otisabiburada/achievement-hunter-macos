import SwiftUI
import AppKit

public struct RoadTo100View: View {
    @ObservedObject var state: AppState
    @State private var expandedGameIds: Set<Int> = []
    @State private var tab: PlanTab = .almostThere
    @State private var startedOnly = true
    
    enum PlanTab: String, CaseIterable, Identifiable {
        case almostThere = "Almost There"
        case quickWins = "Quick Wins"
        case today = "Today's Plan"
        var id: String { rawValue }
    }
    
    // Games with at least 60% completion and at least 1 locked achievement
    private var almostThereGames: [SteamGame] {
        state.games.filter { game in
            game.completionPercentage >= 60.0 && game.completionPercentage < 100.0 && game.totalAchievements > 0
        }.sorted { $0.completionPercentage > $1.completionPercentage }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "flag.checkered.2.crossed")
                                .font(.system(size: 24))
                                .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                            Text("Road to 100%")
                                .font(.system(size: 24, weight: .bold))
                        }
                        Text("Games nearest to completion. Focus on the final achievements to turn them into Perfect Games.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(almostThereGames.count) Games In Range")
                            .font(.system(size: 14, weight: .bold))
                        Text("60% - 99% Completed")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
                
                Picker("View", selection: $tab) {
                    ForEach(PlanTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                
                if tab == .quickWins {
                    quickWinsSection
                } else if tab == .today {
                    todaySection
                } else if almostThereGames.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "trophy.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No games currently between 60% and 99% completion.")
                            .font(.system(size: 14, weight: .medium))
                        Text("Play more games or unlock additional achievements to see them appear here.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(almostThereGames) { game in
                            let isExpanded = expandedGameIds.contains(game.appId)
                            let lockedAchievements = game.trackableAchievements.filter { !$0.isUnlocked }
                            
                            VStack(spacing: 0) {
                                // Game summary row
                                HStack(spacing: 14) {
                                    RemoteImageView(
                                        url: game.headerImageUrl,
                                        fallbackSystemName: "gamecontroller.fill",
                                        cornerRadius: 8
                                    )
                                    .frame(width: 80, height: 40)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(game.name)
                                                .font(.system(size: 15, weight: .bold))
                                            Spacer()
                                            Text("\(Int(game.completionPercentage))%")
                                                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                                .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.1))
                                        }
                                        
                                        CustomProgressBar(
                                            value: game.completionPercentage,
                                            height: 5,
                                            isPerfect: false
                                        )
                                        
                                        HStack(spacing: 8) {
                                            Text("Only \(lockedAchievements.count) \(lockedAchievements.count == 1 ? "achievement" : "achievements") remaining!")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.orange)
                                            
                                            if let hours = PlanEngine.hoursLeft(for: game) {
                                                Text("•")
                                                    .foregroundColor(.secondary.opacity(0.4))
                                                Text("\(PlanEngine.hoursText(hours).replacingOccurrences(of: "about ", with: "~")) left at your pace")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                                    .help("A rough estimate: your playtime per unlocked achievement times what remains")
                                            }
                                            
                                            Text("•")
                                                .foregroundColor(.secondary.opacity(0.4))
                                            
                                            Text("\(game.unlockedAchievements) / \(game.totalAchievements) Unlocked")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                if isExpanded {
                                                    expandedGameIds.remove(game.appId)
                                                } else {
                                                    expandedGameIds.insert(game.appId)
                                                }
                                            }) {
                                                HStack(spacing: 4) {
                                                    Text(isExpanded ? "Hide Remaining" : "Show Remaining (\(lockedAchievements.count))")
                                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                                }
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.accentColor)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(14)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                                .cornerRadius(12)
                                
                                // Expandable list of remaining locked achievements
                                if isExpanded {
                                    VStack(spacing: 8) {
                                        ForEach(lockedAchievements) { ach in
                                            HStack(spacing: 12) {
                                                Image(systemName: "lock.fill")
                                                    .foregroundColor(.secondary)
                                                    .font(.system(size: 12))
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack(spacing: 6) {
                                                        Text(ach.displayName)
                                                            .font(.system(size: 13, weight: .bold))
                                                        
                                                        if let tier = ach.rarityTier {
                                                            RarityBadge(tier: tier, percentage: ach.globalPercent, compact: true)
                                                        }
                                                    }
                                                    
                                                    Text(ach.descriptionText.isEmpty ? "Hidden / No description provided." : ach.descriptionText)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(2)
                                                }
                                                
                                                Spacer()
                                                
                                                // Quick Guide button
                                                Button(action: {
                                                    state.openWalkthrough(for: ach, gameName: game.name)
                                                }) {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: "play.tv.fill")
                                                        Text("Guide")
                                                    }
                                                    .font(.system(size: 10, weight: .medium))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.primary.opacity(0.06))
                                                    .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                                
                                                // Pin Target button
                                                Button(action: {
                                                    state.togglePinTarget(achievement: ach, game: game)
                                                }) {
                                                    Image(systemName: state.isTargetPinned(achievement: ach) ? "pin.fill" : "pin")
                                                        .font(.system(size: 11))
                                                        .foregroundColor(state.isTargetPinned(achievement: ach) ? .orange : .secondary)
                                                        .padding(5)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Color.primary.opacity(0.02))
                                            .cornerRadius(8)
                                        }
                                    }
                                    .padding(.top, 6)
                                    .padding(.leading, 20)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: Quick Wins
    
    private var winsToShow: [QuickWin] {
        let all = state.quickWins
        return startedOnly ? all.filter { $0.gameStarted } : all
    }
    
    @ViewBuilder
    private var quickWinsSection: some View {
        let wins = Array(winsToShow.prefix(60))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("The easiest achievements you still lack, across all your games (the ones most players have).")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("Only games I've started", isOn: $startedOnly)
                    .toggleStyle(.switch)
                    .font(.system(size: 11))
            }
            
            if wins.isEmpty {
                Text("Nothing to suggest yet. Sync your library and open a game to see its easiest achievements.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(wins) { win in
                        quickWinRow(win)
                    }
                }
            }
        }
    }
    
    private func quickWinRow(_ win: QuickWin) -> some View {
        let a = win.achievement
        return HStack(spacing: 12) {
            RemoteImageView(url: (a.grayIconUrl ?? a.iconUrl).flatMap { URL(string: $0) }, fallbackSystemName: "lock.fill", cornerRadius: 8)
                .frame(width: 42, height: 42)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(a.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(win.gameName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                if !a.descriptionText.isEmpty {
                    Text(a.descriptionText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text(String(format: "%.0f%% of players", win.percent))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.green)
            
            Menu {
                if let url = WalkthroughLinks.tsaGameURL(gameName: win.gameName) {
                    Button("TrueSteamAchievements Walkthrough") { NSWorkspace.shared.open(url) }
                }
                Button("Find This Achievement") { NSWorkspace.shared.open(WalkthroughLinks.tsaSearchURL(gameName: win.gameName, achievement: a.displayName)) }
                Button("YouTube Walkthrough") { NSWorkspace.shared.open(WalkthroughLinks.youtubeURL(gameName: win.gameName, achievement: a.displayName)) }
            } label: {
                Image(systemName: "play.tv.fill").foregroundColor(.blue).padding(4)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Guides for this achievement")
            
            Button(action: {
                if let game = state.games.first(where: { $0.appId == win.appId }) { state.togglePinTarget(achievement: a, game: game) }
            }) {
                Image(systemName: state.isTargetPinned(achievement: a) ? "pin.fill" : "pin")
                    .foregroundColor(state.isTargetPinned(achievement: a) ? .orange : .secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Pin to Focus Targets")
            
            Button("Open game") { state.openGame(win.appId) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    // MARK: Today's plan
    
    @ViewBuilder
    private var todaySection: some View {
        if let plan = PlanEngine.dailyPlan(games: state.visibleGames) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill").foregroundColor(.orange)
                    Text("Today's target").font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                    Text("(changes every day)").font(.system(size: 11)).foregroundColor(.secondary.opacity(0.7))
                }
                
                HStack(spacing: 16) {
                    RemoteImageView(url: plan.game.headerImageUrl, fallbackSystemName: "gamecontroller.fill", cornerRadius: 10)
                        .frame(width: 184, height: 86)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.game.name).font(.system(size: 20, weight: .bold)).lineLimit(2)
                        CustomProgressBar(value: plan.game.completionPercentage, height: 6, isPerfect: false)
                        HStack(spacing: 10) {
                            Text("\(plan.game.unlockedAchievements) / \(plan.game.totalAchievements) unlocked")
                            Text("•").foregroundColor(.secondary.opacity(0.5))
                            Text("\(plan.remaining) to go").foregroundColor(.orange).fontWeight(.semibold)
                            if let hours = plan.estimatedHours {
                                Text("•").foregroundColor(.secondary.opacity(0.5))
                                Text("\(PlanEngine.hoursText(hours)) at your pace")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open game") { state.openGame(plan.game.appId) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                if !plan.picks.isEmpty {
                    Text("START WITH").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
                    ForEach(plan.picks) { pick in
                        HStack(spacing: 12) {
                            RemoteImageView(url: (pick.grayIconUrl ?? pick.iconUrl).flatMap { URL(string: $0) }, fallbackSystemName: "lock.fill", cornerRadius: 8)
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pick.isHidden ? "Hidden achievement" : pick.displayName).font(.system(size: 13, weight: .bold))
                                if !pick.isHidden, !pick.descriptionText.isEmpty {
                                    Text(pick.descriptionText).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            if let pct = pick.globalPercent {
                                Text(String(format: "%.0f%% of players", pct))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            Button(action: { state.togglePinTarget(achievement: pick, game: plan.game) }) {
                                Image(systemName: state.isTargetPinned(achievement: pick) ? "pin.fill" : "pin")
                                    .foregroundColor(state.isTargetPinned(achievement: pick) ? .orange : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sun.max").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.4))
                Text("No game is close enough to suggest yet.").font(.system(size: 14, weight: .semibold))
                Text("Games that are at least 30% done with 30 or fewer achievements left show up here. Try Quick Wins to find easy ones.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        }
    }
}
