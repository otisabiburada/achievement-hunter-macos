import SwiftUI
import Combine
import WebKit
import AppKit

public enum NavigationSection: String, CaseIterable, Identifiable {
    case library = "Games Library"
    case nowPlaying = "Now Playing"
    case activity = "Activity Feed"
    case roadTo100 = "Road to 100%"
    case focusTargets = "Focus Targets"
    case analytics = "Analytics & Heatmap"
    case hallOfFame = "Hall of Fame"
    case friendCompare = "Friend Compare"
    case widgets = "Widgets Studio"
    
    public var id: String { rawValue }
    
    /// Sidebar group heading.
    public var group: String {
        switch self {
        case .library, .nowPlaying, .activity: return "Library"
        case .roadTo100, .focusTargets: return "Hunt"
        case .analytics, .hallOfFame: return "Insights"
        case .friendCompare, .widgets: return "Share & Compare"
        }
    }
    
    public var iconName: String {
        switch self {
        case .library:
            return "gamecontroller.fill"
        case .nowPlaying:
            return "dot.radiowaves.left.and.right"
        case .activity:
            return "bell.badge.fill"
        case .roadTo100:
            return "flag.checkered.2.crossed"
        case .focusTargets:
            return "pin.fill"
        case .analytics:
            return "chart.xyaxis.line"
        case .hallOfFame:
            return "crown.fill"
        case .friendCompare:
            return "person.2.fill"
        case .widgets:
            return "rectangle.3.group.fill"
        }
    }
}

public enum GameSort: String, CaseIterable, Identifiable {
    case playtime = "Most played"
    case name = "Name (A-Z)"
    case completion = "Completion %"
    case remaining = "Fewest remaining"
    case recentUnlock = "Recent unlocks"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .playtime: return "clock"
        case .name: return "textformat"
        case .completion: return "percent"
        case .remaining: return "flag.checkered"
        case .recentUnlock: return "sparkles"
        }
    }
}

struct NavLocation: Equatable {
    var section: NavigationSection
    var gameId: Int?
}

public enum GameFilter: String, CaseIterable, Identifiable {
    case all = "All Games"
    case perfect = "100% Completed"
    case inProgress = "In Progress"
    case unstarted = "Unstarted"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all:
            return "gamecontroller.fill"
        case .perfect:
            return "trophy.fill"
        case .inProgress:
            return "chart.bar.fill"
        case .unstarted:
            return "circle.dashed"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var selectedSection: NavigationSection = .library {
        didSet { recordNavigation() }
    }
    
    @Published public var player: SteamPlayer? = nil
    @Published public var games: [SteamGame] = [] { didSet { derivedCache = nil; aggregatesCache = nil } }
    @Published public var selectedGameId: Int? = nil {
        didSet { recordNavigation() }
    }
    @Published public var selectedFilter: GameFilter = .all { didSet { derivedCache = nil } }
    @Published public var searchQuery: String = "" { didSet { derivedCache = nil } }
    
    // Progress Tracking
    @Published public var isLoading: Bool = false
    @Published public var syncProgress: Double = 0.0
    @Published public var syncStageText: String = ""
    @Published public var syncDetailText: String = ""
    
    @Published public var errorMessage: String? = nil
    @Published public var exportMessage: String? = nil
    @Published public var isSettingsPresented: Bool = false
    @Published public var isLoginPresented: Bool = false
    @Published public var isOnboardingPresented: Bool = false
    @Published public var isQuickOpenPresented: Bool = false
    @Published public var isProfileSharePresented: Bool = false
    /// Bumped to move keyboard focus to the game search field (⌘F).
    @Published public var searchFocusToken: Int = 0
    
    // Pinned Targets
    @Published public var pinnedTargets: [PinnedTarget] = [] {
        didSet { savePinnedTargets() }
    }
    
    // Custom Tags: [apiname: [tags]]
    @Published public var tagsMap: [String: [AchievementTag]] = [:] {
        didSet { saveTags() }
    }
    
    // Steam Account State
    @Published public var isAuthenticated: Bool = false
    @Published public var authenticatedSteamId: String? = nil {
        didSet {
            UserDefaults.standard.set(authenticatedSteamId, forKey: "auth_steam_id")
        }
    }
    /// Short-lived API token issued to the signed-in session; makes an API key unnecessary.
    @Published public private(set) var webToken: SteamWebToken? = nil
    
    /// Connected, but with no way to read the full library: no sign-in session and no API key. This is also the
    /// state after updating from a version that kept the login in the macOS Keychain.
    /// A saved Steam sign-in exists (the banner asking to sign in must never show then).
    public var hasSignInSession: Bool { !sessionCookies.isEmpty }
    
    public var needsSignIn: Bool {
        isAuthenticated && sessionCookies.isEmpty && apiKey.isEmpty
    }
    
    /// What to use for Web API calls right now: the user's own key if they set one, else the sign-in token.
    public var activeAuth: SteamAuth? {
        SteamAuth.resolve(apiKey: apiKey, token: webToken)
    }
    
    /// Gets (or renews) the sign-in token from the saved login cookies. No-op if a key is set or signed out.
    private var lastTokenAttempt = Date.distantPast
    
    public func ensureWebToken() async {
        guard apiKey.isEmpty, !sessionCookies.isEmpty, webToken?.isFresh != true else { return }
        // Don't hammer Steam when the session has expired: one attempt every few minutes is plenty.
        guard Date().timeIntervalSince(lastTokenAttempt) > 300 else { return }
        lastTokenAttempt = Date()
        if let token = await SteamWebSession.fetchToken(cookies: sessionCookies, expectedSteamId: authenticatedSteamId) {
            webToken = token
            AppLog.shared.log("Sign-in token renewed, valid until \(token.expiresAt)")
        } else {
            AppLog.shared.log("Sign-in token unavailable (session expired or signed out)")
        }
    }
    
    public var sessionCookies: [HTTPCookie] = [] {
        didSet { SecretStore.shared.saveCookies(sessionCookies) }
    }
    
    // API Key
    @Published public var apiKey: String = "" {
        didSet { SecretStore.shared.writeString(apiKey, account: Self.apiKeyAccount) }
    }
    @Published public var steamIdOrVanity: String = "" {
        didSet { UserDefaults.standard.set(steamIdOrVanity, forKey: "steam_id_or_vanity") }
    }
    
    private static let apiKeyAccount = "steam_api_key"
    
