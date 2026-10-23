import Foundation

/// Names and avatars for a list of friends, without an API key.
/// `GetPlayerSummaries` needs a key, so each friend's public mini profile is read instead (one small request each,
/// several at a time). Answers are kept for a day on disk, so the second visit is instant.
actor FriendProfiles {
    static let shared = FriendProfiles()
    
    private struct Entry: Codable {
        var name: String
        var avatar: String?
        var fetchedAt: Date
    }
    
    private let ttl: TimeInterval = 24 * 3600
    private let fileURL: URL
    private var entries: [String: Entry] = [:]
    private var loaded = false
    
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AchievementHunter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("friend_profiles.json")
    }
    
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.library.decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder.library.encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }
    
    /// Returns a profile for every id (a generic one if Steam doesn't answer for that friend).
    /// `progress` is called with the number of friends done so far.
    func profiles(
        for ids: [String],
        community: SteamCommunityService = .shared,
        progress: @Sendable @escaping (Int) -> Void = { _ in }
    ) async -> [SteamPlayer] {
        loadIfNeeded()
        let now = Date()
        var result: [String: SteamPlayer] = [:]
        var missing: [String] = []
        for id in ids {
            if let e = entries[id], now.timeIntervalSince(e.fetchedAt) < ttl {
                result[id] = SteamPlayer(steamId: id, personaName: e.name, avatarUrl: e.avatar)
            } else {
                missing.append(id)
            }
        }
        progress(result.count)
        
        if !missing.isEmpty {
            await withTaskGroup(of: (String, SteamPlayer?).self) { group in
                var iterator = missing.makeIterator()
                func next() { if let id = iterator.next() { group.addTask { (id, await community.fetchMiniProfileStatus(steamId64: id)) } } }
                for _ in 0..<3 { next() }   // a few at a time: Steam's bot filter refuses bursts
                var done = result.count
                while let (id, player) = await group.next() {
                    if let player = player {
                        entries[id] = Entry(name: player.personaName, avatar: player.avatarUrl, fetchedAt: now)
                        result[id] = SteamPlayer(steamId: id, personaName: player.personaName, avatarUrl: player.avatarUrl)
                    } else {
                        result[id] = SteamPlayer(steamId: id, personaName: "Steam user \(id.suffix(4))")
                        // Steam is refusing (or this friend can't be shown): stop asking for the rest, they keep a
                        // placeholder and are filled in on a later visit instead of making the block longer.
                        if await CommunityThrottle.shared.isBlocked { while iterator.next() != nil {} }
                    }
                    done += 1
                    progress(done)
                    next()
                }
            }
            save()
        }
        return ids.compactMap { result[$0] }
    }
}
