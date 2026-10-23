import Foundation

public enum SteamPrivacyHelp {
    public static let settingsURL = URL(string: "https://steamcommunity.com/my/edit/settings")!
    public static let steps = "In Steam open your Profile > Edit Profile > Privacy Settings, then set \"My profile\" and \"Game details\" to Public and untick \"Always keep my total playtime private\". Changes can take a few minutes to apply."
}

public enum SteamAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case networkError(String)
    case playerNotFound
    case vanityURLNotFound
    case privateProfile
    case noAchievements
    case rateLimited
    case accessDenied
    case httpStatus(Int)
    case custom(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Steam API URL."
        case .invalidResponse:
            return "Unexpected response format from Steam servers."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .playerNotFound:
            return "Steam profile not found. Please verify your SteamID64."
        case .vanityURLNotFound:
            return "Custom Steam URL could not be resolved."
        case .privateProfile:
            return "This Steam profile or its game details are private. \(SteamPrivacyHelp.steps)"
        case .noAchievements:
            return "No achievements found for this game."
        case .rateLimited:
            return "Steam is rate limiting requests. Wait a minute and retry."
        case .accessDenied:
            return "Steam refused the request: the API key is invalid, or the data is private."
        case .httpStatus(let code):
            return "Steam returned an unexpected HTTP \(code) response."
        case .custom(let msg):
            return msg
        }
    }
}

