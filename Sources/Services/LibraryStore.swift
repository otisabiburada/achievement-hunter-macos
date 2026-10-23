import Foundation

/// Light per-game record kept in the index so a game survives even if its detail file is unreadable.
struct GameStub: Codable, Sendable {
    let appId: Int
    var name: String
    var playtimeMinutes: Int
    var iconHash: String?
    var customHeaderUrl: String?
    var playtimeIsKnown: Bool?
    
    init(_ g: SteamGame) {
        appId = g.appId
        name = g.name
        playtimeMinutes = g.playtimeMinutes
        iconHash = g.iconHash
        customHeaderUrl = g.customHeaderUrl
        playtimeIsKnown = g.playtimeIsKnown
    }
    
    var asGame: SteamGame {
        SteamGame(appId: appId, name: name, playtimeMinutes: playtimeMinutes, iconHash: iconHash,
                  customHeaderUrl: customHeaderUrl, playtimeIsKnown: playtimeIsKnown)
    }
}

struct LibraryIndex: Codable, Sendable {
    var schemaVersion: Int
    var player: SteamPlayer?
    var lastSyncedAt: Date?
    var stubs: [GameStub]
}

struct LoadedLibrary {
    var player: SteamPlayer?
    var games: [SteamGame]
    var lastSyncedAt: Date?
}

/// Versioned on-disk library:
///   AchievementHunter/library/index.json        (schema version, player, game stubs)
///   AchievementHunter/library/games/<appId>.json (one file per game)
/// Only changed games are rewritten, so saving a 1,000+ game library during sync stays cheap.
/// The old single-file `library_cache.json` (v1, unversioned) is migrated on first launch.
final class LibraryStore: @unchecked Sendable {
    static let currentVersion = 2
    
    private let root: URL
    private let libraryDir: URL
    private let gamesDir: URL
    private let indexURL: URL
    private let legacyURL: URL
    private let queue = DispatchQueue(label: "com.achievementhunter.library", qos: .utility)
    
    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AchievementHunter")
        self.root = base
        libraryDir = base.appendingPathComponent("library")
        gamesDir = libraryDir.appendingPathComponent("games")
        indexURL = libraryDir.appendingPathComponent("index.json")
        legacyURL = base.appendingPathComponent("library_cache.json")
        try? FileManager.default.createDirectory(at: gamesDir, withIntermediateDirectories: true)
    }
    
    // MARK: Load
    
    func load() -> LoadedLibrary? {
        if let data = try? Data(contentsOf: indexURL) {
            guard let index = try? JSONDecoder.library.decode(LibraryIndex.self, from: data) else {
                quarantineLibrary(reason: "unreadable-index")
                return nil
            }
            if index.schemaVersion > Self.currentVersion {
                // Written by a newer app version: don't read it and don't destroy it.
                quarantineLibrary(reason: "v\(index.schemaVersion)")
                return nil
            }
            return LoadedLibrary(player: index.player, games: loadGames(for: index), lastSyncedAt: index.lastSyncedAt)
        }
        return migrateLegacy()
    }
    
    /// Reads only the small index (player + game stubs): enough to show the library immediately.
    /// Returns nil if there is none, or if it is unreadable / from a newer app version (quarantined).
    func loadIndexOnly() -> LibraryIndex? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        guard let index = try? JSONDecoder.library.decode(LibraryIndex.self, from: data) else {
            quarantineLibrary(reason: "unreadable-index")
            return nil
        }
        if index.schemaVersion > Self.currentVersion {
            quarantineLibrary(reason: "v\(index.schemaVersion)")
            return nil
        }
        return index
    }
    
    /// Reads every game's detail file in parallel. Safe to call off the main thread.
    func loadGames(for index: LibraryIndex) -> [SteamGame] {
        let stubs = index.stubs
        var result = [SteamGame?](repeating: nil, count: stubs.count)
        let lock = NSLock()
        let dir = gamesDir
        DispatchQueue.concurrentPerform(iterations: stubs.count) { i in
            let url = dir.appendingPathComponent("\(stubs[i].appId).json")
            var game = stubs[i].asGame
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder.library.decode(SteamGame.self, from: data) {
                game = decoded
            }
            lock.lock(); result[i] = game; lock.unlock()
        }
        return result.compactMap { $0 }
    }
    
    /// v1 -> v2: split the single JSON blob into the versioned layout, keep the old file as a backup.
    private func migrateLegacy() -> LoadedLibrary? {
        struct LegacyV1: Codable {
            let player: SteamPlayer?
            let games: [SteamGame]
            let cachedAt: Date
        }
        guard let data = try? Data(contentsOf: legacyURL) else { return nil }
        guard let legacy = try? JSONDecoder.library.decode(LegacyV1.self, from: data), !legacy.games.isEmpty else {
            // Can't be read (e.g. model changed): keep it aside rather than silently dropping it.
            try? FileManager.default.moveItem(at: legacyURL, to: root.appendingPathComponent("library_cache.unreadable.json"))
            return nil
        }
        let index = LibraryIndex(schemaVersion: Self.currentVersion, player: legacy.player,
                                 lastSyncedAt: legacy.cachedAt, stubs: legacy.games.map(GameStub.init))
        writeSync(index: index, dirty: legacy.games, prune: true)
        try? FileManager.default.moveItem(at: legacyURL, to: root.appendingPathComponent("library_cache.v1.bak"))
        return LoadedLibrary(player: legacy.player, games: legacy.games, lastSyncedAt: legacy.cachedAt)
    }
    
    private func quarantineLibrary(reason: String) {
        let dest = root.appendingPathComponent("library.unreadable-\(reason)")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: libraryDir, to: dest)
        try? FileManager.default.createDirectory(at: gamesDir, withIntermediateDirectories: true)
    }
    
    // MARK: Save
    
    func save(index: LibraryIndex, dirty: [SteamGame], prune: Bool) {
        queue.async { [self] in writeSync(index: index, dirty: dirty, prune: prune) }
    }
    
    private func writeSync(index: LibraryIndex, dirty: [SteamGame], prune: Bool) {
        let fm = FileManager.default
        try? fm.createDirectory(at: gamesDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder.library
        for game in dirty {
            if let data = try? encoder.encode(game) {
                try? data.write(to: gamesDir.appendingPathComponent("\(game.appId).json"), options: .atomic)
            }
        }
        if prune {
            let keep = Set(index.stubs.map { "\($0.appId).json" })
            for name in (try? fm.contentsOfDirectory(atPath: gamesDir.path)) ?? [] where !keep.contains(name) {
                try? fm.removeItem(at: gamesDir.appendingPathComponent(name))
            }
        }
        if let data = try? encoder.encode(index) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
    
    func clear() {
        queue.async { [self] in
            try? FileManager.default.removeItem(at: libraryDir)
            try? FileManager.default.removeItem(at: legacyURL)
            try? FileManager.default.createDirectory(at: gamesDir, withIntermediateDirectories: true)
        }
    }
    
    /// Blocks until queued writes are done (used by tests and on quit).
    func flush() { queue.sync {} }
}

extension JSONEncoder {
    static var library: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }
}

extension JSONDecoder {
    /// Reads dates as seconds-since-1970; falls back to the legacy default (reference date) format.
    static var library: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(Double.self)
            // Legacy files used timeIntervalSinceReferenceDate (values far below 1e9 for current dates).
            return value > 1_000_000_000 ? Date(timeIntervalSince1970: value) : Date(timeIntervalSinceReferenceDate: value)
        }
        return d
    }
}
