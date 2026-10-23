import SwiftUI

@MainActor
final class FriendCompareModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case needsApiKey
        case loadingFriends
        case ready
        case failed(String)
    }
    
    @Published var phase: Phase = .idle
    @Published var friends: [SteamPlayer] = []
    @Published var selectedFriendId: String?
    
    @Published var loadingDetail: String?
    @Published var isComparing = false
    @Published var compareMessage: String?
    @Published var compareDone = 0
    @Published var compareTotal = 0
    /// appId -> friend's (unlocked, total). Games the friend lacks or hides are simply absent.
    @Published var friendCounts: [Int: (unlocked: Int, total: Int)] = [:]
    
    private var compareTask: Task<Void, Never>?
    
    var selectedFriend: SteamPlayer? {
        friends.first { $0.steamId == selectedFriendId }
    }
    
    func loadFriends(state: AppState) async {
        await state.ensureWebToken()
        guard let auth = state.activeAuth else {
            phase = .needsApiKey
            return
        }
        guard let myId = state.player?.steamId ?? state.authenticatedSteamId else {
            phase = .failed("Connect your Steam account first.")
            return
        }
        phase = .loadingFriends
        do {
            let ids = try await SteamAPIService.shared.fetchFriendIds(steamId: myId, auth: auth)
            let players: [SteamPlayer]
            if auth.apiKey != nil {
                players = try await SteamAPIService.shared.fetchPlayerSummaries(steamIds: ids, auth: auth)
            } else {
                // Signed in without an API key: names and avatars come from each friend's public mini profile
                // (kept for a day, so only the first visit takes a moment).
                loadingDetail = "0 of \(ids.count)"
                players = await FriendProfiles.shared.profiles(for: ids) { done in
                    Task { @MainActor in self.loadingDetail = "\(done) of \(ids.count)" }
                }
                loadingDetail = nil
            }
            friends = players.sorted { $0.personaName.lowercased() < $1.personaName.lowercased() }
            phase = .ready
        } catch SteamAPIError.accessDenied {
            phase = .failed("Steam refused the friends list. Your friends list must be public and the API key valid.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
    
    func compare(friend: SteamPlayer, state: AppState) {
        compareTask?.cancel()
        selectedFriendId = friend.steamId
        friendCounts = [:]
        compareMessage = nil
        compareDone = 0
        
        let key = state.apiKey
        let auth = state.activeAuth
        let cookies = state.sessionCookies
        let mine = state.games.filter { $0.hasAchievementsLoaded && $0.totalAchievements > 0 }
        let myTotals = Dictionary(mine.map { ($0.appId, $0.totalAchievements) }, uniquingKeysWith: { first, _ in first })
        compareTotal = mine.count
        guard !mine.isEmpty else {
            compareMessage = "Your achievements haven't finished syncing yet. Try again when the sync banner is gone."
            return
        }
        
        isComparing = true
        compareTask = Task { [weak self] in
            do {
                let owned = try await SteamAPIService.shared.fetchOwnedGames(steamId: friend.steamId, auth: auth ?? SteamAuth())
                let ownedIds = Set(owned.map { $0.appId })
                let shared = mine.map { $0.appId }.filter { ownedIds.contains($0) }
                await MainActor.run { self?.compareTotal = shared.count }
                
                await withTaskGroup(of: (Int, (unlocked: Int, total: Int)?).self) { group in
                    var iterator = shared.makeIterator()
                    func enqueueNext() {
                        if let id = iterator.next() {
                            group.addTask {
                                // An API key can read counts directly; a plain sign-in reads the friend's community stats page.
                                var counts: (unlocked: Int, total: Int)?
                                // Steam's player endpoint: one light request, no key needed, shows what the friend allows.
                                if let rows = try? await SteamAPIService.shared.fetchUserAchievements(steamId: friend.steamId, appId: id, auth: auth),
                                   let total = myTotals[id] {
                                    counts = (min(rows.filter { $0.unlocked }.count, total), total)
                                }
                                if counts == nil, !key.isEmpty {
                                    counts = try? await SteamAPIService.shared.fetchAchievementCounts(appId: id, steamId: friend.steamId, apiKey: key)
                                }
                                if counts == nil {
                                    counts = try? await SteamCommunityService.shared.fetchAchievementCounts(steamId: friend.steamId, appId: id, cookies: cookies)
                                }
                                return (id, counts)
                            }
                        }
                    }
                    for _ in 0..<6 { enqueueNext() }
                    while let (id, counts) = await group.next() {
                        if Task.isCancelled { group.cancelAll(); break }
                        if let self = self {
                            if let counts = counts { self.friendCounts[id] = counts }
                            self.compareDone += 1
                        }
                        enqueueNext()
                    }
                }
                if let self = self, !Task.isCancelled, self.friendCounts.isEmpty {
                    self.compareMessage = "No shared games with achievements were found (the friend's game details may be private)."
                }
            } catch is CancellationError {
                return
            } catch SteamAPIError.privateProfile {
                self?.compareMessage = "\(friend.personaName)'s game details are private, so their achievements can't be compared."
            } catch {
                self?.compareMessage = error.localizedDescription
            }
            self?.isComparing = false
        }
    }
}

public struct FriendCompareView: View {
    @ObservedObject var state: AppState
    @StateObject private var model = FriendCompareModel()
    
    public init(state: AppState) {
        self.state = state
    }
    
    /// Games both of you have, with achievement data for both sides.
    private var sharedGames: [(game: SteamGame, friend: (unlocked: Int, total: Int))] {
        state.games.compactMap { g in
            guard let f = model.friendCounts[g.appId] else { return nil }
            return (g, f)
        }
        .sorted { $0.game.name.lowercased() < $1.game.name.lowercased() }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                
                switch model.phase {
                case .idle, .loadingFriends:
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text(model.loadingDetail.map { "Loading your friends (\($0))..." } ?? "Loading your friends...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                case .needsApiKey:
                    VStack(alignment: .leading, spacing: 10) {
                        notice("Sign in with Steam to list your friends and compare achievements. No API key needed.", icon: "person.badge.key.fill")
                        Button("Sign In with Steam") { state.isLoginPresented = true }
                            .buttonStyle(.borderedProminent)
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 10) {
                        notice(message, icon: "exclamationmark.triangle.fill")
                        Button("Try Again") { Task { await model.loadFriends(state: state) } }
                            .buttonStyle(.bordered)
                    }
                case .ready:
                    if !model.friends.isEmpty { FriendsHubView(state: state, watcher: state.friendWatcher, friends: model.friends) }
                    if model.friends.isEmpty {
                        notice("No friends found on this account.", icon: "person.crop.circle.badge.questionmark")
                    } else if let friend = model.selectedFriend {
                        comparison(friend: friend)
                    } else {
                        notice("Pick a friend above to compare your achievements.", icon: "person.2.fill")
                    }
                }
            }
            .padding(24)
        }
        .task {
            if model.phase == .idle { await model.loadFriends(state: state) }
        }
    }
    
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    Text("Friend Head-to-Head Comparison")
                        .font(.system(size: 24, weight: .bold))
                }
                Text("Compares real achievement counts on the games you both own. Sign in with Steam; your friend's game details need to be visible to friends.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if model.phase == .ready, !model.friends.isEmpty {
                Picker("Friend", selection: Binding(
                    get: { model.selectedFriendId ?? "" },
                    set: { id in
                        if let f = model.friends.first(where: { $0.steamId == id }) {
                            model.compare(friend: f, state: state)
                        }
                    }
                )) {
                    Text("Choose a friend").tag("")
                    ForEach(model.friends) { f in
                        Text(f.personaName).tag(f.steamId)
                    }
                }
                .frame(width: 200)
            }
        }
    }
    
    private func notice(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func comparison(friend: SteamPlayer) -> some View {
        let rows = sharedGames
        let myUnlocked = rows.reduce(0) { $0 + $1.game.unlockedAchievements }
        let myTotal = rows.reduce(0) { $0 + $1.game.totalAchievements }
        let myPerfect = rows.filter { $0.game.isPerfect }.count
        let fUnlocked = rows.reduce(0) { $0 + $1.friend.unlocked }
        let fTotal = rows.reduce(0) { $0 + $1.friend.total }
        let fPerfect = rows.filter { $0.friend.total > 0 && $0.friend.unlocked == $0.friend.total }.count
        let myRate = myTotal > 0 ? Int((Double(myUnlocked) / Double(myTotal)) * 100) : 0
        let fRate = fTotal > 0 ? Int((Double(fUnlocked) / Double(fTotal)) * 100) : 0
        
        if model.isComparing {
            HStack(spacing: 10) {
                ProgressView(value: Double(model.compareDone), total: Double(max(1, model.compareTotal)))
                    .frame(width: 180)
                Text("Comparing shared games \(model.compareDone) / \(model.compareTotal)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        if let message = model.compareMessage {
            notice(message, icon: "info.circle.fill")
        }
        
        if !rows.isEmpty {
            HStack(spacing: 16) {
                ProfileCompareCard(
                    title: "YOU",
                    name: state.player?.personaName ?? "You",
                    avatarUrl: state.player?.avatarImageURL,
                    isWinner: myUnlocked > fUnlocked,
                    stats: [
                        ("Completion Rate", "\(myRate)%"),
                        ("Achievements Unlocked", "\(myUnlocked)"),
                        ("Perfect Games", "\(myPerfect)"),
                        ("Shared Games", "\(rows.count)")
                    ]
                )
                
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Text("VS")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.accentColor)
                }
                
                ProfileCompareCard(
                    title: "FRIEND",
                    name: friend.personaName,
                    avatarUrl: friend.avatarImageURL,
                    isWinner: fUnlocked > myUnlocked,
                    stats: [
                        ("Completion Rate", "\(fRate)%"),
                        ("Achievements Unlocked", "\(fUnlocked)"),
                        ("Perfect Games", "\(fPerfect)"),
                        ("Shared Games", "\(rows.count)")
                    ]
                )
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("SHARED GAMES ACHIEVEMENT RACE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 10) {
                    ForEach(rows, id: \.game.appId) { row in
                        raceRow(game: row.game, friendName: friend.personaName, friendCount: row.friend)
                    }
                }
            }
        }
    }
    
    private func raceRow(game: SteamGame, friendName: String, friendCount: (unlocked: Int, total: Int)) -> some View {
        let yourCount = game.unlockedAchievements
        let diff = yourCount - friendCount.unlocked
        let friendPct = friendCount.total > 0 ? (Double(friendCount.unlocked) / Double(friendCount.total)) * 100.0 : 0.0
        
        return VStack(spacing: 8) {
            HStack {
                Text(game.name)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if diff > 0 {
                    Text("🏆 You lead by \(diff)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                } else if diff < 0 {
                    Text("Friend leads by \(-diff)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                } else {
                    Text("Tied")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("You").font(.system(size: 10, weight: .medium))
                        Spacer()
                        Text("\(yourCount) / \(game.totalAchievements)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    CustomProgressBar(value: game.completionPercentage, height: 4, isPerfect: game.isPerfect)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(friendName).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        Spacer()
                        Text("\(friendCount.unlocked) / \(friendCount.total)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    CustomProgressBar(value: friendPct, height: 4, isPerfect: friendPct >= 100.0)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
    }
}

private struct ProfileCompareCard: View {
    let title: String
    let name: String
    let avatarUrl: URL?
    let isWinner: Bool
    let stats: [(String, String)]
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.secondary)
                Spacer()
                if isWinner {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                        Text("LEADER")
                    }
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                }
            }
            
            HStack(spacing: 12) {
                RemoteImageView(url: avatarUrl, fallbackSystemName: "person.crop.circle.fill", cornerRadius: 20)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Text("Steam Member")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            Divider()
            
            VStack(spacing: 6) {
                ForEach(stats, id: \.0) { s in
                    HStack {
                        Text(s.0)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(s.1)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isWinner ? Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
    }
}
