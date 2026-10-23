import Foundation

public struct SteamTargetInfo {
    public let rawInput: String
    public var steamId64: String?
    public var vanitySlug: String?
    
    public init(input: String) {
        var clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasSuffix("/") { clean.removeLast() }
        self.rawInput = clean
        
        if clean.contains("steamcommunity.com/id/") {
            let slug = clean.components(separatedBy: "steamcommunity.com/id/").last?
                .components(separatedBy: "/").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.vanitySlug = slug
            self.steamId64 = nil
        } else if clean.contains("steamcommunity.com/profiles/") {
            let id = clean.components(separatedBy: "steamcommunity.com/profiles/").last?
                .components(separatedBy: "/").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = id, id.allSatisfy({ $0.isNumber }) && id.count >= 17 {
                self.steamId64 = id
                self.vanitySlug = nil
            } else {
                self.steamId64 = nil
                self.vanitySlug = id
            }
        } else if clean.allSatisfy({ $0.isNumber }) && clean.count >= 17 {
            self.steamId64 = clean
            self.vanitySlug = nil
        } else {
            self.vanitySlug = clean
            self.steamId64 = nil
        }
    }
}

/// Steam's community pages (profile XML, mini profile, stats) sit behind a bot filter: a burst of requests gets
/// "403 Access Denied" for a while. Every community request goes through this gate: a polite request rate, and after
/// a refusal NO further requests for a cool-down, so the block is short instead of being prolonged by retries.
actor CommunityThrottle {
    static let shared = CommunityThrottle()
    
    private let spacing: TimeInterval
    private let coolDown: TimeInterval
    private var nextSlot = Date.distantPast
    private var blockedUntil = Date.distantPast
    
    init(spacing: TimeInterval = 0.2, coolDown: TimeInterval = 90) {
        self.spacing = spacing
        self.coolDown = coolDown
    }
    
    var isBlocked: Bool { Date() < blockedUntil }
    var secondsBlocked: Int { max(0, Int(blockedUntil.timeIntervalSinceNow.rounded(.up))) }
    
    /// Waits for this request's turn. Returns false (do not send) while the community host is cooling down.
    func acquire() async -> Bool {
        if Date() < blockedUntil { return false }
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(spacing)
        if slot > now { try? await Task.sleep(nanoseconds: UInt64(slot.timeIntervalSince(now) * 1_000_000_000)) }
        return Date() >= blockedUntil
    }
    
    func noteRefused() {
        blockedUntil = Date().addingTimeInterval(coolDown)
        AppLog.shared.log("Steam community pages refused requests (Access Denied); pausing them for \(Int(coolDown)) seconds")
    }
    
    func reset() { blockedUntil = .distantPast; nextSlot = .distantPast }
}

public final class SteamCommunityService {
    public static let shared = SteamCommunityService()
    private let session: URLSession
    
    public init(session: URLSession? = nil) {
        self.session = session ?? HTTPClient.session
    }
    
    /// Every community request goes through here (see `CommunityThrottle`).
    private func send(_ request: URLRequest, maxAttempts: Int = 4) async throws -> (Data, HTTPURLResponse) {
        guard await CommunityThrottle.shared.acquire() else { throw SteamAPIError.rateLimited }
        let (data, http) = try await HTTPClient.data(for: request, session: session, maxAttempts: maxAttempts)
        if http.statusCode == 403, let head = String(data: data.prefix(300), encoding: .utf8), head.localizedCaseInsensitiveContains("access denied") {
            await CommunityThrottle.shared.noteRefused()
            throw SteamAPIError.rateLimited
        }
        return (data, http)
    }
    
