import Foundation

public struct AchievementSchemaEntry: Codable, Sendable {
    public let displayName: String
    public let description: String
    public let icon: String?
    public let grayIcon: String?
    public let isHidden: Bool
}

/// Disk cache (in ~/Library/Caches, so it is safe to delete) for per-game schema and global rarity.
/// Schema (names, descriptions, icons) rarely changes; rarity drifts slowly. Re-syncs reuse them and
/// only the player's own unlock state has to be fetched.
enum MetadataCache {
    static let schemaTTL: TimeInterval = 14 * 24 * 3600
    static let rarityTTL: TimeInterval = 3 * 24 * 3600
    
    private struct Envelope<T: Codable>: Codable {
        let fetchedAt: Date
        let value: T
    }
    
    private static var dir: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AchievementHunter/metadata")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    
    private static func read<T: Codable>(_ name: String, as type: T.Type) -> (value: T, age: TimeInterval)? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
              let env = try? JSONDecoder.library.decode(Envelope<T>.self, from: data) else { return nil }
        return (env.value, Date().timeIntervalSince(env.fetchedAt))
    }
    
    private static func write<T: Codable>(_ value: T, name: String) {
        if let data = try? JSONEncoder.library.encode(Envelope(fetchedAt: Date(), value: value)) {
            try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
    }
    
    // fresh == within TTL; stale values are still returned (as `fresh: false`) for use when the network fails.
    static func schema(appId: Int) -> (value: [String: AchievementSchemaEntry], fresh: Bool)? {
        read("\(appId).schema.json", as: [String: AchievementSchemaEntry].self).map { ($0.value, $0.age < schemaTTL) }
    }
    
    static func storeSchema(_ value: [String: AchievementSchemaEntry], appId: Int) {
        write(value, name: "\(appId).schema.json")
    }
    
    static func rarity(appId: Int) -> (value: [String: Double], fresh: Bool)? {
        read("\(appId).rarity.json", as: [String: Double].self).map { ($0.value, $0.age < rarityTTL) }
    }
    
    static func storeRarity(_ value: [String: Double], appId: Int) {
        write(value, name: "\(appId).rarity.json")
    }
    
    // The catalog (names, icons, rarity, achievement sets) is cached for a shorter time: sets and DLC are added
    // over a game's lifetime and rarity drifts.
    static let catalogTTL: TimeInterval = 2 * 24 * 3600
    
    static func catalog(appId: Int) -> (value: AchievementCatalog, fresh: Bool)? {
        read("\(appId).catalog.json", as: AchievementCatalog.self).map { ($0.value, $0.age < catalogTTL) }
    }
    
    static func storeCatalog(_ value: AchievementCatalog, appId: Int) {
        write(value, name: "\(appId).catalog.json")
    }
    
    /// Removes one game's cached catalog (used by tests that need a cold cache).
    static func clearTestEntry(appId: Int) {
        for kind in ["catalog", "schema", "rarity"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(appId).\(kind).json"))
        }
    }
    
    static func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
