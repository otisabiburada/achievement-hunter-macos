import Foundation

/// Watches a few favorite friends: who is playing what, and rare unlocks / finished games in games you own.
/// Kept small on purpose: at most 5 friends, a handful of light requests every 10 minutes, and it backs off
/// completely when Steam's community pages start refusing.
@MainActor
final class FriendWatcher: ObservableObject {
    static let maxFavorites = 5
    @Published private(set) var favorites: [String]
    @Published private(set) var live: [String: SteamPlayer] = [:]
    @Published private(set) var alerts: [FriendAlert] = []
    @Published private(set) var lastChecked: Date?
    
    private var snapshots: [String: [Int: Set<Int>]] = [:]   // friend -> app -> unlocked keys
    private var lastSeenGames: [String: [Int]] = [:]
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var busy = false
    
    init() {
        favorites = UserDefaults.standard.stringArray(forKey: "friend_favorites") ?? []
        if let d = defaults.data(forKey: "friend_alerts"), let a = try? JSONDecoder().decode([FriendAlert].self, from: d) { alerts = a }
        if let d = defaults.data(forKey: "friend_snapshots"), let s = try? JSONDecoder().decode([String: [Int: [Int]]].self, from: d) {
            snapshots = s.mapValues { $0.mapValues(Set.init) }
        }
    }
    
    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
    
    @discardableResult
    func toggleFavorite(_ id: String) -> Bool {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) }
        else if favorites.count < Self.maxFavorites { favorites.append(id) }
        else { return false }
        defaults.set(favorites, forKey: "friend_favorites")
        return true
    }
    
    func start(state: AppState) {
        timer?.invalidate()
        let t = Timer(timeInterval: 600, repeats: true) { [weak self, weak state] _ in
            guard let self = self, let state = state else { return }
            Task { @MainActor in await self.check(state: state) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { await check(state: state) }
    }
    
    func dismissAlerts() { alerts = []; defaults.removeObject(forKey: "friend_alerts") }
    
    func check(state: AppState) async {
        guard !busy, !favorites.isEmpty, state.hasCredentials else { return }
        if await CommunityThrottle.shared.isBlocked { return }
        busy = true
        defer { busy = false; lastChecked = Date() }
        let owned = Set(state.games.filter { $0.totalAchievements > 0 }.map { $0.appId })
        let names = Dictionary(state.games.map { ($0.appId, $0.name) }, uniquingKeysWith: { a, _ in a })
        await state.ensureWebToken()
        let auth = state.activeAuth
        var fresh: [FriendAlert] = []
        for id in favorites {
            guard let p = await SteamCommunityService.shared.fetchMiniProfileStatus(steamId64: id) else { continue }
            live[id] = p
            if let g = p.currentGameId { lastSeenGames[id] = ([g] + (lastSeenGames[id] ?? [])).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.prefix(5).map { $0 } }
            for appId in FriendWatch.gamesToCheck(friendGameId: p.currentGameId, lastSeen: lastSeenGames[id] ?? [], owned: owned) {
                guard let rows = try? await SteamAPIService.shared.fetchUserAchievements(steamId: id, appId: appId, auth: auth),
                      let catalog = try? await SteamAPIService.shared.fetchCatalog(appId: appId) else { continue }
                let result = FriendWatch.alerts(friendId: id, friendName: p.personaName, appId: appId, gameName: names[appId] ?? "a game",
                                                previous: snapshots[id]?[appId], rows: rows, entries: catalog.entries)
                snapshots[id, default: [:]][appId] = result.unlocked
                fresh += result.alerts
            }
        }
        persistSnapshots()
        let known = Set(alerts.map { $0.id })
        let new = fresh.filter { !known.contains($0.id) }
        guard !new.isEmpty else { return }
        alerts = Array((new + alerts).prefix(30))
        if let d = try? JSONEncoder().encode(alerts) { defaults.set(d, forKey: "friend_alerts") }
        if UnlockNotifier.policy.enabled { UnlockNotifier.shared.postFriendAlerts(new) }
    }
    
    private func persistSnapshots() {
        let plain = snapshots.mapValues { $0.mapValues { Array($0) } }
        if let d = try? JSONEncoder().encode(plain) { defaults.set(d, forKey: "friend_snapshots") }
    }
}