    private func buildCookieHeader(from cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
    
    // Resolve and fetch player profile and most played games from XML
    public func resolveAndFetchProfile(target: String, cookies: [HTTPCookie]? = nil) async throws -> (player: SteamPlayer, initialGames: [SteamGame], vanitySlug: String?, steamId64: String?) {
        let info = SteamTargetInfo(input: target)
        
        var xmlUrls: [URL] = []
        if let slug = info.vanitySlug, let url = URL(string: "https://steamcommunity.com/id/\(slug)/?xml=1") {
            xmlUrls.append(url)
        }
        if let id = info.steamId64, let url = URL(string: "https://steamcommunity.com/profiles/\(id)/?xml=1") {
            xmlUrls.append(url)
        }
        if xmlUrls.isEmpty {
            if let url = URL(string: "https://steamcommunity.com/id/\(info.rawInput)/?xml=1") {
                xmlUrls.append(url)
            }
            if let url = URL(string: "https://steamcommunity.com/profiles/\(info.rawInput)/?xml=1") {
                xmlUrls.append(url)
            }
        }
        
        var lastError: Error? = nil
        for url in xmlUrls {
            do {
                // Steam serves this XML with "Cache-Control: max-age=3600" (and a CDN in front of it), so an
                // ordinary request can return a profile status that is up to an hour old. A unique query value and
                // "don't use any cache" make every request fresh.
                var fresh = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var items = fresh?.queryItems ?? []
                items.append(URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000))))
                fresh?.queryItems = items
                var request = URLRequest(url: fresh?.url ?? url)
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.setValue(HTTPClient.browserUserAgent, forHTTPHeaderField: "User-Agent")
                if let cookies = cookies, !cookies.isEmpty {
                    request.setValue(buildCookieHeader(from: cookies), forHTTPHeaderField: "Cookie")
                }
                
                let (data, _) = try await send(request)
                let parser = CommunityProfileParser()
                let xmlParser = XMLParser(data: data)
                xmlParser.delegate = parser
                xmlParser.parse()
                
                // If it returned an error response or no ID found
                if parser.steamId.isEmpty && parser.customURL.isEmpty && parser.personaName.isEmpty {
                    continue
                }
                
                let resolvedSteamId = !parser.steamId.isEmpty ? parser.steamId : (info.steamId64 ?? info.rawInput)
                let personaName = !parser.personaName.isEmpty ? parser.personaName : "Steam Player"
                let avatar = !parser.avatarFull.isEmpty ? parser.avatarFull : nil
                let vanity = !parser.customURL.isEmpty ? parser.customURL : info.vanitySlug
                
                let profileUrl: String
                if let v = vanity, !v.isEmpty {
                    profileUrl = "https://steamcommunity.com/id/\(v)"
                } else {
                    profileUrl = "https://steamcommunity.com/profiles/\(resolvedSteamId)"
                }
                
                let player = SteamPlayer(
                    steamId: resolvedSteamId,
                    personaName: personaName,
                    avatarUrl: avatar,
                    profileUrl: profileUrl,
                    personaState: (parser.onlineState.lowercased() == "online" || parser.onlineState.lowercased() == "in-game") ? 1 : 0,
                    currentGameId: parser.inGameAppId,
                    currentGameName: Self.currentGameName(onlineState: parser.onlineState, stateMessage: parser.stateMessage, explicit: parser.inGameGameName)
                )
                
                let games: [SteamGame] = parser.mostPlayedGames.map { item in
                    SteamGame(
                        appId: item.appId,
                        name: item.name,
                        playtimeMinutes: Int(item.hours * 60.0),
                        iconHash: nil,
                        customHeaderUrl: item.logo,
                        achievements: [],
                        hasAchievementsLoaded: false
                    )
                }
                
                return (player, games, vanity, parser.steamId.isEmpty ? nil : parser.steamId)
            } catch {
                if case SteamAPIError.rateLimited = error { throw error }
                if error is CancellationError { throw error }
                lastError = error
            }
        }
        
        throw lastError ?? SteamAPIError.playerNotFound
    }
    
    // Backwards-compatible player profile fetcher
    public func fetchPlayerProfile(steamId: String, cookies: [HTTPCookie]? = nil) async throws -> SteamPlayer {
        let (player, _, _, _) = try await resolveAndFetchProfile(target: steamId, cookies: cookies)
        return player
    }
    
    // Fetch owned games list with playtime from Community HTML (rgGames), profile HTML, or XML
    public func fetchOwnedGames(
        target: String,
        vanitySlug: String? = nil,
        steamId64: String? = nil,
        initialGames: [SteamGame] = [],
        cookies: [HTTPCookie]? = nil
    ) async throws -> [SteamGame] {
        var gamesMap: [Int: SteamGame] = [:]
        for g in initialGames {
            gamesMap[g.appId] = g
        }
        
        let info = SteamTargetInfo(input: target)
        let resolvedVanity = vanitySlug ?? info.vanitySlug
        let resolvedId = steamId64 ?? info.steamId64
        
        // 1. Try fetching via rgGames from games page
        var candidateGamesUrls: [String] = []
        if cookies != nil && !(cookies?.isEmpty ?? true) {
            candidateGamesUrls.append("https://steamcommunity.com/my/games/?tab=all")
        }
        if let v = resolvedVanity, !v.isEmpty {
            candidateGamesUrls.append("https://steamcommunity.com/id/\(v)/games/?tab=all")
        }
        if let id = resolvedId, !id.isEmpty {
            candidateGamesUrls.append("https://steamcommunity.com/profiles/\(id)/games/?tab=all")
        }
        
        for urlStr in candidateGamesUrls {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.setValue(HTTPClient.browserUserAgent, forHTTPHeaderField: "User-Agent")
            if let cookies = cookies, !cookies.isEmpty {
                request.setValue(buildCookieHeader(from: cookies), forHTTPHeaderField: "Cookie")
            }
            
            if let (data, _) = try? await send(request),
               let html = String(data: data, encoding: .utf8),
               html.contains("var rgGames = ") {
                if let range = html.range(of: "var rgGames = "),
                   let endRange = html[range.upperBound...].range(of: ";\n") ?? html[range.upperBound...].range(of: ";\r\n") ?? html[range.upperBound...].range(of: ";") {
                    let jsonString = String(html[range.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let jsonData = jsonString.data(using: .utf8),
                       let rawList = try? JSONDecoder().decode([CommunityRgGame].self, from: jsonData),
                       !rawList.isEmpty {
                        for item in rawList {
                            let clean = item.hours_forever.replacingOccurrences(of: ",", with: "")
                            let hours = Double(clean) ?? 0.0
                            let g = SteamGame(
                                appId: item.appid,
                                name: item.name,
                                playtimeMinutes: Int(hours * 60.0),
                                iconHash: nil,
                                customHeaderUrl: item.logo.isEmpty ? "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(item.appid)/header.jpg" : item.logo,
                                achievements: [],
                                hasAchievementsLoaded: false
                            )
                            gamesMap[g.appId] = g
                        }
                        break
                    }
                }
            }
        }
        
        // 2. Scrape Profile HTML for recent games, showcases, and achievement links
        var profileUrls: [String] = []
        if let v = resolvedVanity, !v.isEmpty {
            profileUrls.append("https://steamcommunity.com/id/\(v)/")
        }
        if let id = resolvedId, !id.isEmpty {
            profileUrls.append("https://steamcommunity.com/profiles/\(id)/")
        }
        
        for pUrlStr in profileUrls {
            guard let url = URL(string: pUrlStr) else { continue }
            var request = URLRequest(url: url)
            request.setValue(HTTPClient.browserUserAgent, forHTTPHeaderField: "User-Agent")
            if let cookies = cookies, !cookies.isEmpty {
                request.setValue(buildCookieHeader(from: cookies), forHTTPHeaderField: "Cookie")
            }
            
            if let (data, _) = try? await send(request),
               let html = String(data: data, encoding: .utf8) {
                
                // A. Parse recent games
                let recentPattern = #"(?s)<div class="recent_game">.*?href="https://steamcommunity.com/app/(\d+)".*?<img class="game_capsule" src="([^"]+)".*?<div class="game_name"><a class="whiteLink"[^>]*>([^<]+)</a>"#
                if let regex = try? NSRegularExpression(pattern: recentPattern) {
                    let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                    for m in matches {
                        if let idRange = Range(m.range(at: 1), in: html),
                           let logoRange = Range(m.range(at: 2), in: html),
                           let nameRange = Range(m.range(at: 3), in: html),
                           let id = Int(html[idRange]) {
                            let name = String(html[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let logo = String(html[logoRange])
                            if gamesMap[id] == nil {
                                gamesMap[id] = SteamGame(
                                    appId: id,
                                    name: name,
                                    playtimeMinutes: 0,
                                    iconHash: nil,
                                    customHeaderUrl: logo,
                                    achievements: [],
                                    hasAchievementsLoaded: false,
                                    playtimeIsKnown: false
                                )
                            }
                        }
                    }
                }
                
                // B. Parse achievement links: /achievements/(\d+)
                let achPattern = #"achievements/(\d+)"#
                if let regex = try? NSRegularExpression(pattern: achPattern) {
                    let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                    for m in matches {
                        if let idRange = Range(m.range(at: 1), in: html),
                           let id = Int(html[idRange]) {
                            if gamesMap[id] == nil {
                                gamesMap[id] = SteamGame(
                                    appId: id,
                                    name: "Steam Game #\(id)",
                                    playtimeMinutes: 0,
                                    iconHash: nil,
                                    customHeaderUrl: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg",
                                    achievements: [],
                                    hasAchievementsLoaded: false,
                                    playtimeIsKnown: false
                                )
                            }
                        }
                    }
                }
                
                break
            }
        }
        
        let result = Array(gamesMap.values).sorted { $0.playtimeMinutes > $1.playtimeMinutes }
        return result
    }
    
    /// The game a profile is playing right now. Steam's profile XML no longer carries an `inGameInfo` block; it says
    /// `<onlineState>in-game</onlineState>` and `<stateMessage>In-Game<br/>GUILTY GEAR</stateMessage>` instead.
    static func currentGameName(onlineState: String, stateMessage: String, explicit: String) -> String? {
        if !explicit.isEmpty { return explicit }
        guard onlineState.lowercased() == "in-game" else { return nil }
        let normalized = stateMessage
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
        let lines = normalized.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        var name = lines.dropFirst().joined(separator: " ")
        for (entity, char) in [("&amp;", "&"), ("&#39;", "'"), ("&#x27;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">")] {
            name = name.replacingOccurrences(of: entity, with: char)
        }
        return name.isEmpty ? nil : name
    }
    
    // MARK: Live status (mini profile)
    
    /// What Steam's hover-card says right now. Unlike the profile XML it is not cached for an hour, and it names the
    /// game (with its app id) the player is in.
    struct MiniProfileStatus: Equatable {
        var personaName: String
        var avatarUrl: String?
        var stateClass: String        // "in-game", "online", "offline"
        var gameName: String?
        var appId: Int?
        
        var isInGame: Bool { stateClass == "in-game" && (gameName != nil || appId != nil) }
    }
    
    static func parseMiniProfile(_ html: String) -> MiniProfileStatus? {
        guard html.contains("miniprofile_container") else { return nil }
        func first(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }
        func decode(_ text: String) -> String {
            var t = text
            for (entity, char) in [("&amp;", "&"), ("&#39;", "'"), ("&#x27;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">")] {
                t = t.replacingOccurrences(of: entity, with: char)
            }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let state = first(#"class="persona\s+([a-z-]+)""#) ?? "offline"
        let name = first(#"class="persona[^"]*">([^<]*)<"#).map(decode) ?? "Steam Player"
        let gameName = first(#"class="miniprofile_game_name">([^<]*)<"#).map(decode).flatMap { $0.isEmpty ? nil : $0 }
        let appId = first(#"class="game_logo"[^>]*src="[^"]*/apps/(\d+)/"#).flatMap { Int($0) }
        // The markup holds TWO images: the avatar *frame* decoration (community_assets/images/items/...png) comes first,
        // the real picture is hosted on avatars.*. Take the picture (upgraded to the full-size file), never the frame.
        let avatar = first(#"src="(https://avatars[^"]+?)(?:_medium|_full)?\.jpg"#).map { $0 + "_full.jpg" }
        return MiniProfileStatus(personaName: name, avatarUrl: avatar, stateClass: state, gameName: gameName, appId: appId)
    }
    
    /// Real-time status for a SteamID64, or nil if Steam doesn't answer / the profile can't be shown.
    func fetchMiniProfileStatus(steamId64: String) async -> SteamPlayer? {
        guard let id = UInt64(steamId64), id > 76561197960265728 else { return nil }
        let account = id - 76561197960265728
        var comps = URLComponents(string: "https://steamcommunity.com/miniprofile/\(account)")
        comps?.queryItems = [URLQueryItem(name: "l", value: "english"), URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        guard let url = comps?.url else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(HTTPClient.browserUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, http) = try? await send(request, maxAttempts: 2),
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8),
              let status = Self.parseMiniProfile(html) else { return nil }
        return SteamPlayer(
            steamId: steamId64,
            personaName: status.personaName,
            avatarUrl: status.avatarUrl,
            profileUrl: "https://steamcommunity.com/profiles/\(steamId64)",
            personaState: status.stateClass == "offline" ? 0 : 1,
            currentGameId: status.isInGame ? status.appId : nil,
            currentGameName: status.isInGame ? status.gameName : nil
        )
    }
    
    enum HTMLReply { case noStatsForPlayer, profileUnavailable, notHTML }
    
    /// Steam sometimes answers the `?xml=1` stats request with an HTML page. The profile's own page
    /// ("Steam Community :: <name>") means the profile is readable but has no stats for this game; an error page,
    /// a private-profile notice or a sign-in page means the profile can't be read.
    static func classifyHTMLReply(_ data: Data) -> HTMLReply {
        guard let head = String(data: data.prefix(6000), encoding: .utf8)?.lowercased(),
              head.contains("<html") || head.contains("<!doctype html") else { return .notHTML }
        if let range = head.range(of: "<title>"), let end = head.range(of: "</title>", range: range.upperBound..<head.endIndex) {
            let title = head[range.upperBound..<end.lowerBound]
            if title.contains("error") || title.contains("sign in") { return .profileUnavailable }
            if title.contains("steam community ::") { return .noStatsForPlayer }
        }
        if head.contains("this profile is private") { return .profileUnavailable }
        return .profileUnavailable
    }
    
    /// Unlocked/total for another player's game via the community stats page (works for friends when signed in,
    /// so Friend Compare doesn't need an API key).
    public func fetchAchievementCounts(steamId: String, appId: Int, cookies: [HTTPCookie]?) async throws -> (unlocked: Int, total: Int) {
        guard let url = URL(string: "https://steamcommunity.com/profiles/\(steamId)/stats/\(appId)/?xml=1") else { throw SteamAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(HTTPClient.browserUserAgent, forHTTPHeaderField: "User-Agent")
        if let cookies = cookies, !cookies.isEmpty { request.setValue(buildCookieHeader(from: cookies), forHTTPHeaderField: "Cookie") }
        var (data, response) = try await send(request)
        if let finalURL = response.url, finalURL.query?.contains("xml=1") != true,
           var comps = URLComponents(url: finalURL, resolvingAgainstBaseURL: false) {
            comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "xml", value: "1")]
            if let xmlURL = comps.url {
                var retry = request
                retry.url = xmlURL
                (data, response) = try await send(retry)
            }
        }
        let parser = CommunityAchievementsParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        if parser.achievements.isEmpty {
            if parser.parsedError?.lowercased().contains("private") == true { throw SteamAPIError.privateProfile }
            throw SteamAPIError.noAchievements
        }
        return (parser.achievements.filter { $0.isUnlocked }.count, parser.achievements.count)
    }
    
    // Fetch achievements for a game and merge with public global rarity
    public func fetchAchievementsForGame(
        target: String,
        vanitySlug: String? = nil,
        steamId64: String? = nil,
        appId: Int,
        cookies: [HTTPCookie]? = nil,
        catalog: AchievementCatalog? = nil
    ) async throws -> (achievements: [Achievement], gameName: String?, gameLogo: String?) {
        let info = SteamTargetInfo(input: target)
        let resolvedVanity = vanitySlug ?? info.vanitySlug
        let resolvedId = steamId64 ?? info.steamId64
        
        var candidateUrls: [String] = []
        if let v = resolvedVanity, !v.isEmpty {
            candidateUrls.append("https://steamcommunity.com/id/\(v)/stats/\(appId)/?xml=1")
        }
        if let id = resolvedId, !id.isEmpty {
            candidateUrls.append("https://steamcommunity.com/profiles/\(id)/stats/\(appId)/?xml=1")
        }
        if candidateUrls.isEmpty {
            candidateUrls.append("https://steamcommunity.com/id/\(info.rawInput)/stats/\(appId)/?xml=1")
            candidateUrls.append("https://steamcommunity.com/profiles/\(info.rawInput)/stats/\(appId)/?xml=1")
        }
        
        var lastError: Error? = nil
        var sawNoStats = false
        
        for urlStr in candidateUrls {
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.setValue(HTTPClient.browserUserAgent, forHTTPHeaderField: "User-Agent")
            if let cookies = cookies, !cookies.isEmpty {
                request.setValue(buildCookieHeader(from: cookies), forHTTPHeaderField: "Cookie")
            }
            
            do {
                var (data, response) = try await send(request)
                // Games with a custom stats name (e.g. /stats/440 -> /stats/TF2) redirect and Steam drops
                // "?xml=1", which returns an HTML page. Re-request the redirect target as XML.
                if let finalURL = response.url, finalURL.query?.contains("xml=1") != true,
                   var comps = URLComponents(url: finalURL, resolvingAgainstBaseURL: false) {
                    comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "xml", value: "1")]
                    if let xmlURL = comps.url {
                        var retry = request
                        retry.url = xmlURL
                        (data, response) = try await send(retry)
                    }
                }
                let parser = CommunityAchievementsParser()
                let xmlParser = XMLParser(data: data)
                xmlParser.delegate = parser
                xmlParser.parse()
                
                if !parser.achievements.isEmpty || parser.parsedGameName != nil {
                    let rows = parser.achievements.map { item in
                        PlayerAchievementRow(
                            apiName: item.apiName,
                            name: item.name,
                            description: item.desc,
                            iconUrl: item.iconClosed,
                            grayIconUrl: item.iconOpen,
                            isUnlocked: item.isUnlocked,
                            unlockTime: item.timestamp.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                        )
                    }
                    var resolved = catalog
                    if resolved == nil || resolved?.isEmpty == true {
                        resolved = try? await SteamAPIService.shared.fetchCatalog(appId: appId)
                    }
                    if (resolved == nil || resolved?.isEmpty == true) && !rows.isEmpty {
                        // Public catalog unavailable: at least attach rarity from the keyless percentages.
                        let rarity = await SteamAPIService.shared.fetchGlobalPercentages(appId: appId)
                        resolved = AchievementCatalog(entries: rows.map {
                            CatalogEntry(apiName: $0.apiName, displayName: $0.name ?? $0.apiName, description: $0.description ?? "",
                                         iconUrl: $0.iconUrl, grayIconUrl: $0.grayIconUrl, isHidden: false,
                                         percent: rarity[$0.apiName], groupId: 0, isArchived: false)
                        }, groups: [])
                    }
                    let list = AchievementMerger.merge(rows: rows, catalog: resolved, appId: appId, gameName: parser.parsedGameName)
                    return (list, parser.parsedGameName, parser.parsedGameLogo)
                }
                
                if let message = parser.parsedError?.lowercased() {
                    if message.contains("private") {
                        lastError = SteamAPIError.privateProfile
                    } else {
                        // Steam answered but the game has no stats/achievements for this profile.
                        sawNoStats = true
                    }
                } else {
                    switch Self.classifyHTMLReply(data) {
                    case .noStatsForPlayer:
                        // For a game the player owns but has no stats for, Steam answers with the profile's HTML
                        // page instead of XML. That means "nothing unlocked", not a failure.
                        sawNoStats = true
                    case .profileUnavailable:
                        lastError = SteamAPIError.privateProfile
                    case .notHTML:
                        lastError = SteamAPIError.invalidResponse
                    }
                }
            } catch {
                if error is CancellationError { throw error }
                if case SteamAPIError.rateLimited = error { throw error }
                lastError = error
            }
        }
        
        if let lastError = lastError, !sawNoStats {
            throw lastError
        }
        return ([], nil, nil)
    }
}

private struct CommunityRgGame: Codable {
    let appid: Int
    let name: String
    let hours_forever: String
    let logo: String
}

// XML Parsers

private final class CommunityProfileParser: NSObject, XMLParserDelegate {
    var steamId = ""
    var personaName = ""
    var avatarFull = ""
    var onlineState = ""
    var stateMessage = ""
    var privacyState = ""
    var customURL = ""
    var mostPlayedGames: [(appId: Int, name: String, hours: Double, logo: String)] = []
    var inGameGameName = ""
    var inGameAppId: Int?
    
    private var insideGroup = false
    private var insideMostPlayedGame = false
    private var insideInGameInfo = false
    private var currentElement = ""
    private var currentText = ""
    
    private var curAppId: Int?
    private var curName = ""
    private var curHours = 0.0
    private var curLogo = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "groups" || elementName == "group" {
            insideGroup = true
        } else if elementName == "mostPlayedGame" {
            insideMostPlayedGame = true
            curAppId = nil
            curName = ""
            curHours = 0.0
            curLogo = ""
        } else if elementName == "inGameInfo" {
            insideInGameInfo = true
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let str = String(data: CDATABlock, encoding: .utf8) {
            currentText += str
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let val = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if insideInGameInfo {
            switch elementName {
            case "gameName":
                inGameGameName = val
            case "gameLink":
                if let idStr = val.components(separatedBy: "/app/").last?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                   let id = Int(idStr) {
                    inGameAppId = id
                }
            case "inGameInfo":
                insideInGameInfo = false
            default: break
            }
            return
        }
        
        if elementName == "group" || elementName == "groups" {
            insideGroup = false
            return
        }
        
        if insideMostPlayedGame {
            switch elementName {
            case "gameName":
                curName = val
            case "gameLink":
                if let idStr = val.components(separatedBy: "/app/").last?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                   let id = Int(idStr) {
                    curAppId = id
                }
            case "hoursOnRecord":
                curHours = Double(val.replacingOccurrences(of: ",", with: "")) ?? 0.0
            case "gameLogo":
                curLogo = val
            case "mostPlayedGame":
                if let id = curAppId, !curName.isEmpty {
                    mostPlayedGames.append((id, curName, curHours, curLogo))
                }
                insideMostPlayedGame = false
            default: break
            }
            return
        }
        
        if !insideGroup {
            switch elementName {
            case "steamID64":
                steamId = val
            case "steamID":
                if personaName.isEmpty { personaName = val }
            case "avatarFull":
                if avatarFull.isEmpty { avatarFull = val }
            case "avatarMedium":
                if avatarFull.isEmpty { avatarFull = val }
            case "avatarIcon":
                if avatarFull.isEmpty { avatarFull = val }
            case "onlineState":
                onlineState = val
            case "stateMessage":
                stateMessage = val
            case "privacyState":
                privacyState = val
            case "customURL":
                customURL = val
            default:
                break
            }
        }
    }
}

private final class CommunityAchievementsParser: NSObject, XMLParserDelegate {
    var achievements: [(apiName: String, name: String, desc: String, isUnlocked: Bool, iconClosed: String?, iconOpen: String?, timestamp: Double?)] = []
    var parsedGameName: String?
    var parsedGameLogo: String?
    var parsedError: String?
    
    private var currentElement = ""
    private var currentText = ""
    private var currentClosed: Bool = false
    private var currentApiName: String = ""
    private var currentName: String = ""
    private var currentDesc: String = ""
    private var currentIconClosed: String?
    private var currentIconOpen: String?
    private var currentTimestamp: Double?
    private var insideGame = false
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "game" {
            insideGame = true
        } else if elementName == "achievement" {
            currentClosed = attributeDict["closed"] == "1"
            currentApiName = ""
            currentName = ""
            currentDesc = ""
            currentIconClosed = nil
            currentIconOpen = nil
            currentTimestamp = nil
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let str = String(data: CDATABlock, encoding: .utf8) {
            currentText += str
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let val = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if insideGame {
            switch elementName {
            case "gameName":
                parsedGameName = val
            case "gameLogo":
                parsedGameLogo = val
            case "game":
                insideGame = false
            default:
                break
            }
            return
        }
        
        switch elementName {
        case "error":
            if !val.isEmpty { parsedError = val }
        case "apiname":
            currentApiName = val
        case "name":
            currentName = val
        case "description":
            currentDesc = val
        case "iconClosed":
            currentIconClosed = val
        case "iconOpen":
            currentIconOpen = val
        case "unlockTimestamp":
            currentTimestamp = Double(val)
        case "achievement":
            if !currentApiName.isEmpty || !currentName.isEmpty {
                let api = currentApiName.isEmpty ? currentName : currentApiName
                let name = currentName.isEmpty ? currentApiName : currentName
                achievements.append((api, name, currentDesc, currentClosed, currentIconClosed, currentIconOpen, currentTimestamp))
            }
        default:
            break
        }
    }
}
