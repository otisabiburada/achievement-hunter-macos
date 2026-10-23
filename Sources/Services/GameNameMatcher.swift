import Foundation

/// Compares game titles the way a person would: "DARK SOULS™ III" == "Dark Souls III", "Pokémon" == "Pokemon".
/// Needed because the profile page names the running game while the library uses the store's spelling.
public enum GameNameMatcher {
    public static func normalize(_ name: String) -> String {
        var s = name
        for mark in ["™", "®", "©"] { s = s.replacingOccurrences(of: mark, with: "") }
        s = s.replacingOccurrences(of: "&", with: "and")
        s = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
    
    public static func matches(_ a: String, _ b: String) -> Bool {
        let x = normalize(a), y = normalize(b)
        return !x.isEmpty && x == y
    }
}

/// Spots games whose unlock count on Steam differs from what is saved, using the batch progress answer.
public enum UnlockChangeDetector {
    public static func changedAppIds(games: [SteamGame], progress: [Int: (unlocked: Int, total: Int)]) -> Set<Int> {
        var changed = Set<Int>()
        for g in games where g.hasAchievementsLoaded && !g.achievements.isEmpty {
            let saved = g.achievements.reduce(0) { $0 + ($1.isUnlocked ? 1 : 0) }
            if let row = progress[g.appId], row.unlocked != saved { changed.insert(g.appId) }
        }
        return changed
    }
}
