import Foundation

/// Links to walkthroughs and guides for a game or one achievement.
public enum WalkthroughLinks {
    /// TrueSteamAchievements game slug: the title with punctuation collapsed to hyphens
    /// ("Portal: Still Alive" -> "Portal-Still-Alive").
    public static func tsaSlug(_ name: String) -> String {
        var s = name
        for mark in ["™", "®", "©"] { s = s.replacingOccurrences(of: mark, with: "") }
        s = s.replacingOccurrences(of: "&", with: " and ")
        s = s.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
        s = s.folding(options: .diacriticInsensitive, locale: .current)
        var out = ""
        var pendingHyphen = false
        for ch in s {
            if ch.isLetter || ch.isNumber, ch.isASCII {
                if pendingHyphen && !out.isEmpty { out.append("-") }
                pendingHyphen = false
                out.append(ch)
            } else {
                pendingHyphen = true
            }
        }
        return out
    }
    
    /// The game's walkthrough page on TrueSteamAchievements (nil if the title yields no slug).
    public static func tsaGameURL(gameName: String) -> URL? {
        let slug = tsaSlug(gameName)
        guard !slug.isEmpty else { return nil }
        return URL(string: "https://truesteamachievements.com/game/\(slug)/walkthrough")
    }
    
    /// TrueSteamAchievements does not publish a stable id for each achievement, so achievement-level links go
    /// through a site-restricted search that lands on the matching achievement page and its guide.
    public static func tsaSearchURL(gameName: String, achievement: String?) -> URL {
        var terms = "site:truesteamachievements.com \"\(gameName)\""
        if let a = achievement, !a.isEmpty { terms += " \"\(a)\"" }
        return searchURL(terms)
    }
    
    public static func youtubeURL(gameName: String, achievement: String?) -> URL {
        var terms = "\(gameName)"
        if let a = achievement, !a.isEmpty { terms += " \(a)" }
        terms += achievement == nil ? " achievement guide" : " achievement walkthrough"
        return components("https://www.youtube.com/results", ["search_query": terms])
    }
    
    public static func steamGuidesURL(appId: Int, achievement: String?) -> URL {
        var items = ["appid": String(appId), "browsefilter": "trend", "requiredtags[]": "Achievements"]
        if let a = achievement, !a.isEmpty { items["searchText"] = a }
        return components("https://steamcommunity.com/app/\(appId)/guides/", items)
    }
    
    public static func googleURL(gameName: String, achievement: String?) -> URL {
        var terms = gameName
        if let a = achievement, !a.isEmpty { terms += " \(a) achievement guide" } else { terms += " achievement guide" }
        return searchURL(terms)
    }
    
    private static func searchURL(_ terms: String) -> URL {
        components("https://www.google.com/search", ["q": terms])
    }
    
    private static func components(_ base: String, _ items: [String: String]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves spaces as %20 and encodes quotes; make '+' unambiguous too.
        if let query = c.percentEncodedQuery { c.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%2B") }
        return c.url ?? URL(string: base)!
    }
}