public final class SteamAPIService {
    public static let shared = SteamAPIService()
    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? HTTPClient.session
    }

    /// GET a Steam Web API URL and decode the JSON object, mapping HTTP failures to typed errors.
    private func getJSON(_ url: URL) async throws -> [String: Any] {
        let (data, http) = try await HTTPClient.data(from: url, session: session)
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw SteamAPIError.accessDenied
        default:
            throw SteamAPIError.httpStatus(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SteamAPIError.invalidResponse
        }
        return json
    }

    private func apiURL(_ path: String, _ items: [String: String]) -> URL? {
        var comps = URLComponents(string: "https://api.steampowered.com/\(path)")
        comps?.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps?.url
    }

    private func authedURL(_ path: String, _ auth: SteamAuth, _ items: [String: String]) -> URL? {
        guard !auth.queryItems.isEmpty else { return nil }
        return apiURL(path, auth.queryItems.merging(items) { $1 })
    }
    
    // Resolve custom URL name (e.g. "gabelogannewell") to 64-bit numeric Steam ID
    public func resolveVanityURL(_ vanity: String, apiKey: String) async throws -> String {
        let trimmed = vanity.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.allSatisfy({ $0.isNumber }) && trimmed.count >= 17 {
            return trimmed
        }

        // Extract vanity slug if full profile URL was provided
        var slug = trimmed
        if slug.contains("steamcommunity.com/id/") {
            slug = slug.components(separatedBy: "steamcommunity.com/id/").last?
                .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? trimmed
        } else if slug.contains("steamcommunity.com/profiles/") {
            let id = slug.components(separatedBy: "steamcommunity.com/profiles/").last?
                .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? trimmed
            if id.allSatisfy({ $0.isNumber }) {
                return id
            }
        }

        guard let url = apiURL("ISteamUser/ResolveVanityURL/v0001/", ["key": apiKey, "vanityurl": slug]) else {
            throw SteamAPIError.invalidURL
        }

        let json = try await getJSON(url)
        guard let response = json["response"] as? [String: Any] else {
            throw SteamAPIError.invalidResponse
        }

        if let success = response["success"] as? Int, success == 1,
           let steamId = response["steamid"] as? String {
            return steamId
        }

        throw SteamAPIError.vanityURLNotFound
    }

    private func makePlayer(_ first: [String: Any], fallbackId: String) -> SteamPlayer {
        let name = first["personaname"] as? String ?? "Steam User"
        let avatar = first["avatarfull"] as? String ?? first["avatarmedium"] as? String
        let profileUrl = first["profileurl"] as? String
        let state = first["personastate"] as? Int ?? 0
        let gameIdStr = first["gameid"] as? String
        let gameId = gameIdStr.flatMap { Int($0) }
        let gameName = first["gameextrainfo"] as? String

        return SteamPlayer(
            steamId: first["steamid"] as? String ?? fallbackId,
            personaName: name,
            avatarUrl: avatar,
            profileUrl: profileUrl,
            personaState: state,
            currentGameId: gameId,
            currentGameName: gameName
        )
    }

    // Fetch player summary (name, avatar, online status)
    public func fetchPlayerSummary(steamId: String, apiKey: String) async throws -> SteamPlayer {
        try await fetchPlayerSummary(steamId: steamId, auth: SteamAuth(apiKey: apiKey))
    }
    
    public func fetchPlayerSummary(steamId: String, auth: SteamAuth) async throws -> SteamPlayer {
        guard let url = authedURL("ISteamUser/GetPlayerSummaries/v0002/", auth, ["steamids": steamId]) else {
            throw SteamAPIError.accessDenied
        }

        let json = try await getJSON(url)
        guard let response = json["response"] as? [String: Any],
              let players = response["players"] as? [[String: Any]],
              let first = players.first else {
            throw SteamAPIError.playerNotFound
        }
        return makePlayer(first, fallbackId: steamId)
    }

    // Fetch summaries for many users (Steam allows 100 ids per call)
    public func fetchPlayerSummaries(steamIds: [String], apiKey: String) async throws -> [SteamPlayer] {
        try await fetchPlayerSummaries(steamIds: steamIds, auth: SteamAuth(apiKey: apiKey))
    }
    
    public func fetchPlayerSummaries(steamIds: [String], auth: SteamAuth) async throws -> [SteamPlayer] {
        var result: [SteamPlayer] = []
        var index = 0
        while index < steamIds.count {
            let chunk = Array(steamIds[index..<min(index + 100, steamIds.count)])
            index += 100
            guard let url = authedURL("ISteamUser/GetPlayerSummaries/v0002/", auth, ["steamids": chunk.joined(separator: ",")]) else {
                throw SteamAPIError.accessDenied
            }
            let json = try await getJSON(url)
            guard let response = json["response"] as? [String: Any],
                  let players = response["players"] as? [[String: Any]] else {
                throw SteamAPIError.invalidResponse
            }
            result.append(contentsOf: players.map { makePlayer($0, fallbackId: "") })
        }
        return result
    }

    // Fetch the SteamIDs of the user's friends. Fails with accessDenied if the friends list is private.
    public func fetchFriendIds(steamId: String, apiKey: String) async throws -> [String] {
        try await fetchFriendIds(steamId: steamId, auth: SteamAuth(apiKey: apiKey))
    }
    
    public func fetchFriendIds(steamId: String, auth: SteamAuth) async throws -> [String] {
        // The older GetFriendList needs an API key. The sign-in token works with the friends service instead.
        if auth.apiKey == nil {
            guard let url = authedURL("IFriendsListService/GetFriendsList/v1/", auth, [:]) else { throw SteamAPIError.accessDenied }
            let json = try await getJSON(url)
            guard let list = (json["response"] as? [String: Any])?["friendslist"] as? [String: Any] else {
                throw SteamAPIError.invalidResponse
            }
            let friends = list["friends"] as? [[String: Any]] ?? []
            // efriendrelationship 3 = mutual friends (others are pending requests, blocked users, ...)
            return friends.compactMap { entry in
                let relationship = (entry["efriendrelationship"] as? NSNumber)?.intValue ?? 3
                guard relationship == 3 else { return nil }
                return entry["ulfriendid"] as? String
            }
        }
        guard let url = authedURL("ISteamUser/GetFriendList/v0001/", auth, ["steamid": steamId, "relationship": "friend"]) else {
            throw SteamAPIError.accessDenied
        }
        let json = try await getJSON(url)
        guard let list = json["friendslist"] as? [String: Any],
              let friends = list["friends"] as? [[String: Any]] else {
            throw SteamAPIError.invalidResponse
        }
        return friends.compactMap { $0["steamid"] as? String }
    }

    // Fetch owned games list with names and playtimes
    public func fetchOwnedGames(steamId: String, apiKey: String) async throws -> [SteamGame] {
        try await fetchOwnedGames(steamId: steamId, auth: SteamAuth(apiKey: apiKey))
    }
    
    /// Works with an API key or with the access token of a signed-in session.
    public func fetchOwnedGames(steamId: String, auth: SteamAuth) async throws -> [SteamGame] {
        guard let url = authedURL("IPlayerService/GetOwnedGames/v0001/", auth, [
            "steamid": steamId,
            "include_appinfo": "1",
            "include_played_free_games": "1",
            "format": "json"
        ]) else {
            throw SteamAPIError.accessDenied
        }

        let json = try await getJSON(url)
        guard let response = json["response"] as? [String: Any] else {
            throw SteamAPIError.invalidResponse
        }

        guard let gamesArray = response["games"] as? [[String: Any]] else {
            // Might be private profile
            if response["game_count"] == nil {
                throw SteamAPIError.privateProfile
            }
            return []
        }

        return gamesArray.compactMap { item in
            guard let appId = item["appid"] as? Int,
                  let name = item["name"] as? String else {
                return nil
            }
            let playtime = item["playtime_forever"] as? Int ?? 0
            let iconHash = item["img_icon_url"] as? String
            return SteamGame(
                appId: appId,
                name: name,
                playtimeMinutes: playtime,
                iconHash: iconHash,
                achievements: [],
                hasAchievementsLoaded: false
            )
        }.sorted { $0.playtimeMinutes > $1.playtimeMinutes }
    }

    private func fetchGlobalPercentagesThrowing(appId: Int) async throws -> [String: Double] {
        guard let url = apiURL("ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/", ["gameid": String(appId)]) else {
            throw SteamAPIError.invalidURL
        }
        let json = try await getJSON(url)
        guard let root = json["achievementpercentages"] as? [String: Any],
              let list = root["achievements"] as? [[String: Any]] else {
            return [:]
        }
        
        var map: [String: Double] = [:]
        for item in list {
            guard let name = item["name"] as? String else { continue }
            if let percent = item["percent"] as? Double {
                map[name] = percent
            } else if let str = item["percent"] as? String, let percent = Double(str) {
                map[name] = percent
            }
        }
        return map
    }
    
    // Global achievement percentages (rarity), cached on disk. Rarity is optional decoration, so a
    // failure falls back to stale cached values or an empty map instead of failing the whole game.
    public func fetchGlobalPercentages(appId: Int) async -> [String: Double] {
        let cached = MetadataCache.rarity(appId: appId)
        if let cached = cached, cached.fresh { return cached.value }
        if let fetched = try? await fetchGlobalPercentagesThrowing(appId: appId) {
            MetadataCache.storeRarity(fetched, appId: appId)
            return fetched
        }
        return cached?.value ?? [:]
    }
    
    // Schema (display names, descriptions, icon URLs, hidden flags), cached on disk.
    // Throws on network/HTTP failure (when nothing usable is cached) so a game is retried
    // instead of being stored with raw API names.
    public func fetchGameSchema(appId: Int, apiKey: String) async throws -> [String: AchievementSchemaEntry] {
        let cached = MetadataCache.schema(appId: appId)
        if let cached = cached, cached.fresh { return cached.value }
        do {
            let fetched = try await fetchGameSchemaFromNetwork(appId: appId, apiKey: apiKey)
            MetadataCache.storeSchema(fetched, appId: appId)
            return fetched
        } catch {
            if let stale = cached, !(error is CancellationError) { return stale.value }
            throw error
        }
    }
    
    private func fetchGameSchemaFromNetwork(appId: Int, apiKey: String) async throws -> [String: AchievementSchemaEntry] {
        guard let url = apiURL("ISteamUserStats/GetSchemaForGame/v0002/", ["key": apiKey, "appid": String(appId)]) else {
            throw SteamAPIError.invalidURL
        }
        
        let json = try await getJSON(url)
        guard let game = json["game"] as? [String: Any],
              let stats = game["availableGameStats"] as? [String: Any],
              let achievements = stats["achievements"] as? [[String: Any]] else {
            return [:]
        }
        
        var result: [String: AchievementSchemaEntry] = [:]
        for item in achievements {
            guard let name = item["name"] as? String else { continue }
            result[name] = AchievementSchemaEntry(
                displayName: item["displayName"] as? String ?? name,
                description: item["description"] as? String ?? "",
                icon: item["icon"] as? String,
                grayIcon: item["icongray"] as? String,
                isHidden: (item["hidden"] as? Int ?? 0) == 1
            )
        }
        return result
    }
    
    /// Steam's public achievement catalog (no API key): names, icons, rarity and Achievement Sets
    /// (groups, DLC sets, archived flags). Cached on disk; stale cache is used if Steam is unreachable.
    /// Returns an empty catalog for games without achievements.
    public func fetchCatalog(appId: Int, force: Bool = false) async throws -> AchievementCatalog {
        let cached = MetadataCache.catalog(appId: appId)
        if !force, let cached = cached, cached.fresh { return cached.value }
        do {
            guard let url = apiURL("IPlayerService/GetGameAchievements/v1/", ["appid": String(appId), "language": "english"]) else {
                throw SteamAPIError.invalidURL
            }
            let json = try await getJSON(url)
            guard let response = json["response"] as? [String: Any] else {
                throw SteamAPIError.invalidResponse
            }
            let catalog = AchievementCatalog.parse(response: response, appId: appId)
            MetadataCache.storeCatalog(catalog, appId: appId)
            return catalog
        } catch {
            if let stale = cached, !(error is CancellationError) { return stale.value }
            throw error
        }
    }
    
    /// Catalog for older flows: if the public catalog is unavailable, build one from the keyed schema + rarity.
    private func legacyCatalog(appId: Int, apiKey: String) async throws -> AchievementCatalog {
        async let schemaTask = fetchGameSchema(appId: appId, apiKey: apiKey)
        async let rarityTask = fetchGlobalPercentages(appId: appId)
        let schema = try await schemaTask
        let rarity = await rarityTask
        let entries = schema.map { (name, s) in
            CatalogEntry(apiName: name, displayName: s.displayName, description: s.description, iconUrl: s.icon,
                         grayIconUrl: s.grayIcon, isHidden: s.isHidden, percent: rarity[name], groupId: 0, isArchived: false)
        }.sorted { $0.apiName < $1.apiName }
        return AchievementCatalog(entries: entries, groups: [])
    }
    
    /// A player's achievements for one game from `IPlayerService/GetUserAchievements`, the endpoint Steam's new
    /// achievements page uses. It needs no key for a public profile; the sign-in token or key (if given) is attached so
    /// the owner can also read private data. An empty list means nothing is unlocked (or the data is private).
    public func fetchUserAchievements(steamId: String, appId: Int, auth: SteamAuth? = nil) async throws -> [UserAchievementRow] {
        try await fetchUserAchievementsDetailed(steamId: steamId, appId: appId, auth: auth).rows
    }
    
    /// Same call, also returning the achievement sets Steam lists for this player (their DLC access).
    public func fetchUserAchievementsDetailed(steamId: String, appId: Int, auth: SteamAuth? = nil) async throws -> UserAchievementsResult {
        var items = ["steamid": steamId, "appid": String(appId)]
        if let auth = auth { items.merge(auth.queryItems) { $1 } }
        guard let url = apiURL("IPlayerService/GetUserAchievements/v1/", items) else { throw SteamAPIError.invalidURL }
        let json = try await getJSON(url)
        guard let response = json["response"] as? [String: Any] else { throw SteamAPIError.invalidResponse }
        let rows = (response["achievements"] as? [[String: Any]] ?? []).compactMap { row -> UserAchievementRow? in
            guard let key = (row["internal_key"] as? NSNumber)?.intValue else { return nil }
            let unlocked = (row["unlocked"] as? Bool) ?? ((row["unlocked"] as? NSNumber)?.boolValue ?? false)
            let time = (row["unlock_time"] as? NSNumber)?.doubleValue ?? 0
            return UserAchievementRow(internalKey: key, unlocked: unlocked, unlockTime: time > 0 ? Date(timeIntervalSince1970: time) : nil)
        }
        var groupIds: Set<Int>?
        if let groups = response["groups"] as? [[String: Any]] {
            groupIds = Set(groups.compactMap { ($0["groupid"] as? NSNumber)?.intValue })
        }
        return UserAchievementsResult(rows: rows, accessibleGroupIds: groupIds)
    }
    
    /// Unlocked counts for many games in a few requests (Steam's own achievements page uses this).
    /// Returns nil when unavailable for any reason; callers must then fall back to per-game requests.
    public func fetchAchievementProgress(steamId: String, appIds: [Int], auth: SteamAuth) async -> [Int: (unlocked: Int, total: Int)]? {
        guard !auth.queryItems.isEmpty, !appIds.isEmpty else { return nil }
        let chunks = stride(from: 0, to: appIds.count, by: 100).map { Array(appIds[$0..<min($0 + 100, appIds.count)]) }
        var result: [Int: (unlocked: Int, total: Int)] = [:]
        var anyFailed = false
        
        // The chunks are independent: run them side by side instead of one after another.
        await withTaskGroup(of: [Int: (unlocked: Int, total: Int)]?.self) { group in
            var iterator = chunks.makeIterator()
            func next() { if let chunk = iterator.next() { group.addTask { await self.fetchProgressChunk(steamId: steamId, appIds: chunk, auth: auth) } } }
            for _ in 0..<4 { next() }
            while let part = await group.next() {
                if let part = part { result.merge(part) { $1 } } else { anyFailed = true }
                next()
            }
        }
        // A partial answer is still useful (games it covers); callers treat missing games as "unknown".
        _ = anyFailed
        return result.isEmpty ? nil : result
    }
    
    private func fetchProgressChunk(steamId: String, appIds: [Int], auth: SteamAuth) async -> [Int: (unlocked: Int, total: Int)]? {
        guard var comps = URLComponents(string: "https://api.steampowered.com/IPlayerService/GetAchievementsProgress/v1/") else { return nil }
        comps.queryItems = auth.queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { return nil }
        
        let input: [String: Any] = ["steamid": steamId, "appids": appIds, "language": "english"]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: input),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "input_json", value: jsonString)]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        
        guard let (data, http) = try? await HTTPClient.data(for: request, session: session, maxAttempts: 2),
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let rows = response["achievement_progress"] as? [[String: Any]] else { return nil }
        var part: [Int: (unlocked: Int, total: Int)] = [:]
        for row in rows {
            guard let appId = (row["appid"] as? NSNumber)?.intValue else { continue }
            part[appId] = ((row["unlocked"] as? NSNumber)?.intValue ?? 0, (row["total"] as? NSNumber)?.intValue ?? 0)
        }
        return part
    }
    
    /// Finds an app id from a title with the public store search (no key). Used for Now Playing when the profile page
    /// names a game but gives no id, and the game isn't in the library.
    public func searchAppId(name: String) async -> Int? {
        var comps = URLComponents(string: "https://store.steampowered.com/api/storesearch/")
        comps?.queryItems = [URLQueryItem(name: "term", value: name), URLQueryItem(name: "cc", value: "us"), URLQueryItem(name: "l", value: "english")]
        guard let url = comps?.url,
              let (data, http) = try? await HTTPClient.data(for: URLRequest(url: url), session: session, maxAttempts: 2),
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return nil }
        let apps = items.filter { ($0["type"] as? String ?? "app") == "app" }
        let exact = apps.first { GameNameMatcher.matches(($0["name"] as? String) ?? "", name) }
        return ((exact ?? nil)?["id"] as? NSNumber)?.intValue
    }
    
    // Public store lookup for the real name of an app (used instead of "Steam Game #123" placeholders).
    public func fetchAppName(appId: Int) async -> String? {
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appId)&filters=basic"),
              let (data, http) = try? await HTTPClient.data(for: URLRequest(url: url), session: session, maxAttempts: 2),
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = json[String(appId)] as? [String: Any],
              entry["success"] as? Bool == true,
              let info = entry["data"] as? [String: Any],
              let name = info["name"] as? String, !name.isEmpty else { return nil }
        return name
    }
    
    /// Raw GetPlayerAchievements call. Steam reports "no stats" / "not public" with 400/403 and a JSON body,
    /// so the body is inspected before the status code is turned into a generic error.
    private func fetchPlayerAchievementRows(appId: Int, steamId: String, auth: SteamAuth) async throws -> [[String: Any]] {
        guard let url = authedURL("ISteamUserStats/GetPlayerAchievements/v0001/", auth, [
            "appid": String(appId),
            "steamid": steamId
        ]) else {
            throw SteamAPIError.accessDenied
        }

        let (data, http) = try await HTTPClient.data(from: url, session: session)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let playerstats = json?["playerstats"] as? [String: Any]

        if let playerstats = playerstats, let success = playerstats["success"] as? Bool, !success {
            let message = (playerstats["error"] as? String ?? "").lowercased()
            if message.contains("no stats") || message.contains("not have stats") {
                throw SteamAPIError.noAchievements
            }
            if message.contains("not public") || message.contains("private") {
                throw SteamAPIError.privateProfile
            }
            if !message.isEmpty {
                throw SteamAPIError.custom("Steam: \(playerstats["error"] as? String ?? message)")
            }
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw SteamAPIError.accessDenied
        case 400:
            throw SteamAPIError.noAchievements
        default:
            throw SteamAPIError.httpStatus(http.statusCode)
        }

        guard let playerstats = playerstats else {
            throw SteamAPIError.invalidResponse
        }
        // A game with stats but no achievements has no "achievements" key.
        return playerstats["achievements"] as? [[String: Any]] ?? []
    }

    /// Lightweight unlocked/total count for a game (used by Friend Compare).
    public func fetchAchievementCounts(appId: Int, steamId: String, apiKey: String) async throws -> (unlocked: Int, total: Int) {
        let rows = try await fetchPlayerAchievementRows(appId: appId, steamId: steamId, auth: SteamAuth(apiKey: apiKey))
        let unlocked = rows.filter { ($0["achieved"] as? Int ?? 0) == 1 }.count
        return (unlocked, rows.count)
    }

    // Fetch player achievement status for a game and merge it with the catalog (names, icons, rarity, sets).
    // Pass the catalog if you already have it; otherwise it is fetched (public endpoint, cached).
    public func fetchAchievementsForGame(
        appId: Int,
        steamId: String,
        apiKey: String,
        catalog: AchievementCatalog? = nil
    ) async throws -> [Achievement] {
        try await fetchAchievementsForGame(appId: appId, steamId: steamId, auth: SteamAuth(apiKey: apiKey), catalog: catalog)
    }
    
    /// Works with an API key, or with the sign-in token (if Steam accepts it for this method; callers fall back).
    public func fetchAchievementsForGame(
        appId: Int,
        steamId: String,
        auth: SteamAuth,
        catalog: AchievementCatalog? = nil
    ) async throws -> [Achievement] {
        let achArray = try await fetchPlayerAchievementRows(appId: appId, steamId: steamId, auth: auth)
        if achArray.isEmpty { return [] }
        
        var resolved = catalog
        if resolved == nil || resolved?.isEmpty == true {
            resolved = try? await fetchCatalog(appId: appId)
        }
        if resolved == nil || resolved?.isEmpty == true {
            // Public catalog unavailable: fall back to the keyed schema + rarity (throws if even that fails,
            // so the game is retried instead of being cached with raw API names).
            guard let key = auth.apiKey else { throw SteamAPIError.invalidResponse }
            resolved = try await legacyCatalog(appId: appId, apiKey: key)
        }
        
        let rows = achArray.map { item -> PlayerAchievementRow in
            let unlockSeconds = (item["unlocktime"] as? NSNumber)?.doubleValue ?? 0
            let achieved = (item["achieved"] as? Int ?? 0) == 1
            return PlayerAchievementRow(
                apiName: item["apiname"] as? String ?? "UNKNOWN",
                isUnlocked: achieved,
                unlockTime: (achieved && unlockSeconds > 0) ? Date(timeIntervalSince1970: unlockSeconds) : nil
            )
        }
        return AchievementMerger.merge(rows: rows, catalog: resolved, appId: appId)
    }
}