    public init() {
        // The API key lives in the encrypted secret store (never the macOS Keychain: that asks for a password after
        // every app update). Migrate a key left in UserDefaults by older versions.
        if let stored = SecretStore.shared.readString(Self.apiKeyAccount) {
            self.apiKey = stored
        } else if let legacy = UserDefaults.standard.string(forKey: "steam_api_key"), !legacy.isEmpty {
            self.apiKey = legacy
            if SecretStore.shared.writeString(legacy, account: Self.apiKeyAccount) {
                UserDefaults.standard.removeObject(forKey: "steam_api_key")
            }
        }
        self.sessionCookies = SecretStore.shared.loadCookies()
        self.steamIdOrVanity = UserDefaults.standard.string(forKey: "steam_id_or_vanity") ?? ""
        let savedAuthId = UserDefaults.standard.string(forKey: "auth_steam_id")
        self.authenticatedSteamId = savedAuthId
        self.isAuthenticated = savedAuthId != nil && !(savedAuthId?.isEmpty ?? true)
        
        loadSavedPinnedTargets()
        loadSavedTags()
        
        UnlockNotifier.shared.configure()
        unlockFeed = UnlockEvent.removingImportBursts(from: Self.loadFeed(from: feedFileURL))
        
        // Load only real cached data; NO demo data!
        // The small index appears immediately; the per-game achievement files are read in the background.
        if let index = libraryStore.loadIndexOnly() {
            self.player = index.player
            self.games = index.stubs.map { $0.asGame }
            self.lastSyncedAt = index.lastSyncedAt
            self.selectedGameId = index.stubs.first?.appId
            self.isHydratingLibrary = true
            let store = libraryStore
            cacheLoadTask = Task { [weak self] in
                let full = await Task.detached(priority: .userInitiated) { store.loadGames(for: index) }.value
                self?.finishHydration(full)
            }
        } else if let cached = libraryStore.load() {
            // first launch after upgrading from the old single-file cache (migrates it)
            self.player = cached.player
            self.games = cached.games
            self.lastSyncedAt = cached.lastSyncedAt
            self.selectedGameId = cached.games.first?.appId
        }
        recomputeNowPlaying()
        recordNavigation()
        startOnboardingIfNeeded()
        
        startStatusPolling()
        Task { await self.refreshPlayerStatus() }   // don't wait 30 s for the first status
        restartAutoSync()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)   // first refresh shortly after launch
            await self.runBackgroundSyncIfDue()
            self.friendWatcher.start(state: self)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // coming back to the app after a while: catch up right away
            Task { @MainActor in
                await self?.refreshPlayerStatus()
                await self?.runBackgroundSyncIfDue()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopStatusPolling()
                self?.libraryStore.flush()
            }
        }
    }
    
    /// A side-effect-free state for rendering UI in tests and previews: no cache, timers, network or notifications.
    public init(previewGames: [SteamGame], player: SteamPlayer?) {
        self.games = previewGames
        self.player = player
        self.isAuthenticated = true
        self.selectedGameId = previewGames.first?.appId
        self.nowPlayingAppId = previewGames.first?.appId
    }
    
    // MARK: - Start guide
    
    private static let onboardingKey = "onboarding_done_v1"
    
    public var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }
    
    public func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        isOnboardingPresented = false
    }
    
    /// Shows the guide to new users; people who already have a library never see it unprompted.
    private func startOnboardingIfNeeded() {
        if hasCompletedOnboarding { return }
        if !games.isEmpty || isAuthenticated {
            UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        } else {
            isOnboardingPresented = true
        }
    }
    
    // MARK: - Library hydration
    
    /// True while the cached achievements are still being read from disk after launch.
    @Published public private(set) var isHydratingLibrary = false
    private var cacheLoadTask: Task<Void, Never>?
    
    private func finishHydration(_ full: [SteamGame]) {
        let byId = Dictionary(full.map { ($0.appId, $0) }, uniquingKeysWith: { first, _ in first })
        // Only fill in games that haven't been touched since launch.
        games = games.map { current in
            guard !current.hasAchievementsLoaded, let cached = byId[current.appId] else { return current }
            return cached
        }
        isHydratingLibrary = false
        recomputeNowPlaying()
        
        Task { await repairMissingSets() }
        
        // One-time repair of games earlier versions wrongly saved as "no achievements".
        if needsEmptyRecheck, hasAccountConnected, games.contains(where: { $0.hasNoAchievements }) {
            AppLog.shared.log("Repairing \(games.filter { $0.hasNoAchievements }.count) games that were saved as having no achievements")
            // The feed may hold a flood of fake "new unlocks" produced while those games were being repaired.
            if unlockFeed.count >= 50 { unlockFeed.removeAll(); saveFeed() }
            Task { await syncWithSteam() }
        }
    }
    
    /// Games whose achievements carry set ids but whose set list was dropped (an earlier bug lost it on re-syncs) get it
    /// back from the cached catalog, or from Steam if that cache has expired. Only a handful of games use sets.
    private func repairMissingSets() async {
        let needing = games.filter { g in
            g.achievementGroups == nil && g.achievements.contains { ($0.groupId ?? 0) > 0 }
        }.map { $0.appId }
        guard !needing.isEmpty else { return }
        AppLog.shared.log("Restoring achievement sets for \(needing.count) games")
        
        var restored: [Int: [AchievementGroup]] = [:]
        await withTaskGroup(of: (Int, [AchievementGroup]?).self) { group in
            var iterator = needing.makeIterator()
            func next() {
                if let id = iterator.next() {
                    group.addTask {
                        if let cached = MetadataCache.catalog(appId: id), !cached.value.groups.isEmpty { return (id, cached.value.groups) }
                        let fetched = try? await SteamAPIService.shared.fetchCatalog(appId: id)
                        return (id, fetched?.groups)
                    }
                }
            }
            for _ in 0..<4 { next() }
            while let (id, groups) = await group.next() {
                if let groups = groups, !groups.isEmpty { restored[id] = groups }
                next()
            }
        }
        guard !restored.isEmpty else { return }
        var updated = games
        for i in updated.indices {
            if let groups = restored[updated[i].appId], updated[i].achievementGroups == nil {
                updated[i].achievementGroups = groups
                dirtyGameIds.insert(updated[i].appId)
            }
        }
        games = updated
        saveLocalCache()
    }
    
    // MARK: - Navigation history (⌘[ / ⌘])
    
    private var navStack: [NavLocation] = []
    private var navIndex = -1
    private var isRestoringNavigation = false
    @Published public private(set) var canGoBack = false
    @Published public private(set) var canGoForward = false
    
    private func recordNavigation() {
        guard !isRestoringNavigation else { return }
        let here = NavLocation(section: selectedSection, gameId: selectedSection == .library ? selectedGameId : nil)
        if navStack.isEmpty {
            navStack = [here]
            navIndex = 0
        } else if navStack[navIndex] != here {
            navStack = Array(navStack[0...navIndex]) + [here]
            if navStack.count > 100 { navStack.removeFirst(navStack.count - 100) }
            navIndex = navStack.count - 1
        }
        canGoBack = navIndex > 0
        canGoForward = navIndex < navStack.count - 1
    }
    
    private func restoreNavigation(at index: Int) {
        guard navStack.indices.contains(index) else { return }
        isRestoringNavigation = true
        navIndex = index
        let loc = navStack[index]
        selectedSection = loc.section
        if let id = loc.gameId, games.contains(where: { $0.appId == id }) { selectedGameId = id }
        isRestoringNavigation = false
        canGoBack = navIndex > 0
        canGoForward = navIndex < navStack.count - 1
    }
    
    public func goBack() { restoreNavigation(at: navIndex - 1) }
    public func goForward() { restoreNavigation(at: navIndex + 1) }
    
    /// Title for the window: where you are right now.
    public var windowTitle: String {
        if selectedSection == .library, let g = selectedGame { return g.name }
        return selectedSection.rawValue
    }
    
    /// Jump to a game in the library.
    public func openGame(_ appId: Int) {
        selectedSection = .library
        selectedGameId = appId
        searchQuery = ""
        Task { await loadAchievements(for: appId) }
    }
    
    // MARK: - Now Playing & In-Game Detection
    //
    // Steam's own "in-game" status is the single source of truth. It is polled on a timer (one network
    // call per interval) and the result is cached in `nowPlayingAppId`, so SwiftUI reads are O(1)-ish and
    // never scan running processes (name matching a Mac app like "Portal" to the game was unreliable).
    
    @Published public private(set) var nowPlayingAppId: Int? = nil
    private var nowPlayingFallbackName: String? = nil
    
    private var statusTimer: Timer?
    private var isPollingStatus = false
    private static let statusPollInterval: TimeInterval = 15
    private static let backgroundStatusPollInterval: TimeInterval = 45
    private static let liveRefreshInterval: TimeInterval = 120
    
    public var nowPlayingGame: SteamGame? {
        guard let id = nowPlayingAppId else { return nil }
        if let g = games.first(where: { $0.appId == id }) { return g }
        return SteamGame(appId: id, name: nowPlayingFallbackName ?? "Steam Game", playtimeMinutes: 0)
    }
    
    public var isInGame: Bool {
        nowPlayingAppId != nil
    }
    
    private func recomputeNowPlaying() {
        guard let p = player, p.isInGame else {
            nowPlayingAppId = nil
            nowPlayingFallbackName = nil
            return
        }
        if let id = p.currentGameId, games.contains(where: { $0.appId == id }) {
            nowPlayingAppId = id
            nowPlayingFallbackName = nil
        } else if let name = p.currentGameName, let g = games.first(where: { GameNameMatcher.matches($0.name, name) }) {
            nowPlayingAppId = g.appId
            nowPlayingFallbackName = nil
        } else if let id = p.currentGameId {
            nowPlayingAppId = id
            nowPlayingFallbackName = p.currentGameName
        } else {
            nowPlayingAppId = nil
            nowPlayingFallbackName = nil
        }
    }
    
    public func startStatusPolling() {
        statusTimer?.invalidate()
        // macOS throttles timers of background apps (App Nap). Status tracking must keep running while another app
        // (the game!) is in front, so opt out for as long as the app is open.
        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Tracking your Steam status")
        }
        let timer = Timer(timeInterval: Self.statusPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // fast while you are looking at the app, relaxed while it is in the background
                if !NSApp.isActive && Date().timeIntervalSince(self.lastStatusPoll) < Self.backgroundStatusPollInterval { return }
                await self.refreshPlayerStatus()
            }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)   // .common: keeps firing while menus are open or the list scrolls
        statusTimer = timer
    }
    
    public func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    public func checkNowPlayingStatus() {
        recomputeNowPlaying()
        guard let g = nowPlayingGame else { return }
        if !g.hasAchievementsLoaded, g.loadError == nil {
            Task { await loadAchievements(for: g.appId) }
        } else if g.hasAchievementsLoaded,
                  Date().timeIntervalSince(g.lastFetchedAt ?? .distantPast) > Self.liveRefreshInterval {
            // Keep the live HUD fresh while a game is running (this is also what feeds the unlock feed).
            Task { await loadAchievements(for: g.appId, force: true) }
        }
    }
    
    /// When Steam's status was last read successfully (shown in Now Playing so a stall is visible), and how many
    /// checks have run (a heartbeat line is written to the log every 40 checks, about every 10 minutes).
    @Published public private(set) var lastStatusCheckAt: Date?
    @Published public private(set) var lastStatusCheckFailed = false
    private var statusCheckCount = 0
    private var lastStatusLog = ""
    private var statusDebouncer = GameStatusDebouncer()
    private var lastStatusPoll = Date.distantPast
    private var statusPollStartedAt: Date?
    private var activityToken: NSObjectProtocol?
    
    /// Reads the player's status from BOTH the Web API (key or sign-in token) and the public profile page, and merges
    /// them: whichever sees a running game wins. Now Playing relies on this, so it must not depend on one source.
    public func refreshPlayerStatus() async {
        // A poll that hangs (a request that never answers) must not block every later poll.
        if isPollingStatus, let started = statusPollStartedAt, Date().timeIntervalSince(started) > 45 { isPollingStatus = false }
        guard !isPollingStatus, !isLoading else { return }
        let target = authenticatedSteamId ?? steamIdOrVanity
        guard !target.isEmpty else { return }
        isPollingStatus = true
        statusPollStartedAt = Date()
        lastStatusPoll = Date()
        defer { isPollingStatus = false }
        
        await ensureWebToken()
        let id = accountRef?.steamId ?? SteamTargetInfo(input: target).steamId64 ?? target
        let cookies = sessionCookies
        
        // Priority: the user's own API key (real time) > Steam's mini profile (real time, names the game and app)
        // > the profile XML (uncached, but the least reliable). The sign-in token can't read player summaries.
        let key = apiKey
        async let apiResult: SteamPlayer? = {
            guard !key.isEmpty else { return nil }
            return try? await SteamAPIService.shared.fetchPlayerSummary(steamId: id, auth: SteamAuth(apiKey: key))
        }()
        let apiPlayer = await apiResult
        let mini = await SteamCommunityService.shared.fetchMiniProfileStatus(steamId64: id)
        // The profile page is only a fallback for when the live card didn't answer: one community request per check
        // instead of two (the community pages are rate limited).
        let page: SteamPlayer? = (apiPlayer ?? mini) == nil
            ? (try? await SteamCommunityService.shared.fetchPlayerProfile(steamId: target, cookies: cookies))
            : nil
        // Union of the sources (key > live card > profile page): any of them seeing a game counts. Leaving a game is
        // only believed after a grace period (see GameStatusDebouncer), because the live card flickers.
        let api = apiPlayer ?? mini
        let community = page
        statusCheckCount += 1
        if statusCheckCount % 40 == 0 { AppLog.shared.log("Status polling is running (\(statusCheckCount) checks so far)") }
        guard let merged = SteamPlayer.merge(api: api, community: community) else {
            if !lastStatusCheckFailed { lastStatusCheckFailed = true }
            logStatus("Status check failed: no answer from the Web API or the profile page")
            return
        }
        if lastStatusCheckFailed { lastStatusCheckFailed = false }
        // Every assignment to a @Published property redraws what observes it; "checked N seconds ago" is only
        // useful to the nearest half minute, and an unchanged player must not publish at all.
        if lastStatusCheckAt == nil || Date().timeIntervalSince(lastStatusCheckAt!) > 30 { lastStatusCheckAt = Date() }
        var status = statusDebouncer.resolve(observed: merged, previous: self.player)
        if status.isInGame, status.currentGameId == nil, let name = status.currentGameName,
           !games.contains(where: { GameNameMatcher.matches($0.name, name) }) {
            // Not in the library (free game, family sharing, or spelled differently): ask the store which app this is.
            if let id = await SteamAPIService.shared.searchAppId(name: name) { status.currentGameId = id }
        }
        if self.player != status { self.player = status }
        logStatus("Status: \(status.statusText)\(status.currentGameId.map { " [app \($0)]" } ?? "") (key: \(apiPlayer == nil ? "none" : (apiPlayer!.isInGame ? "in-game" : "no game")), live card: \(mini == nil ? "none" : (mini!.isInGame ? "in-game" : "no game")), page: \(page == nil ? "none" : (page!.isInGame ? "in-game" : "no game")))")
        checkNowPlayingStatus()
    }
    
    /// Writes status changes to the diagnostic log (not every 30-second poll).
    private func logStatus(_ line: String) {
        guard line != lastStatusLog else { return }
        lastStatusLog = line
        AppLog.shared.log(line)
    }
    
    public var hasAccountConnected: Bool {
        player != nil || !games.isEmpty || isAuthenticated
    }
    
    public var selectedGame: SteamGame? {
        guard let id = selectedGameId else { return games.first }
        return games.first { $0.appId == id }
    }
    
    /// Hide games that have no achievements, and don't re-sync them. Persisted.
    @Published public var hideGamesWithoutAchievements: Bool = (UserDefaults.standard.object(forKey: "hide_games_without_achievements") as? Bool ?? true) {
        didSet {
            UserDefaults.standard.set(hideGamesWithoutAchievements, forKey: "hide_games_without_achievements")
            derivedCache = nil
            aggregatesCache = nil
        }
    }
    
    // MARK: Library-wide aggregates (cached)
    //
    // Statistics screens (heat map, analytics, hall of fame, menu bar, widgets) need every unlocked achievement. They
    // used to walk all ~54,000 achievements of the library on EVERY redraw, and every status check redraws: that is what
    // froze the app. The lists are now built once per change of the library and shared.
    
    public struct UnlockedItem: Identifiable, Sendable {
        public let achievement: Achievement
        public let gameName: String
        public let appId: Int
        public var id: String { "\(appId)-\(achievement.apiName)" }
    }
    
    public struct LockedItem: Sendable {
        public let name: String
        public let gameName: String
        public let percent: Double
        public let iconUrl: String?
    }
    
    private struct Aggregates {
        var unlocked: [UnlockedItem]
        var byRarity: [UnlockedItem]
        var byTime: [UnlockedItem]
        var countsByDay: [String: Int]
        var rarestLocked: [LockedItem]
        var quickWins: [QuickWin]
    }
    
    private var aggregatesCache: Aggregates?
    
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    public static func dayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }
    
    private var aggregates: Aggregates {
        if let cached = aggregatesCache { return cached }
        var unlocked: [UnlockedItem] = []
        var locked: [LockedItem] = []
        for g in games {
            for a in g.achievements {
                if a.isUnlocked {
                    unlocked.append(UnlockedItem(achievement: a, gameName: g.name, appId: g.appId))
                } else if let pct = a.globalPercent, g.countsTowardCompletion(a) {
                    locked.append(LockedItem(name: a.displayName, gameName: g.name, percent: pct, iconUrl: a.iconUrl))
                }
            }
        }
        var counts: [String: Int] = [:]
        for item in unlocked {
            if let t = item.achievement.unlockTimestamp { counts[Self.dayKey(t), default: 0] += 1 }
        }
        let result = Aggregates(
            unlocked: unlocked,
            byRarity: unlocked.filter { $0.achievement.globalPercent != nil }
                .sorted { ($0.achievement.globalPercent ?? 100) < ($1.achievement.globalPercent ?? 100) },
            byTime: unlocked.filter { $0.achievement.unlockTimestamp != nil }
                .sorted { ($0.achievement.unlockTimestamp ?? .distantPast) > ($1.achievement.unlockTimestamp ?? .distantPast) },
            countsByDay: counts,
            rarestLocked: Array(locked.sorted { $0.percent < $1.percent }.prefix(20)),
            quickWins: PlanEngine.quickWins(games: games.filter { !$0.hasNoAchievements })
        )
        aggregatesCache = result
        return result
    }
    
    /// Every unlocked achievement, with its game.
    public var unlockedItems: [UnlockedItem] { aggregates.unlocked }
    /// Unlocked achievements, rarest first (only those with rarity data).
    public var unlockedByRarity: [UnlockedItem] { aggregates.byRarity }
    /// Unlocked achievements, newest first (only those with an unlock time).
    public var unlockedByTime: [UnlockedItem] { aggregates.byTime }
    /// Unlocks per day ("yyyy-MM-dd") for the activity heat map.
    public var unlockCountsByDay: [String: Int] { aggregates.countsByDay }
    /// The easiest achievements you still lack (cached; see PlanEngine).
    public var quickWins: [QuickWin] { aggregates.quickWins }
    /// The rarest achievements you still lack.
    public var rarestLockedItems: [LockedItem] { aggregates.rarestLocked }
    
    // MARK: Derived library data (cached)
    //
    // The sidebar, header and statistics read these on every redraw. They are computed once per change of
    // their inputs (games, search, filter, sort, hide-option) instead of on every access.
    
    private struct Derived {
        var visible: [SteamGame]
        var filtered: [SteamGame]
        var hidden: Int
        var unlocked: Int
        var total: Int
        var perfect: Int
    }
    
    private var derivedCache: Derived?
    
    private var derived: Derived {
        if let cached = derivedCache { return cached }
        let hidden = games.reduce(0) { $0 + ($1.hasNoAchievements ? 1 : 0) }
        let visible = hideGamesWithoutAchievements ? games.filter { !$0.hasNoAchievements } : games
        
        var list = visible
        switch selectedFilter {
        case .all:
            break
        case .perfect:
            list = list.filter { $0.isPerfect }
        case .inProgress:
            list = list.filter { !$0.isPerfect && $0.unlockedAchievements > 0 }
        case .unstarted:
            list = list.filter { $0.unlockedAchievements == 0 }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { $0.name.lowercased().contains(query) }
        }
        
        let result = Derived(
            visible: visible,
            filtered: sorted(list),
            hidden: hidden,
            unlocked: visible.reduce(0) { $0 + $1.unlockedAchievements },
            total: visible.reduce(0) { $0 + $1.totalAchievements },
            perfect: visible.reduce(0) { $0 + ($1.isPerfect ? 1 : 0) }
        )
        derivedCache = result
        return result
    }
    
    public var hiddenGamesCount: Int { derived.hidden }
    
    /// Games shown in lists and statistics (respects "hide games without achievements").
    public var visibleGames: [SteamGame] { derived.visible }
    
    @Published public var gameSort: GameSort = GameSort(rawValue: UserDefaults.standard.string(forKey: "game_sort") ?? "") ?? .playtime {
        didSet {
            UserDefaults.standard.set(gameSort.rawValue, forKey: "game_sort")
            derivedCache = nil
        }
    }
    
    private func sorted(_ list: [SteamGame]) -> [SteamGame] {
        switch gameSort {
        case .playtime:
            return list.sorted { $0.playtimeMinutes > $1.playtimeMinutes }
        case .name:
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .completion:
            return list.sorted { ($0.completionPercentage, $0.totalAchievements) > ($1.completionPercentage, $1.totalAchievements) }
        case .remaining:
            // closest to finished first; finished and empty games last
            return list.sorted {
                let a = $0.lockedAchievements > 0 ? $0.lockedAchievements : Int.max
                let b = $1.lockedAchievements > 0 ? $1.lockedAchievements : Int.max
                return a < b
            }
        case .recentUnlock:
            // compute each game's latest unlock once, not on every comparison
            var latest: [Int: Date] = [:]
            for g in list { latest[g.appId] = g.achievements.lazy.compactMap { $0.unlockTimestamp }.max() ?? .distantPast }
            return list.sorted { (latest[$0.appId] ?? .distantPast) > (latest[$1.appId] ?? .distantPast) }
        }
    }
    
    public var filteredGames: [SteamGame] { derived.filtered }
    
    public var totalUnlockedCount: Int { derived.unlocked }
    
    public var totalAchievementsCount: Int { derived.total }
    
    public var perfectGamesCount: Int { derived.perfect }
    
    public var overallCompletionPercentage: Double {
        let d = derived
        guard d.total > 0 else { return 0.0 }
        return (Double(d.unlocked) / Double(d.total)) * 100.0
    }
    
    public func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    
    // Pinned Targets Management
    public func isTargetPinned(achievement: Achievement) -> Bool {
        pinnedTargets.contains { $0.achievement.apiName.lowercased() == achievement.apiName.lowercased() }
    }
    
    public func togglePinTarget(achievement: Achievement, game: SteamGame) {
        togglePinTarget(achievement: achievement, gameName: game.name, appId: game.appId)
    }
    
    public func togglePinTarget(achievement: Achievement, gameName: String = "", appId: Int = 0) {
        triggerHaptic()
        if let idx = pinnedTargets.firstIndex(where: { $0.achievement.apiName.lowercased() == achievement.apiName.lowercased() }) {
            pinnedTargets.remove(at: idx)
        } else {
            let gName = gameName.isEmpty ? (games.first(where: { $0.appId == appId })?.name ?? "Steam Game") : gameName
            let target = PinnedTarget(appId: appId, gameName: gName, achievement: achievement)
            pinnedTargets.append(target)
        }
    }
    
    public func removePinnedTarget(id: String) {
        triggerHaptic()
        pinnedTargets.removeAll { $0.id == id }
    }
    
    public func updateTargetNote(id: String, note: String) {
        if let idx = pinnedTargets.firstIndex(where: { $0.id == id }) {
            pinnedTargets[idx].notes = note
        }
    }
    
    // Tagging Management
    public func getTags(for apiName: String) -> [AchievementTag] {
        tagsMap[apiName.lowercased()] ?? []
    }
    
    public func toggleTag(_ tag: AchievementTag, for apiName: String) {
        triggerHaptic()
        let key = apiName.lowercased()
        var existing = tagsMap[key] ?? []
        if let idx = existing.firstIndex(of: tag) {
            existing.remove(at: idx)
        } else {
            existing.append(tag)
        }
        tagsMap[key] = existing
    }
    
    // Walkthrough Helper
    public func openWalkthrough(for achievement: Achievement, gameName: String) {
        let query = "\(gameName) \(achievement.displayName) walkthrough"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.youtube.com/results?search_query=\(query)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // Exports
    public func exportMarkdown() {
        triggerHaptic()
        let md = LibraryExporter.shared.exportToMarkdown(games: visibleGames, player: player)
        if let url = LibraryExporter.shared.saveExportFile(content: md, filename: "AchievementHunter_Report", ext: "md") {
            exportMessage = "Saved report to \(url.lastPathComponent)!"
        }
    }
    
    public func exportCSV() {
        triggerHaptic()
        let csv = LibraryExporter.shared.exportToCSV(games: visibleGames)
        if let url = LibraryExporter.shared.saveExportFile(content: csv, filename: "AchievementHunter_Library", ext: "csv") {
            exportMessage = "Saved spreadsheet to \(url.lastPathComponent)!"
        }
    }
    
    // MARK: - Account Context
    
    private typealias AccountRef = FetchRef
    
    private var accountRef: AccountRef?
    
    private func currentAccountRef() -> AccountRef? {
        if let ref = accountRef { return ref }
        let target = authenticatedSteamId ?? steamIdOrVanity
        guard !target.isEmpty else { return nil }
        let info = SteamTargetInfo(input: target)
        return AccountRef(target: target, vanity: info.vanitySlug, steamId64: info.steamId64, steamId: info.steamId64 ?? target)
    }
    
    // Direct Steam Login Handler from WebKit
    public func handleSteamLoginSuccess(
        steamId: String,
        initialGames: [SteamGame] = [],
        detectedApiKey: String? = nil,
        cookies: [HTTPCookie] = [],
        webToken tokenJWT: String? = nil
    ) {
        self.authenticatedSteamId = steamId
        self.achievementsPrivateNotice = false
        self.webToken = tokenJWT.flatMap { SteamWebToken(jwt: $0) }
        AppLog.shared.log("Signed in as \(steamId): token \(webToken == nil ? "NOT received (using the games-page fallback)" : "received, valid until \(webToken!.expiresAt)"), cookies \(cookies.count), preloaded games \(initialGames.count)")
        self.isAuthenticated = true
        self.sessionCookies = cookies
        self.steamIdOrVanity = steamId
        
        // A key typed in the "Use an API key" tab is an explicit choice and replaces any earlier one.
        if let detected = detectedApiKey, !detected.isEmpty {
            self.apiKey = detected
        }
        
        Task {
            await fetchDirectlyFromAccount(target: steamId, preloadedGames: initialGames)
        }
    }
    
    public func fetchDirectlyFromAccount(steamId: String) async {
        await fetchDirectlyFromAccount(target: steamId)
    }
    
    /// With an API key the official Web API is used for the profile, so no page scraping is involved.
    /// Without one (or if the API fails) the public community pages are used.
    private func resolveProfile(target: String) async throws -> (player: SteamPlayer, initialGames: [SteamGame], vanitySlug: String?, steamId64: String?) {
        // GetPlayerSummaries needs an API key (it refuses the sign-in token), so only key users go through it; everyone
        // else reads the profile page, saving one failing request per sync.
        if let auth = activeAuth, !apiKey.isEmpty {
            do {
                // The numeric id is known when the target is one, or can be resolved with an API key. For a plain
                // vanity name we use the public profile page below; never assume the signed-in account.
                var id = SteamTargetInfo(input: target).steamId64
                if id == nil, !apiKey.isEmpty {
                    id = try await SteamAPIService.shared.resolveVanityURL(target, apiKey: apiKey)
                }
                if let id = id {
                    let p = try await SteamAPIService.shared.fetchPlayerSummary(steamId: id, auth: auth)
                    var vanity = SteamTargetInfo(input: target).vanitySlug
                    if let url = p.profileUrl, let range = url.range(of: "/id/") {
                        let slug = url[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        if !slug.isEmpty { vanity = slug }
                    }
                    if let v = vanity, v.allSatisfy({ $0.isNumber }) { vanity = nil }
                    return (p, [], vanity, id)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // fall back to the public profile page
            }
        }
        return try await SteamCommunityService.shared.resolveAndFetchProfile(target: target, cookies: sessionCookies)
    }
    
    /// Phase 1 (blocking overlay): resolve the profile and the list of games.
    /// Phase 2 (background, non-blocking): fetch achievements, concurrently. By default only games whose
    /// playtime changed (or that never loaded / went stale) are refetched; `forceFull` refetches all.
    /// A sync needs a way to read the account: a Steam sign-in or an API key. Steam no longer shows game lists to
    /// anonymous visitors, so there is no public-profile mode.
    public var hasCredentials: Bool {
        !apiKey.isEmpty || !sessionCookies.isEmpty || webToken?.isFresh == true
    }
    
    /// `silent`: a background refresh. No blocking overlay, no error pop-ups (problems go to the log), and the
    /// current screen/selection is left alone.
    public func fetchDirectlyFromAccount(target: String, preloadedGames: [SteamGame] = [], forceFull: Bool = false, silent: Bool = false) async {
        await cacheLoadTask?.value
        guard hasCredentials else {
            if !silent {
                errorMessage = "Sign in with Steam, or add a Steam Web API key, to sync your library."
                if !isLoginPresented { isLoginPresented = true }
            }
            AppLog.shared.log("Sync not started: no sign-in and no API key")
            return
        }
        guard !isSyncBusy else { return }
        isSyncBusy = true
        defer { isSyncBusy = false }
        syncIsBackground = silent
        achievementSyncTask?.cancel()
        if !silent {
            isLoading = true
            errorMessage = nil
            syncProgress = 0.05
            syncStageText = "Connecting to Steam..."
            syncDetailText = "Resolving Steam profile..."
        }
        await ensureWebToken()
        
        do {
            // 1. Fetch Profile
            if !silent { syncProgress = 0.15 }
            if !silent { syncStageText = "Fetching player profile..." }
            let (fetchedPlayer, profileGames, vanitySlug, steamId64) = try await resolveProfile(target: target)
            AppLog.shared.log("Profile resolved for \(fetchedPlayer.steamId); credentials: \(apiKey.isEmpty ? (activeAuth == nil ? "none" : "sign-in token") : "API key")")
            
            // A different account than the cached one: nothing cached (games, unlock feed, pins) applies to it.
            let isSameAccount = self.player?.steamId == nil || self.player?.steamId == fetchedPlayer.steamId
            if !isSameAccount {
                pinnedTargets.removeAll()
                unlockFeed.removeAll()
                saveFeed()
            }
            
            self.player = statusDebouncer.resolve(observed: fetchedPlayer, previous: self.player)
            self.authenticatedSteamId = fetchedPlayer.steamId
            self.isAuthenticated = true
            if let vanity = vanitySlug, !vanity.isEmpty {
                self.steamIdOrVanity = vanity
            } else {
                self.steamIdOrVanity = fetchedPlayer.steamId
            }
            
            // 2. Fetch Games
            if !silent { syncProgress = 0.30 }
            if !silent { syncStageText = "Fetching your games library..." }
            var fetchedGames = preloadedGames
            // Public pages only expose a handful of games. Such a partial list must never shrink a library that
            // was loaded earlier with a full sign-in.
            var isPartialList = false
            
            if fetchedGames.isEmpty, let auth = activeAuth {
                syncDetailText = apiKey.isEmpty ? "Loading your library with your Steam sign-in..." : "Querying Steam Web API (IPlayerService)..."
                do {
                    let apiGames = try await SteamAPIService.shared.fetchOwnedGames(steamId: fetchedPlayer.steamId, auth: auth)
                    if !apiGames.isEmpty { fetchedGames = apiGames }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if !silent { syncDetailText = "Web API failed (\(error.localizedDescription)) - trying the public community pages..." }
                }
            }
            
            if fetchedGames.isEmpty {
                if !silent { syncDetailText = "Scanning public library & showcase games..." }
                let commGames = try await SteamCommunityService.shared.fetchOwnedGames(
                    target: target,
                    vanitySlug: vanitySlug,
                    steamId64: steamId64,
                    initialGames: profileGames,
                    cookies: sessionCookies
                )
                if !commGames.isEmpty {
                    fetchedGames = commGames
                    isPartialList = true
                }
            }
            
            AppLog.shared.log("Library: \(fetchedGames.count) games (\(isPartialList ? "public pages only, partial" : (preloadedGames.isEmpty ? "API" : "sign-in page")))")
            guard !fetchedGames.isEmpty else {
                throw SteamAPIError.custom("No games could be loaded. \(SteamPrivacyHelp.steps)")
            }
            
            // Merge with what we already have: keep achievements, and work out which games need a refetch.
            let existing = isSameAccount
                ? Dictionary(self.games.map { ($0.appId, $0) }, uniquingKeysWith: { first, _ in first })
                : [:]
            let staleCutoff = Date().addingTimeInterval(-Self.staleAfter)
            var needsRefresh = Set<Int>()
            var changed = Set<Int>()
            for i in fetchedGames.indices {
                let id = fetchedGames[i].appId
                guard let old = existing[id] else {
                    needsRefresh.insert(id)
                    changed.insert(id)
                    continue
                }
                if old.hasAchievementsLoaded {
                    fetchedGames[i].achievements = old.achievements
                    // Achievement Sets and the user's DLC choices belong with the achievements: carry them over too,
                    // otherwise every re-sync would silently drop the sets of games that weren't refetched.
                    fetchedGames[i].achievementGroups = old.achievementGroups
                    fetchedGames[i].dlcOverrides = old.dlcOverrides
                    fetchedGames[i].hasAchievementsLoaded = true
                    fetchedGames[i].lastFetchedAt = old.lastFetchedAt
                    fetchedGames[i].loadError = old.loadError
                    if fetchedGames[i].name.starts(with: "Steam Game #") { fetchedGames[i].name = old.name }
                    if fetchedGames[i].customHeaderUrl == nil { fetchedGames[i].customHeaderUrl = old.customHeaderUrl }
                }
                var playtimeChanged = false
                if fetchedGames[i].playtimeIsKnown == false, old.playtimeIsKnown != false {
                    // The source doesn't know playtime; don't throw away what we had.
                    fetchedGames[i].playtimeMinutes = old.playtimeMinutes
                    fetchedGames[i].playtimeIsKnown = nil
                } else if old.playtimeIsKnown != false {
                    playtimeChanged = old.playtimeMinutes != fetchedGames[i].playtimeMinutes
                }
                let stale = (old.lastFetchedAt ?? .distantPast) < staleCutoff
                // DLC sets whose ownership Steam hasn't told us about yet (data saved before this was read): ask once.
                let needsOwnership = old.achievementGroups?.contains { $0.dlcAppId != 0 && !$0.isDeveloperOnly && $0.ownedByPlayer == nil } == true
                if needsOwnership && activeAuth != nil && apiKey.isEmpty { needsRefresh.insert(id) }
                // Games known to have no achievements are not re-synced (re-checked only every few weeks,
                // in case the developer adds some) when "hide games without achievements" is on.
                let recheckEmpty = needsEmptyRecheck && old.hasNoAchievements
                let knownEmpty = old.hasNoAchievements
                    && (old.lastFetchedAt ?? .distantPast) > Date().addingTimeInterval(-Self.emptyRecheckAfter)
                if hideGamesWithoutAchievements && knownEmpty && !playtimeChanged && !forceFull && !recheckEmpty {
                    // skip entirely
                } else if !old.hasAchievementsLoaded || old.loadError != nil || playtimeChanged || stale || forceFull || recheckEmpty {
                    needsRefresh.insert(id)
                }
                if old != fetchedGames[i] { changed.insert(id) }
            }
            
            // One batch request tells how many achievements each game has unlocked. A different number than we have
            // saved means new unlocks (or a reset): refetch exactly those games. No need to wait for playtime to change.
            var progressMap: [Int: (unlocked: Int, total: Int)]? = nil
            if let auth = activeAuth, !fetchedGames.isEmpty {
                progressMap = await SteamAPIService.shared.fetchAchievementProgress(steamId: fetchedPlayer.steamId, appIds: fetchedGames.map { $0.appId }, auth: auth)
                if let progress = progressMap {
                    let changedByProgress = UnlockChangeDetector.changedAppIds(
                        games: fetchedGames.filter { !needsRefresh.contains($0.appId) }, progress: progress)
                    needsRefresh.formUnion(changedByProgress)
                    if !changedByProgress.isEmpty { AppLog.shared.log("\(silent ? "Background sync" : "Sync"): \(changedByProgress.count) games have a different unlock count than saved") }
                }
            }
            
            if isPartialList && isSameAccount {
                let fetchedIds = Set(fetchedGames.map { $0.appId })
                fetchedGames += existing.values.filter { !fetchedIds.contains($0.appId) }
            }
            
            // Replace "Steam Game #123" placeholders with real names from the public store.
            await resolvePlaceholderNames(in: &fetchedGames, changed: &changed)
            
            if !silent { syncProgress = 1.0 }
            if !silent { syncStageText = "Library loaded" }
            syncDetailText = needsRefresh.isEmpty
                ? "Everything is up to date."
                : "Found \(fetchedGames.count) games. Updating \(needsRefresh.count) in the background..."
            
            self.games = fetchedGames
            if selectedGameId == nil || !fetchedGames.contains(where: { $0.appId == selectedGameId }) {
                self.selectedGameId = fetchedGames.first?.appId
            }
            if !silent { self.isSettingsPresented = false }
            recomputeNowPlaying()
            dirtyGameIds.formUnion(changed)
            saveLocalCache(pruneOrphans: true)
            
            let ref = AccountRef(target: target, vanity: vanitySlug, steamId64: steamId64, steamId: fetchedPlayer.steamId)
            self.accountRef = ref
            if needsRefresh.isEmpty {
                lastSyncedAt = Date()
                UserDefaults.standard.set(true, forKey: Self.emptyRecheckKey)
                saveLocalCache()
            } else {
                startAchievementSync(ref: ref, ids: fetchedGames.map { $0.appId }.filter { needsRefresh.contains($0) }, progress: progressMap)
            }
        } catch is CancellationError {
            // superseded by a newer sync
        } catch {
            if !silent { self.errorMessage = error.localizedDescription }
            AppLog.shared.log("\(silent ? "Background sync" : "Sync") failed: \(error.localizedDescription)")
        }
        
        if !silent {
            try? await Task.sleep(nanoseconds: 400_000_000)
            isLoading = false
        }
    }
    
    // MARK: - Automatic background sync
    
    /// Minutes between silent syncs while the app is open (0 = off). The game you are playing is refreshed more
    /// often by Now Playing; this picks up unlocks in every other game (e.g. played on another device).
    @Published public var autoSyncMinutes: Int = (UserDefaults.standard.object(forKey: "auto_sync_minutes") as? Int) ?? 10 {
        didSet {
            UserDefaults.standard.set(autoSyncMinutes, forKey: "auto_sync_minutes")
            restartAutoSync()
        }
    }
    
    private var autoSyncTimer: Timer?
    
    public func restartAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
        guard autoSyncMinutes > 0 else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Double(autoSyncMinutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runBackgroundSyncIfDue() }
        }
        timer.tolerance = 20
        autoSyncTimer = timer
    }
    
    /// Runs a silent sync if one is due and nothing else is going on.
    public func runBackgroundSyncIfDue() async {
        guard autoSyncMinutes > 0, hasCredentials, !isLoading, !isSyncBusy, !isSyncingAchievements,
              !isOnboardingPresented, !isHydratingLibrary, !games.isEmpty,
              let target = currentAccountRef()?.target else { return }
        if let last = lastSyncedAt, Date().timeIntervalSince(last) < Double(autoSyncMinutes) * 60 * 0.8 { return }
        AppLog.shared.log("Background sync started (every \(autoSyncMinutes) min)")
        await fetchDirectlyFromAccount(target: target, silent: true)
    }
    
    public func syncWithSteam() async {
        guard !isLoading, !isSyncBusy else { return }   // a repeated ⌘R must not start a second library sync
        triggerHaptic()
        let idInput = steamIdOrVanity.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = !idInput.isEmpty ? idInput : (authenticatedSteamId ?? "")
        
        guard !target.isEmpty else {
            errorMessage = "Please enter your Steam Profile URL, Vanity Name, or SteamID64."
            return
        }
        
        await fetchDirectlyFromAccount(target: target)
    }
    
    /// Refetch every game, ignoring the incremental shortcuts.
    public func fullResync() async {
        guard !isLoading, !isSyncBusy else { return }
        triggerHaptic()
        guard let target = currentAccountRef()?.target else { return }
        await fetchDirectlyFromAccount(target: target, forceFull: true)
    }
    
    /// Delete every locally cached thing (library, schema/rarity, images) and rebuild from Steam.
    public func clearCacheAndResync() async {
        triggerHaptic()
        let target = currentAccountRef()?.target
        await cacheLoadTask?.value
        cancelAchievementSync()
        libraryStore.clear()
        MetadataCache.clear()
        await ImageLoader.shared.clearDisk()
        games.removeAll()
        selectedGameId = nil
        lastSyncedAt = nil
        dirtyGameIds.removeAll()
        recomputeNowPlaying()
        if let target = target {
            await fetchDirectlyFromAccount(target: target, forceFull: true)
        }
    }
    
    private func resolvePlaceholderNames(in games: inout [SteamGame], changed: inout Set<Int>) async {
        let ids = games.filter { $0.name.starts(with: "Steam Game #") }.prefix(80).map { $0.appId }
        guard !ids.isEmpty else { return }
        syncDetailText = "Looking up names for \(ids.count) games..."
        var names: [Int: String] = [:]
        await withTaskGroup(of: (Int, String?).self) { group in
            var iterator = ids.makeIterator()
            for _ in 0..<3 {
                if let id = iterator.next() { group.addTask { (id, await SteamAPIService.shared.fetchAppName(appId: id)) } }
            }
            while let (id, name) = await group.next() {
                if let name = name { names[id] = name }
                if let next = iterator.next() { group.addTask { (next, await SteamAPIService.shared.fetchAppName(appId: next)) } }
            }
        }
        for i in games.indices {
            if let name = names[games[i].appId] {
                games[i].name = name
                changed.insert(games[i].appId)
            }
        }
    }
    
    // MARK: - Achievement Sync (concurrent, incremental, resumable)
    
    /// True while the library list is being read (also during silent background syncs, which don't set `isLoading`).
    private var isSyncBusy = false
    /// The running achievement sync was started by the background timer (no banner for small ones).
    @Published public var syncIsBackground = false
    @Published public var isSyncingAchievements: Bool = false
    @Published public var achievementSyncDone: Int = 0
    @Published public var achievementSyncTotal: Int = 0
    @Published public var lastSyncedAt: Date? = nil
    /// Set when a sync couldn't read the player's unlocks because the profile's achievements are private.
    @Published public var achievementsPrivateNotice: Bool = false
    
    /// One-time repair: earlier versions saved games as "no achievements" whenever Steam answered "no stats" for
    /// the player (unplayed games) or refused a private profile. Those games are re-checked once.
    private static let emptyRecheckKey = "empty_games_recheck_v2"
    private var needsEmptyRecheck: Bool { !UserDefaults.standard.bool(forKey: Self.emptyRecheckKey) }
    
    private var achievementSyncTask: Task<Void, Never>?
    private var achievementSyncGeneration = 0
    private var inFlightLoads: Set<Int> = []
    // Measured on a real 240-game cold sync: 8 parallel = 21 s, 16 = 10.5 s, 24 = 7.6 s, no refusals from Steam.
    private static let maxConcurrentFetches = 20
    /// Games whose achievements were fetched more recently than this are skipped on a normal re-sync
    /// unless their playtime changed.
    private static let staleAfter: TimeInterval = 24 * 3600
    private static let emptyRecheckAfter: TimeInterval = 21 * 24 * 3600
    
    public var failedGames: [SteamGame] {
        games.filter { $0.loadError != nil }
    }
    
    public func cancelAchievementSync() {
        achievementSyncTask?.cancel()
        achievementSyncGeneration += 1
        isSyncingAchievements = false
        saveLocalCache()
    }
    
    /// Re-fetch only the games that failed or never loaded.
    public func retryFailedGames() {
        guard let ref = currentAccountRef() else { return }
        let ids = games.filter { $0.loadError != nil || !$0.hasAchievementsLoaded }.map { $0.appId }
        startAchievementSync(ref: ref, ids: ids)
    }
    
    private func startAchievementSync(ref: AccountRef, ids: [Int], progress given: [Int: (unlocked: Int, total: Int)]? = nil) {
        achievementSyncTask?.cancel()
        achievementSyncGeneration += 1
        let generation = achievementSyncGeneration
        
        guard !ids.isEmpty else {
            isSyncingAchievements = false
            return
        }
        
        isSyncingAchievements = true
        achievementSyncDone = 0
        achievementSyncTotal = ids.count
        
        let key = apiKey
        let cookies = sessionCookies
        let hadBefore = Set(games.filter { !$0.achievements.isEmpty }.map { $0.appId })
        let priorUnlocked = Dictionary(games.map { ($0.appId, $0.unlockedAchievements) }, uniquingKeysWith: { first, _ in first })
        let auth = activeAuth
        let tokenAuth: SteamAuth? = apiKey.isEmpty ? auth : nil
        let health = SyncHealth()
        achievementsPrivateNotice = false
        syncTally = SyncTally()
        syncStartedAt = Date()
        AppLog.shared.log("Sync started: \(ids.count) games to fetch, credentials: \(!key.isEmpty ? "API key" : (auth != nil ? "sign-in token" : "none")), cookies: \(cookies.isEmpty ? "none" : "\(cookies.count)")")
        
        achievementSyncTask = Task { [weak self] in
            var finishedNormally = true
            // With a key or sign-in, one batch request tells which games have ANY unlocks. Games with none and no
            // history need no per-game request at all: the catalog is the whole answer (a big saving for libraries
            // full of unplayed games, and far fewer requests for Steam to rate-limit).
            var progress = given
            if progress == nil, let auth = auth {
                progress = await SteamAPIService.shared.fetchAchievementProgress(steamId: ref.steamId, appIds: ids, auth: auth)
            }
            let progressMap = progress
            AppLog.shared.log("Batch progress: \(progressMap.map { "\($0.count) games, \($0.values.filter { $0.unlocked == 0 }.count) with 0 unlocked" } ?? (auth == nil ? "skipped (no credentials)" : "unavailable, using per-game requests"))")
            await withTaskGroup(of: (Int, GameFetchOutcome).self) { group in
                var iterator = ids.makeIterator()
                
                func enqueueNext() {
                    if let id = iterator.next() {
                        let knownLocked = progressMap?[id]?.unlocked == 0 && (priorUnlocked[id] ?? 0) == 0
                        group.addTask { (id, await GameFetcher.fetch(appId: id, ref: ref, apiKey: key, token: tokenAuth, cookies: cookies, hadAchievementsBefore: hadBefore.contains(id), health: health, knownLocked: knownLocked, previousUnlocked: priorUnlocked[id] ?? 0)) }
                    }
                }
                for _ in 0..<AppState.maxConcurrentFetches { enqueueNext() }
                
                // Results are applied in batches: one UI update per ~20 games (or 0.4 s) instead of one per game.
                var buffer: [(Int, GameFetchOutcome)] = []
                var lastFlush = Date()
                @MainActor func flush(_ owner: AppState) {
                    guard !buffer.isEmpty else { return }
                    owner.applyBatch(buffer)
                    owner.achievementSyncDone += buffer.count
                    if owner.achievementSyncDone / 100 != (owner.achievementSyncDone - buffer.count) / 100 { owner.saveLocalCache() }
                    buffer.removeAll(keepingCapacity: true)
                    lastFlush = Date()
                }
                
                while let (appId, outcome) = await group.next() {
                    guard let self = self, self.achievementSyncGeneration == generation, !Task.isCancelled else {
                        finishedNormally = false
                        group.cancelAll()
                        break
                    }
                    buffer.append((appId, outcome))
                    if buffer.count >= 20 || Date().timeIntervalSince(lastFlush) > 0.4 { flush(self) }
                    enqueueNext()
                }
                if let owner = self, owner.achievementSyncGeneration == generation { flush(owner) }
            }
            
            guard let self = self, self.achievementSyncGeneration == generation else { return }
            self.isSyncingAchievements = false
            if finishedNormally {
                self.lastSyncedAt = Date()
                UserDefaults.standard.set(true, forKey: AppState.emptyRecheckKey)
            }
            // Only people WITHOUT a sign-in can be told to sign in: a handful of unreadable games (e.g. a game Steam's
            // stats pages can't show) is not a privacy problem for someone who is signed in.
            self.achievementsPrivateNotice = health.communityBlocked && self.sessionCookies.isEmpty
            AppLog.shared.log(String(format: "Sync finished in %.0fs (%@): %@", Date().timeIntervalSince(self.syncStartedAt), finishedNormally ? "complete" : "stopped", self.syncTally.summary))
            self.saveLocalCache()
        }
    }
    
    /// Counts of what a sync found, written to the diagnostic log.
    private struct SyncTally {
        var withAchievements = 0, lockedOnly = 0, noAchievements = 0, unverified = 0, failed = 0
        var failureReasons: [String: Int] = [:]
        
        mutating func add(_ outcome: GameFetchOutcome) {
            switch outcome {
            case .loaded(let ach, _, _, _, let verified):
                if ach.isEmpty { noAchievements += 1 }
                else if !verified { unverified += 1 }
                else if ach.contains(where: { $0.isUnlocked }) { withAchievements += 1 }
                else { lockedOnly += 1 }
            case .failed(let reason):
                failed += 1
                failureReasons[String(reason.prefix(80)), default: 0] += 1
            case .cancelled:
                break
            }
        }
        
        var summary: String {
            var text = "with unlocks \(withAchievements), all locked \(lockedOnly), unreadable (private) \(unverified), no achievements \(noAchievements), failed \(failed)"
            if !failureReasons.isEmpty {
                text += " [" + failureReasons.sorted { $0.value > $1.value }.prefix(3).map { "\($0.value)x \($0.key)" }.joined(separator: "; ") + "]"
            }
            return text
        }
    }
    
    private var syncTally = SyncTally()
    private var syncStartedAt = Date()
    
    
    private func apply(_ outcome: GameFetchOutcome, appId: Int) {
        applyBatch([(appId, outcome)])
    }
    
    /// Applies many results with a single change notification (the UI redraws once, not once per game).
    private func applyBatch(_ batch: [(Int, GameFetchOutcome)]) {
        for (_, outcome) in batch { syncTally.add(outcome) }
        var updated = games
        var indexByApp: [Int: Int] = [:]
        indexByApp.reserveCapacity(updated.count)
        for (i, g) in updated.enumerated() { indexByApp[g.appId] = i }
        var changed = false
        
        for (appId, outcome) in batch {
            guard let i = indexByApp[appId] else { continue }
            switch outcome {
            case .loaded(let ach, let groups, let name, let logo, let verified):
                // Compare with the previous state BEFORE overwriting it (see UnlockDetector for the rules).
                let previous = updated[i]
                let newly = UnlockDetector.newUnlocks(previous: previous, fresh: ach, previousSyncAt: lastSyncedAt)
                if !newly.isEmpty {
                    let gameName = (name?.isEmpty == false && previous.name.starts(with: "Steam Game #")) ? name! : previous.name
                    recordUnlocks(newly, gameName: gameName, appId: appId)
                }
                if let name = name, !name.isEmpty, updated[i].name.starts(with: "Steam Game #") {
                    updated[i].name = name
                }
                if let logo = logo, !logo.isEmpty {
                    updated[i].customHeaderUrl = logo
                }
                updated[i].achievements = ach
                updated[i].achievementGroups = groups.isEmpty ? nil : groups
                updated[i].hasAchievementsLoaded = true
                updated[i].loadError = nil
                // Unverified results (private data) stay "stale" so the next sync, e.g. after signing in, re-checks them.
                updated[i].lastFetchedAt = verified ? Date() : nil
            case .failed(let message):
                // Keep any previously loaded achievements; just flag the game so it can be retried.
                updated[i].loadError = message
            case .cancelled:
                continue
            }
            dirtyGameIds.insert(appId)
            changed = true
        }
        if changed { games = updated }
    }
    
    /// Load (or retry) a single game, e.g. when it is opened or the user taps Retry.
    public func loadAchievements(for gameId: Int, force: Bool = false) async {
        await cacheLoadTask?.value
        guard let index = games.firstIndex(where: { $0.appId == gameId }) else { return }
        if !force && games[index].hasAchievementsLoaded && games[index].loadError == nil { return }
        guard !inFlightLoads.contains(gameId), let ref = currentAccountRef() else { return }
        
        inFlightLoads.insert(gameId)
        defer { inFlightLoads.remove(gameId) }
        
        let outcome = await GameFetcher.fetch(appId: gameId, ref: ref, apiKey: apiKey, token: apiKey.isEmpty ? activeAuth : nil, cookies: sessionCookies,
                                                  hadAchievementsBefore: !games[index].achievements.isEmpty, health: SyncHealth(),
                                                  previousUnlocked: games[index].unlockedAchievements)
        apply(outcome, appId: gameId)
        saveLocalCache()
    }
    
    /// "I own this DLC" for a DLC achievement set (nil = automatic: counts once you've unlocked something in it).
    public func setDLCOwned(_ owned: Bool?, groupId: Int, appId: Int) {
        guard let i = games.firstIndex(where: { $0.appId == appId }) else { return }
        var overrides = games[i].dlcOverrides ?? [:]
        if let owned = owned { overrides["\(groupId)"] = owned } else { overrides.removeValue(forKey: "\(groupId)") }
        games[i].dlcOverrides = overrides.isEmpty ? nil : overrides
        dirtyGameIds.insert(appId)
        saveLocalCache()
    }
    
    public func signOut() {
        triggerHaptic()
        achievementSyncTask?.cancel()
        achievementSyncGeneration += 1
        isSyncingAchievements = false
        
        authenticatedSteamId = nil
        isAuthenticated = false
        sessionCookies.removeAll()
        apiKey = ""
        steamIdOrVanity = ""
        accountRef = nil
        webToken = nil
        player = nil
        games.removeAll()
        selectedGameId = nil
        lastSyncedAt = nil
        dirtyGameIds.removeAll()
        recomputeNowPlaying()
        // Pinned targets and tags are your own notes and are kept; pins are cleared automatically
        // if you later sign in as a different Steam account.
        UserDefaults.standard.removeObject(forKey: "auth_steam_id")
        UserDefaults.standard.removeObject(forKey: "steam_api_key")
        UserDefaults.standard.removeObject(forKey: "steam_id_or_vanity")
        
        libraryStore.clear()
        MetadataCache.clear()
        Task { await ImageLoader.shared.clearDisk() }
        
        let dataStore = WKWebsiteDataStore.default()
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {}
        }
    }
    
    // MARK: - Unlock Feed
    
    @Published public var unlockFeed: [UnlockEvent] = []
    private static let maxFeedEvents = 300
    
    public var unseenUnlockCount: Int {
        unlockFeed.filter { !$0.isSeen }.count
    }
    
    private func recordUnlocks(_ achievements: [Achievement], gameName: String, appId: Int) {
        let now = Date()
        let existingIds = Set(unlockFeed.map { $0.id })
        var events: [UnlockEvent] = []
        for var a in achievements {
            a.gameAppId = appId
            a.gameName = gameName
            let event = UnlockEvent(appId: appId, gameName: gameName, achievement: a, detectedAt: now, isSeen: false)
            if !existingIds.contains(event.id) { events.append(event) }
        }
        guard !events.isEmpty else { return }
        unlockFeed = Array((events.sorted { $0.happenedAt > $1.happenedAt } + unlockFeed).prefix(Self.maxFeedEvents))
        saveFeed()
        let rare = UnlockNotifier.shared.notify(events)
        if let first = rare.first { showCelebration(first) }
    }
    
    /// The big in-app card for an ultra-rare unlock; goes away by itself.
    @Published public var celebration: UnlockEvent?
    let friendWatcher = FriendWatcher()
    private func showCelebration(_ event: UnlockEvent) {
        celebration = event
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            if self?.celebration?.id == event.id { self?.celebration = nil }
        }
    }
    
    /// Quiet hours, daily summary and celebration settings (Settings > Notifications).
    @Published public var notificationPolicy: NotificationPolicy = UnlockNotifier.policy {
        didSet { if notificationPolicy != oldValue { UnlockNotifier.policy = notificationPolicy } }
    }
    
    /// What the Activity Feed shows: the unlocks the app detected (with their "new" state) plus everything your library
    /// says you unlocked, by the real unlock time, so the feed is complete even for unlocks made while the app was
    /// closed, asleep, or on another device. Only the `maxDays` most recent days with activity are built, so opening
    /// the feed never has to process the whole history.
    public func activityDays(maxDays: Int) -> (days: [ActivityDay], hasMore: Bool) {
        let detectedIds = Set(unlockFeed.map { $0.id })
        // Both sources are newest first; merge them just far enough to cover the requested days.
        var merged: [UnlockEvent] = unlockFeed.sorted { $0.happenedAt > $1.happenedAt }
        let calendar = Calendar.current
        var libraryDays = Set<Date>()
        var items: [UnlockEvent] = []
        for item in unlockedByTime {
            guard let when = item.achievement.unlockTimestamp else { continue }
            libraryDays.insert(calendar.startOfDay(for: when))
            if libraryDays.count > maxDays + 1 { break }      // one extra day proves there is more history
            let event = UnlockEvent(appId: item.appId, gameName: item.gameName, achievement: item.achievement, detectedAt: when, isSeen: true)
            if !detectedIds.contains(event.id) { items.append(event) }
        }
        merged.append(contentsOf: items)
        merged.sort { $0.happenedAt > $1.happenedAt }
        return ActivityWindow.recentDays(from: merged, maxDays: maxDays, calendar: calendar)
    }
    
    public func markFeedSeen() {
        guard unlockFeed.contains(where: { !$0.isSeen }) else { return }
        for i in unlockFeed.indices { unlockFeed[i].isSeen = true }
        saveFeed()
    }
    
    public func clearFeed() {
        unlockFeed.removeAll()
        saveFeed()
    }
    
    private var feedFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AchievementHunter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("unlock_feed.json")
    }
    
    private static func loadFeed(from url: URL) -> [UnlockEvent] {
        guard let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder.library.decode([UnlockEvent].self, from: data) else { return [] }
        return events
    }
    
    private func saveFeed() {
        let snapshot = unlockFeed
        let url = feedFileURL
        Self.cacheQueue.async {
            if let data = try? JSONEncoder.library.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
    
    // MARK: - Persistent Cache
    
    private static let cacheQueue = DispatchQueue(label: "com.achievementhunter.feed", qos: .utility)
    private let libraryStore = LibraryStore()
    private var dirtyGameIds: Set<Int> = []
    
    /// Writes only the games that changed since the last save (plus a small index), off the main thread.
    private func saveLocalCache(pruneOrphans: Bool = false) {
        guard !games.isEmpty else { return }
        let dirty = games.filter { dirtyGameIds.contains($0.appId) }
        dirtyGameIds.removeAll()
        let index = LibraryIndex(
            schemaVersion: LibraryStore.currentVersion,
            player: player,
            lastSyncedAt: lastSyncedAt,
            stubs: games.map(GameStub.init)
        )
        libraryStore.save(index: index, dirty: dirty, prune: pruneOrphans)
    }
    
    // User Preferences Persistence
    private func savePinnedTargets() {
        if let encoded = try? JSONEncoder().encode(pinnedTargets) {
            UserDefaults.standard.set(encoded, forKey: "pinned_targets_v1")
        }
    }
    
    private func loadSavedPinnedTargets() {
        if let data = UserDefaults.standard.data(forKey: "pinned_targets_v1"),
           let decoded = try? JSONDecoder().decode([PinnedTarget].self, from: data) {
            self.pinnedTargets = decoded
        }
    }
    
    private func saveTags() {
        if let encoded = try? JSONEncoder().encode(tagsMap) {
            UserDefaults.standard.set(encoded, forKey: "achievement_tags_v1")
        }
    }
    
    private func loadSavedTags() {
        if let data = UserDefaults.standard.data(forKey: "achievement_tags_v1"),
           let decoded = try? JSONDecoder().decode([String: [AchievementTag]].self, from: data) {
            // API-name casing differs between Steam sources; tags are keyed case-insensitively.
            var merged: [String: [AchievementTag]] = [:]
            for (key, tags) in decoded { merged[key.lowercased(), default: []].append(contentsOf: tags.filter { !(merged[key.lowercased()] ?? []).contains($0) }) }
            self.tagsMap = merged
        }
    }
}
