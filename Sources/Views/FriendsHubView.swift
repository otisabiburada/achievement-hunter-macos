import SwiftUI

/// Compare you against several friends at once: one column per friend, one row per shared game.
@MainActor
final class MultiCompareModel: ObservableObject {
    @Published var selected: [String] = []
    @Published var counts: [String: [Int: (unlocked: Int, total: Int)]] = [:]
    @Published var isRunning = false
    @Published var message: String?
    private var task: Task<Void, Never>?
    static let maxFriends = 4
    
    func toggle(_ id: String) {
        if let i = selected.firstIndex(of: id) { selected.remove(at: i); counts[id] = nil }
        else if selected.count < Self.maxFriends { selected.append(id) }
    }
    
    func run(friends: [SteamPlayer], state: AppState) {
        task?.cancel()
        message = nil
        counts = [:]
        let chosen = friends.filter { selected.contains($0.steamId) }
        let mine = state.games.filter { $0.hasAchievementsLoaded && $0.totalAchievements > 0 }
        let totals = Dictionary(mine.map { ($0.appId, $0.totalAchievements) }, uniquingKeysWith: { a, _ in a })
        guard !chosen.isEmpty, !mine.isEmpty else { return }
        isRunning = true
        let auth = state.activeAuth
        task = Task { [weak self] in
            for friend in chosen {
                if Task.isCancelled { break }
                guard let owned = try? await SteamAPIService.shared.fetchOwnedGames(steamId: friend.steamId, auth: auth ?? SteamAuth()) else {
                    self?.message = "\(friend.personaName)'s game details are private, so they are left out."
                    continue
                }
                let ownedIds = Set(owned.map { $0.appId })
                let shared = mine.map { $0.appId }.filter { ownedIds.contains($0) }
                var result: [Int: (unlocked: Int, total: Int)] = [:]
                await withTaskGroup(of: (Int, Int?).self) { group in
                    var it = shared.makeIterator()
                    func next() {
                        if let id = it.next() {
                            group.addTask {
                                guard let rows = try? await SteamAPIService.shared.fetchUserAchievements(steamId: friend.steamId, appId: id, auth: auth) else { return (id, nil) }
                                return (id, rows.filter { $0.unlocked }.count)
                            }
                        }
                    }
                    for _ in 0..<6 { next() }
                    while let (id, n) = await group.next() {
                        if Task.isCancelled { group.cancelAll(); break }
                        if let n = n, let total = totals[id] { result[id] = (min(n, total), total) }
                        next()
                    }
                }
                self?.counts[friend.steamId] = result
            }
            self?.isRunning = false
        }
    }
}

struct FriendsHubView: View {
    @ObservedObject var state: AppState
    @ObservedObject var watcher: FriendWatcher
    let friends: [SteamPlayer]
    @StateObject private var multi = MultiCompareModel()
    @State private var showMulti = false
    
    private var favoriteFriends: [SteamPlayer] { friends.filter { watcher.isFavorite($0.steamId) } }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            favoritesCard
            if !watcher.alerts.isEmpty { alertsCard }
            DisclosureGroup(isExpanded: $showMulti) { multiBody.padding(.top, 8) } label: {
                Label("Compare several friends at once", systemImage: "person.3.fill").font(.system(size: 13, weight: .bold))
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private var favoritesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Favorite friends", systemImage: "star.fill").font(.system(size: 13, weight: .bold)).foregroundColor(.yellow)
                Spacer()
                if let t = watcher.lastChecked { Text("checked \(t.formatted(.relative(presentation: .named)))").font(.system(size: 10)).foregroundColor(.secondary) }
                Button("Check now") { Task { await watcher.check(state: state) } }.controlSize(.small)
            }
            Text("Star up to \(FriendWatcher.maxFavorites) friends to see what they are playing and get a heads-up when they unlock something rare or finish a game you also own.")
                .font(.system(size: 11)).foregroundColor(.secondary)
            
            Menu {
                ForEach(friends) { f in
                    Button(action: { watcher.toggleFavorite(f.steamId) }) {
                        Label(f.personaName, systemImage: watcher.isFavorite(f.steamId) ? "star.fill" : "star")
                    }
                }
            } label: { Label("Choose favorites", systemImage: "star") }
            .menuStyle(.borderlessButton).fixedSize()
            
            ForEach(favoriteFriends) { f in
                let live = watcher.live[f.steamId]
                HStack(spacing: 10) {
                    RemoteImageView(url: (live ?? f).avatarImageURL, fallbackSystemName: "person.crop.circle.fill", cornerRadius: 14).frame(width: 28, height: 28)
                    Text(f.personaName).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if let game = live?.currentGameName {
                        Label(game, systemImage: "gamecontroller.fill").font(.system(size: 11)).foregroundColor(.green)
                    } else {
                        Text(live == nil ? "not checked yet" : "not in a game").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
    
    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Friend news", systemImage: "bell.badge.fill").font(.system(size: 13, weight: .bold)).foregroundColor(.orange)
                Spacer()
                Button("Clear") { watcher.dismissAlerts() }.controlSize(.small)
            }
            ForEach(watcher.alerts.prefix(8)) { a in
                HStack(spacing: 8) {
                    Image(systemName: a.kind == .finished ? "crown.fill" : "sparkles").foregroundColor(a.kind == .finished ? .yellow : .purple)
                    Text(a.text).font(.system(size: 12))
                    Spacer()
                    Text(a.date.formatted(.relative(presentation: .named))).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    
    @ViewBuilder
    private var multiBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick up to \(MultiCompareModel.maxFriends) friends.").font(.system(size: 11)).foregroundColor(.secondary)
            FlowChips(friends: friends, selected: multi.selected) { multi.toggle($0) }
            HStack {
                Button("Compare") { multi.run(friends: friends, state: state) }
                    .buttonStyle(.borderedProminent).disabled(multi.selected.isEmpty || multi.isRunning)
                if multi.isRunning { ProgressView().scaleEffect(0.6) }
                if let m = multi.message { Text(m).font(.system(size: 11)).foregroundColor(.secondary) }
            }
            let chosen = friends.filter { multi.selected.contains($0.steamId) && multi.counts[$0.steamId] != nil }
            if !chosen.isEmpty {
                let games = state.games.filter { g in chosen.contains { multi.counts[$0.steamId]?[g.appId] != nil } }
                    .sorted { $0.name.lowercased() < $1.name.lowercased() }
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("Game").font(.system(size: 11, weight: .bold))
                        Text("You").font(.system(size: 11, weight: .bold))
                        ForEach(chosen) { Text($0.personaName).font(.system(size: 11, weight: .bold)).lineLimit(1) }
                    }
                    Divider()
                    ForEach(games.prefix(60)) { g in
                        GridRow {
                            Text(g.name).font(.system(size: 11)).lineLimit(1)
                            Text("\(g.unlockedAchievements)/\(g.totalAchievements)").font(.system(size: 11, design: .monospaced))
                            ForEach(chosen) { f in
                                if let c = multi.counts[f.steamId]?[g.appId] {
                                    Text("\(c.unlocked)/\(c.total)").font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(c.unlocked > g.unlockedAchievements ? .orange : .secondary)
                                } else { Text("-").foregroundColor(.secondary) }
                            }
                        }
                    }
                }
                Text("Orange = that friend is ahead of you in the game.").font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }
}

private struct FlowChips: View {
    let friends: [SteamPlayer]
    let selected: [String]
    let toggle: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(friends) { f in
                    let on = selected.contains(f.steamId)
                    Button(f.personaName) { toggle(f.steamId) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(on ? .accentColor : .gray)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.5))
                }
            }
        }
    }
}
