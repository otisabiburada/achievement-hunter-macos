import Foundation

var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
    if cond() { print("  ok   \(msg)") } else { print("  FAIL \(msg) (line \(line))"); failures += 1 }
}

// ---- URLProtocol stub
final class Stub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))?
    static var requests: [URL] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Stub.requests.append(request.url!)
        let (code, headers, body) = Stub.handler!(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let cfg = URLSessionConfiguration.ephemeral
cfg.protocolClasses = [Stub.self]
let session = URLSession(configuration: cfg)

func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }

func ach(_ n: String, _ unlocked: Bool, t: Date? = nil) -> Achievement {
    Achievement(apiName: n, displayName: n, descriptionText: "d", isUnlocked: unlocked, unlockTimestamp: t)
}

func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("ah-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func live0AvatarIsPicture(_ url: String?) -> Bool {
    guard let url = url else { return false }
    return url.contains("avatars") && !url.contains("/items/")
}

func run() async {
    // ===== LibraryStore
    print("LibraryStore")
    do {
        let root = tmp()
        let store = LibraryStore(root: root)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        var g1 = SteamGame(appId: 10, name: "A", playtimeMinutes: 90, achievements: [ach("x", true, t: when)], hasAchievementsLoaded: true, lastFetchedAt: when)
        g1.loadError = nil
        let g2 = SteamGame(appId: 20, name: "B", playtimeMinutes: 0, playtimeIsKnown: false)
        let idx = LibraryIndex(schemaVersion: LibraryStore.currentVersion, player: SteamPlayer(steamId: "7656", personaName: "me"), lastSyncedAt: when, stubs: [GameStub(g1), GameStub(g2)])
        store.save(index: idx, dirty: [g1, g2], prune: true); store.flush()
        let loaded = LibraryStore(root: root).load()
        check(loaded?.games.count == 2, "roundtrip game count")
        let l1 = loaded?.games.first { $0.appId == 10 }
        check(l1?.achievements.first?.unlockTimestamp == when, "unlock date preserved")
        check(l1?.hasAchievementsLoaded == true && l1?.lastFetchedAt == when, "flags preserved")
        check(loaded?.games.first { $0.appId == 20 }?.playtimeIsKnown == false, "playtimeIsKnown preserved")
        check(loaded?.player?.personaName == "me" && loaded?.lastSyncedAt == when, "player + lastSyncedAt")
        
        // only dirty games rewritten
        let f10 = root.appendingPathComponent("library/games/10.json")
        try! FileManager.default.removeItem(at: f10)
        store.save(index: idx, dirty: [g2], prune: false); store.flush()
        check(!FileManager.default.fileExists(atPath: f10.path), "clean game not rewritten")
        let l2 = LibraryStore(root: root).load()
        check(l2?.games.first { $0.appId == 10 }?.hasAchievementsLoaded == false && l2?.games.count == 2, "unreadable game file falls back to stub (unloaded)")
        
        // prune
        let idx2 = LibraryIndex(schemaVersion: LibraryStore.currentVersion, player: nil, lastSyncedAt: nil, stubs: [GameStub(g2)])
        store.save(index: idx2, dirty: [], prune: true); store.flush()
        check(LibraryStore(root: root).load()?.games.count == 1, "prune drops removed games")
    }
    do { // legacy migration, written exactly like the old app did
        struct LegacyV1: Codable { let player: SteamPlayer?; let games: [SteamGame]; let cachedAt: Date }
        let root = tmp()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = LegacyV1(player: SteamPlayer(steamId: "1", personaName: "old"),
                              games: [SteamGame(appId: 5, name: "Old", playtimeMinutes: 5, achievements: [ach("a", true, t: when)], hasAchievementsLoaded: true)],
                              cachedAt: when)
        try! JSONEncoder().encode(legacy).write(to: root.appendingPathComponent("library_cache.json"))
        let loaded = LibraryStore(root: root).load()
        check(loaded?.games.count == 1 && loaded?.player?.personaName == "old", "legacy v1 migrated")
        check(loaded?.games.first?.achievements.first?.unlockTimestamp == when, "legacy default-format dates read correctly")
        check(loaded?.lastSyncedAt == when, "legacy cachedAt becomes lastSyncedAt")
        check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("library_cache.json").path), "legacy file moved")
        check(FileManager.default.fileExists(atPath: root.appendingPathComponent("library_cache.v1.bak").path), "legacy backup kept")
        check(LibraryStore(root: root).load()?.games.count == 1, "migrated library loads again")
    }
    do { // newer schema is never destroyed or misread
        let root = tmp()
        let store = LibraryStore(root: root)
        let idx = LibraryIndex(schemaVersion: 99, player: nil, lastSyncedAt: nil, stubs: [])
        store.save(index: idx, dirty: [], prune: false); store.flush()
        check(LibraryStore(root: root).load() == nil, "future schema ignored")
        let kids = try! FileManager.default.contentsOfDirectory(atPath: root.path)
        check(kids.contains { $0.hasPrefix("library.unreadable-v99") }, "future-schema data quarantined, not deleted")
    }
    do { // corrupt legacy keeps a copy
        let root = tmp()
        try! Data("{not json".utf8).write(to: root.appendingPathComponent("library_cache.json"))
        check(LibraryStore(root: root).load() == nil, "corrupt legacy -> nil")
        check(FileManager.default.fileExists(atPath: root.appendingPathComponent("library_cache.unreadable.json").path), "corrupt legacy preserved aside")
    }
    
    // ===== HTTPClient
    print("HTTPClient")
    do {
        var n = 0
        Stub.handler = { _ in n += 1; return n < 3 ? (429, ["Retry-After": "0"], Data()) : (200, [:], Data("ok".utf8)) }
        let (d, r) = try! await HTTPClient.data(from: URL(string: "https://x.test/a")!, session: session)
        check(r.statusCode == 200 && String(data: d, encoding: .utf8) == "ok" && n == 3, "retries 429 then succeeds (\(n) calls)")
        n = 0
        Stub.handler = { _ in n += 1; return (429, ["Retry-After": "0"], Data()) }
        do { _ = try await HTTPClient.data(from: URL(string: "https://x.test/b")!, session: session); check(false, "should throw") }
        catch SteamAPIError.rateLimited { check(n == 4, "gives up with rateLimited after 4 attempts (\(n))") }
        catch { check(false, "wrong error \(error)") }
        n = 0
        Stub.handler = { _ in n += 1; return (404, [:], Data()) }
        let (_, r404) = try! await HTTPClient.data(from: URL(string: "https://x.test/c")!, session: session)
        check(r404.statusCode == 404 && n == 1, "404 returned without retry")
    }
    
    // ===== SteamAPIService
    print("SteamAPIService")
    let api = SteamAPIService(session: session)
    let base = 900_000_000 + Int.random(in: 0..<90_000_000)   // unlikely to collide with real app ids in the cache
    defer {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AchievementHunter/metadata")
        for i in 0..<5 { for k in ["schema", "rarity"] { try? FileManager.default.removeItem(at: caches.appendingPathComponent("\(base + i).\(k).json")) } }
    }
    do {
        Stub.handler = { _ in (400, [:], json(["playerstats": ["error": "Requested app has no stats", "success": false]])) }
        do { _ = try await api.fetchAchievementsForGame(appId: base, steamId: "1", apiKey: "k"); check(false, "should throw") }
        catch SteamAPIError.noAchievements { check(true, "400 'no stats' -> noAchievements") }
        catch { check(false, "wrong error \(error)") }
        
        Stub.handler = { _ in (403, [:], json(["playerstats": ["error": "Profile is not public", "success": false]])) }
        do { _ = try await api.fetchAchievementsForGame(appId: base, steamId: "1", apiKey: "k"); check(false, "should throw") }
        catch SteamAPIError.privateProfile { check(true, "'Profile is not public' -> privateProfile") }
        catch { check(false, "wrong error \(error)") }
        
        Stub.handler = { _ in (403, [:], Data("Forbidden".utf8)) }
        do { _ = try await api.fetchOwnedGames(steamId: "1", apiKey: "bad"); check(false, "should throw") }
        catch SteamAPIError.accessDenied { check(true, "403 -> accessDenied") }
        catch { check(false, "wrong error \(error)") }
        
        // full merge via the public catalog (sets, rarity) + caching
        let id = base + 1
        Stub.requests = []
        func catalogJSON() -> Data {
            json(["response": [
                "schema_version": 3, "schema_hash": 42,
                "groups": [
                    ["groupid": 0, "localized_name": "", "dlcappid": 0, "archived": false, "developeronly": false, "order": 0, "total_achievements": 2],
                    ["groupid": 1, "localized_name": "Expansion", "dlcappid": 777, "archived": false, "developeronly": false, "order": 1, "total_achievements": 1]],
                "achievements": [
                    ["internal_name": "A1", "localized_name": "First", "localized_desc": "d1", "icon": "i1.jpg", "icon_gray": "g1.jpg", "hidden": false, "player_percent_unlocked": "50.5", "groupid": 0, "archived": false],
                    ["internal_name": "A2", "localized_name": "Second", "localized_desc": "d2", "icon": "i2.jpg", "icon_gray": "g2.jpg", "hidden": true, "player_percent_unlocked": "1.5", "groupid": 0, "archived": false],
                    ["internal_name": "D1", "localized_name": "DLC One", "localized_desc": "dd", "icon": "i3.jpg", "icon_gray": "g3.jpg", "hidden": false, "player_percent_unlocked": "9.0", "groupid": 1, "archived": false]]]])
        }
        Stub.handler = { req in
            let u = req.url!.absoluteString
            if u.contains("GetPlayerAchievements") {
                return (200, [:], json(["playerstats": ["success": true, "achievements": [
                    ["apiname": "A1", "achieved": 1, "unlocktime": 1_700_000_000],
                    ["apiname": "A2", "achieved": 0, "unlocktime": 0]]]]))
            }
            if u.contains("GetGameAchievements") { return (200, [:], catalogJSON()) }
            return (500, [:], Data())
        }
        let first = try! await api.fetchAchievementsForGame(appId: id, steamId: "1", apiKey: "k")
        check(first.count == 3 && first[0].displayName == "First" && first[0].isUnlocked && first[1].isHidden, "merge catalog + unlock state")
        check(first[1].globalPercent == 1.5 && first[0].unlockTimestamp == Date(timeIntervalSince1970: 1_700_000_000), "rarity + unlock time")
        check(first[2].apiName == "D1" && first[2].groupId == 1 && !first[2].isUnlocked, "DLC achievement missing from player rows is added as locked, with its set")
        check(first[0].iconUrl == "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/\(id)/i1.jpg", "icon hash expanded to a URL")
        let callsFirst = Stub.requests.count
        _ = try! await api.fetchAchievementsForGame(appId: id, steamId: "1", apiKey: "k")
        let secondCalls = Stub.requests.count - callsFirst
        check(callsFirst == 2 && secondCalls == 1, "2nd sync of same game needs 1 request instead of 2 (first \(callsFirst), second \(secondCalls))")
        
        // catalog unavailable -> legacy schema + rarity fallback; if that also fails the game fails (and is retried)
        let id2 = base + 2
        Stub.handler = { req in
            let u = req.url!.absoluteString
            if u.contains("GetPlayerAchievements") { return (200, [:], json(["playerstats": ["success": true, "achievements": [["apiname": "Z", "achieved": 0]]]])) }
            if u.contains("GetGameAchievements") { return (403, [:], Data()) }
            if u.contains("GetSchemaForGame") { return (403, [:], Data()) }
            return (200, [:], json(["achievementpercentages": ["achievements": []]]))
        }
        do { _ = try await api.fetchAchievementsForGame(appId: id2, steamId: "1", apiKey: "k"); check(false, "should throw") }
        catch SteamAPIError.accessDenied { check(true, "catalog + schema both failing fails the game (will be retried)") }
        catch { check(false, "wrong error \(error)") }
        
        let id3 = base + 4
        Stub.handler = { req in
            let u = req.url!.absoluteString
            if u.contains("GetPlayerAchievements") { return (200, [:], json(["playerstats": ["success": true, "achievements": [["apiname": "Z", "achieved": 1, "unlocktime": 5]]]])) }
            if u.contains("GetGameAchievements") { return (403, [:], Data()) }
            if u.contains("GetSchemaForGame") { return (200, [:], json(["game": ["availableGameStats": ["achievements": [["name": "Z", "displayName": "Zed", "description": "zz", "icon": "zi", "icongray": "zg", "hidden": 0]]]]])) }
            return (200, [:], json(["achievementpercentages": ["achievements": [["name": "Z", "percent": 3.5]]]]))
        }
        let legacy = try! await api.fetchAchievementsForGame(appId: id3, steamId: "1", apiKey: "k")
        check(legacy.count == 1 && legacy[0].displayName == "Zed" && legacy[0].globalPercent == 3.5, "legacy schema+rarity fallback still works")
        
        // empty catalog = game without achievements
        let id4 = base + 3
        Stub.handler = { _ in (200, [:], json(["response": ["schema_version": 1, "groups": [], "achievements": []]])) }
        let emptyCat = try! await api.fetchCatalog(appId: id4)
        check(emptyCat.isEmpty, "game without achievements -> empty catalog")
        
        // store name lookup
        Stub.handler = { _ in (200, [:], json(["123": ["success": true, "data": ["name": "Real Name"]]])) }
        let nm1 = await api.fetchAppName(appId: 123); check(nm1 == "Real Name", "store name lookup")
        Stub.handler = { _ in (200, [:], json(["123": ["success": false]])) }
        let nm2 = await api.fetchAppName(appId: 123); check(nm2 == nil, "store lookup miss -> nil")
        
        // friends
        Stub.handler = { _ in (200, [:], json(["friendslist": ["friends": [["steamid": "11"], ["steamid": "22"]]]])) }
        let fr = try! await api.fetchFriendIds(steamId: "1", apiKey: "k"); check(fr == ["11", "22"], "friend list")
        Stub.handler = { _ in (200, [:], json(["playerstats": ["success": true, "achievements": [["apiname": "a", "achieved": 1], ["apiname": "b", "achieved": 0]]]])) }
        let counts = try! await api.fetchAchievementCounts(appId: base + 3, steamId: "1", apiKey: "k")
        check(counts.unlocked == 1 && counts.total == 2, "achievement counts")
    }
    

    // ===== Achievement sets / completion rules
    print("Achievement sets")
    do {
        func A(_ n: String, _ unlocked: Bool, group: Int = 0, archived: Bool = false) -> Achievement {
            Achievement(apiName: n, displayName: n, descriptionText: "", isUnlocked: unlocked, groupId: group, isArchived: archived)
        }
        let base0 = AchievementGroup(groupId: 0, name: "")
        let dlc = AchievementGroup(groupId: 1, name: "Expansion", dlcAppId: 777)
        let devOnly = AchievementGroup(groupId: 2, name: "Dev", isDeveloperOnly: true)
        var g = SteamGame(appId: 1, name: "G", achievements: [A("a", true), A("b", false), A("d1", false, group: 1), A("d2", false, group: 1), A("x", false, group: 2)],
                          hasAchievementsLoaded: true)
        g.achievementGroups = [base0, dlc, devOnly]
        check(g.totalAchievements == 2 && g.unlockedAchievements == 1, "DLC set without access and developer-only set are excluded (total 2)")
        check(!g.isPerfect, "not perfect while a base achievement is locked")
        g.achievements[3].isUnlocked = true
        check(g.totalAchievements == 4 && g.unlockedAchievements == 2, "unlocking something in a DLC set proves access: the whole set counts")
        g.achievements[3].isUnlocked = false
        g.dlcOverrides = ["1": true]
        check(g.totalAchievements == 4, "manual 'I own this DLC' override counts the set")
        g.dlcOverrides = ["1": false]
        g.achievements[3].isUnlocked = true
        check(g.totalAchievements == 2, "manual 'not owned' override excludes the set")
        
        var h = SteamGame(appId: 2, name: "H", achievements: [A("a", true), A("old", false, archived: true), A("oldDone", true, archived: true)], hasAchievementsLoaded: true)
        check(h.totalAchievements == 2 && h.unlockedAchievements == 2 && h.isPerfect, "archived+missed doesn't block completion; archived+unlocked still counts")
        h.achievements.removeAll()
        check(h.hasNoAchievements, "loaded game with nothing to track -> hasNoAchievements")
        h.hasAchievementsLoaded = false
        check(!h.hasNoAchievements, "unloaded game is not 'no achievements'")
        
        let parsed = AchievementCatalog.parse(response: [
            "schema_hash": 7,
            "groups": [["groupid": 3, "localized_name": "Late", "dlcappid": 5, "order": 2], ["groupid": 0, "localized_name": "", "dlcappid": 0, "order": 0]],
            "achievements": [["internal_name": "X", "localized_name": "Ex", "groupid": 3, "archived": true, "hidden": true, "player_percent_unlocked": "12.5"], ["localized_name": "no id"]]
        ], appId: 9)
        check(parsed.entries.count == 1 && parsed.entries[0].isArchived && parsed.entries[0].isHidden && parsed.entries[0].percent == 12.5, "catalog parse: flags, rarity, skips entries without an id")
        check(parsed.groups.map { $0.groupId } == [0, 3] && parsed.groups[1].isDLC && parsed.schemaHash == 7, "catalog parse: groups sorted by order, DLC detected")
        check(AchievementCatalog.parse(response: [:], appId: 1).isEmpty, "catalog parse: empty response is fine")
        
        // merge ordering follows the catalog
        let merged = AchievementMerger.merge(rows: [PlayerAchievementRow(apiName: "b", isUnlocked: true), PlayerAchievementRow(apiName: "a", isUnlocked: false)],
                                             catalog: AchievementCatalog(entries: [
                                                CatalogEntry(apiName: "a", displayName: "A", description: "", iconUrl: nil, grayIconUrl: nil, isHidden: false, percent: nil, groupId: 0, isArchived: false),
                                                CatalogEntry(apiName: "b", displayName: "B", description: "", iconUrl: nil, grayIconUrl: nil, isHidden: false, percent: nil, groupId: 0, isArchived: false)], groups: []),
                                             appId: 1)
        check(merged.map { $0.apiName } == ["a", "b"], "merge keeps catalog order")
        
        // community pages lower-case API names; the catalog's casing must win and nothing may be duplicated
        let ci = AchievementMerger.merge(rows: [PlayerAchievementRow(apiName: "ach_first", isUnlocked: true)],
                                         catalog: AchievementCatalog(entries: [
                                            CatalogEntry(apiName: "ACH_FIRST", displayName: "First", description: "", iconUrl: nil, grayIconUrl: nil, isHidden: false, percent: 5, groupId: 0, isArchived: false)], groups: []),
                                         appId: 1)
        check(ci.count == 1 && ci[0].apiName == "ACH_FIRST" && ci[0].globalPercent == 5 && ci[0].isUnlocked, "case-insensitive merge: no duplicates, catalog casing, rarity attached")
    }

    // ===== "No data for the player" is not "no achievements"
    print("Empty player results")
    do {
        func entry(_ n: String) -> CatalogEntry { CatalogEntry(apiName: n, displayName: n, description: "", iconUrl: nil, grayIconUrl: nil, isHidden: false, percent: 1, groupId: 0, isArchived: false) }
        let withAch = AchievementCatalog(entries: [entry("A"), entry("B")], groups: [])
        check(EmptyPlayerResult.resolve(catalog: withAch) == .lockedFromCatalog, "catalog has achievements + no player data -> list them all locked")
        check(EmptyPlayerResult.resolve(catalog: AchievementCatalog(entries: [], groups: [])) == .noAchievements, "empty catalog -> game really has none")
        check(EmptyPlayerResult.resolve(catalog: nil) == .unknown, "catalog unavailable -> unknown (never cache 'no achievements')")
        
        let locked = AchievementMerger.merge(rows: [], catalog: withAch, appId: 1)
        check(locked.count == 2 && locked.allSatisfy { !$0.isUnlocked }, "locked list built from the catalog")
        var g = SteamGame(appId: 1, name: "Unplayed", achievements: locked, hasAchievementsLoaded: true)
        check(!g.hasNoAchievements && g.totalAchievements == 2 && g.unlockedAchievements == 0, "an unplayed game with achievements is NOT hidden as 'no achievements'")
        g.achievements = []
        check(g.hasNoAchievements, "(a game with a truly empty list still is)")
        
        let health = SyncHealth()
        check(!health.communityBlocked, "fresh sync is not blocked")
        health.recordPrivate(); health.recordPrivate()
        check(!health.communityBlocked, "two refusals are not enough to stop asking")
        health.recordPrivate()
        check(health.communityBlocked && health.privateCount == 3, "three refusals and no success -> stop asking Steam for each game")
        let ok = SyncHealth(); ok.recordSuccess(); ok.recordPrivate(); ok.recordPrivate(); ok.recordPrivate()
        check(!ok.communityBlocked, "a profile that has answered before is never treated as blocked")
        
        // batch progress endpoint
        Stub.requests = []
        Stub.handler = { req in
            check(req.httpMethod == "POST", "progress request is a POST")
            return (200, [:], json(["response": ["achievement_progress": [["appid": 440, "unlocked": 312, "total": 520], ["appid": 10, "unlocked": 0, "total": 5]]]]))
        }
        let prog = await api.fetchAchievementProgress(steamId: "1", appIds: [440, 10], auth: SteamAuth(accessToken: "T"))
        check(prog?[440]?.unlocked == 312 && prog?[10]?.unlocked == 0 && prog?[10]?.total == 5, "progress parsed per game")
        check(Stub.requests.first?.absoluteString.contains("access_token=T") == true, "progress uses the sign-in token")
        Stub.handler = { _ in (500, [:], Data()) }
        let failed = await api.fetchAchievementProgress(steamId: "1", appIds: [440], auth: SteamAuth(accessToken: "T"))
        check(failed == nil, "progress endpoint failing -> nil (caller falls back to per-game requests)")
        let noAuthProgress = await api.fetchAchievementProgress(steamId: "1", appIds: [440], auth: SteamAuth())
        check(noAuthProgress == nil, "no credentials -> nil, no request")
    }
    
    // ===== The whole per-game pipeline, with the replies Steam really sends
    print("Game fetch pipeline")
    do {
        let community = SteamCommunityService(session: session)
        let ref = FetchRef(target: "someone", vanity: "someone", steamId64: "76561198000000001", steamId: "76561198000000001")
        let catalogReply = json(["response": ["groups": [["groupid": 0, "localized_name": "", "dlcappid": 0]],
                                              "achievements": [["internal_name": "ACH_ONE", "localized_name": "One", "localized_desc": "d", "icon": "i.jpg", "icon_gray": "g.jpg", "player_percent_unlocked": "10.0", "groupid": 0],
                                                               ["internal_name": "ACH_TWO", "localized_name": "Two", "localized_desc": "d", "icon": "j.jpg", "icon_gray": "h.jpg", "player_percent_unlocked": "20.0", "groupid": 0]]]])
        let emptyCatalog = json(["response": ["groups": [], "achievements": []]])
        let profileHTML = Data("<!DOCTYPE html>\n<html class=\" responsive\"><head><title>Steam Community :: sampleuser</title></head><body>profile</body></html>".utf8)
        let errorHTML = Data("<!DOCTYPE html><html><head><title>Steam Community :: Error</title></head><body>The specified profile could not be found.</body></html>".utf8)
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><playerstats><game><gameName><![CDATA[Real Game]]></gameName></game><achievements>
        <achievement closed="1"><name>One</name><apiname>ach_one</apiname><description>d</description><unlockTimestamp>1700000000</unlockTimestamp></achievement>
        <achievement closed="0"><name>Two</name><apiname>ach_two</apiname><description>d</description></achievement></achievements></playerstats>
        """.utf8)
        
        func run(appId: Int, catalog: Data?, catalogStatus: Int = 200, stats: Data, health: SyncHealth = SyncHealth(), knownLocked: Bool = false, hadBefore: Bool = false) async -> GameFetchOutcome {
            Stub.handler = { req in
                let u = req.url!.absoluteString
                if u.contains("GetGameAchievements") { return catalog == nil ? (catalogStatus, [:], Data()) : (200, [:], catalog!) }
                if u.contains("steamcommunity.com") { return (200, [:], stats) }
                return (500, [:], Data())
            }
            MetadataCache.clearTestEntry(appId: appId)
            return await GameFetcher.fetch(appId: appId, ref: ref, apiKey: "", cookies: [], hadAchievementsBefore: hadBefore, health: health, knownLocked: knownLocked, api: api, community: community)
        }
        func summarize(_ o: GameFetchOutcome) -> (count: Int, unlocked: Int, verified: Bool, failed: Bool) {
            switch o {
            case .loaded(let a, _, _, _, let v): return (a.count, a.filter { $0.isUnlocked }.count, v, false)
            case .failed: return (0, 0, false, true)
            case .cancelled: return (0, 0, false, false)
            }
        }
        let b = 980_000_000 + Int.random(in: 0..<1000) * 10
        
        var r = summarize(await run(appId: b + 1, catalog: catalogReply, stats: xml))
        check(r.count == 2 && r.unlocked == 1 && r.verified, "normal game: unlock state merged with the catalog")
        
        r = summarize(await run(appId: b + 2, catalog: catalogReply, stats: profileHTML))
        check(r.count == 2 && r.unlocked == 0 && r.verified && !r.failed, "UNPLAYED game (Steam replies with the profile's HTML page): all achievements listed as locked, NOT 'no achievements'")
        
        let priv = SyncHealth()
        r = summarize(await run(appId: b + 3, catalog: catalogReply, stats: errorHTML, health: priv))
        check(r.count == 2 && r.unlocked == 0 && !r.verified && !r.failed && priv.privateCount == 1, "unreadable/private profile: catalog list, flagged unverified so it is re-checked after signing in")
        
        r = summarize(await run(appId: b + 4, catalog: emptyCatalog, stats: profileHTML))
        check(r.count == 0 && r.verified && !r.failed, "catalog says none: the game really has no achievements")
        
        r = summarize(await run(appId: b + 5, catalog: nil, catalogStatus: 403, stats: profileHTML))
        check(r.failed, "catalog unreachable + no player data: failed (retried), never saved as 'no achievements'")
        
        let blocked = SyncHealth(); blocked.recordPrivate(); blocked.recordPrivate(); blocked.recordPrivate()
        var requestedStats = false
        Stub.handler = { req in
            let u = req.url!.absoluteString
            if u.contains("steamcommunity.com") { requestedStats = true }
            return u.contains("GetGameAchievements") ? (200, [:], catalogReply) : (200, [:], xml)
        }
        MetadataCache.clearTestEntry(appId: b + 6)
        let skipped = summarize(await GameFetcher.fetch(appId: b + 6, ref: ref, apiKey: "", cookies: [], hadAchievementsBefore: false, health: blocked, api: api, community: community))
        check(skipped.count == 2 && !skipped.verified && !requestedStats, "after repeated refusals the rest of the library is not requested one by one")
        
        r = summarize(await run(appId: b + 7, catalog: catalogReply, stats: xml, knownLocked: true))
        check(r.count == 2 && r.unlocked == 0 && r.verified, "batch progress says 0 unlocked: answered from the catalog without a per-game request")
        
        r = summarize(await run(appId: b + 8, catalog: emptyCatalog, stats: profileHTML, hadBefore: true))
        check(r.count == 0 && r.verified, "a game that had achievements and now reports none keeps the honest answer")
        
        // signed in: Steam's player endpoint (IPlayerService/GetUserAchievements), keyed by Steam's numeric ids
        let tokenAuth = SteamAuth(accessToken: "TOK")
        let keyedCatalog = json(["response": ["groups": [["groupid": 0, "localized_name": "", "dlcappid": 0]],
                                              "achievements": [["internal_name": "ACH_ONE", "internal_key": 11, "localized_name": "One", "localized_desc": "d", "icon": "i.jpg", "icon_gray": "g.jpg", "player_percent_unlocked": "10.0", "groupid": 0],
                                                               ["internal_name": "ACH_TWO", "internal_key": 12, "localized_name": "Two", "localized_desc": "d", "icon": "j.jpg", "icon_gray": "h.jpg", "player_percent_unlocked": "20.0", "groupid": 0],
                                                               ["internal_name": "ACH_THREE", "internal_key": 13, "localized_name": "Three", "localized_desc": "d", "icon": "k.jpg", "icon_gray": "l.jpg", "player_percent_unlocked": "30.0", "groupid": 0]]]])
        var userCalls = 0
        var lastUserURL = ""
        func tokenRun(appId: Int, userReply: (Int, Data), health: SyncHealth = SyncHealth()) async -> GameFetchOutcome {
            Stub.handler = { req in
                let u = req.url!.absoluteString
                if u.contains("GetGameAchievements") { return (200, [:], keyedCatalog) }
                if u.contains("GetUserAchievements") { userCalls += 1; lastUserURL = u; return (userReply.0, userReply.0 == 200 ? [:] : ["Retry-After": "0"], userReply.1) }
                if u.contains("steamcommunity.com") { return (200, [:], xml) }
                return (500, [:], Data())
            }
            MetadataCache.clearTestEntry(appId: appId)
            return await GameFetcher.fetch(appId: appId, ref: ref, apiKey: "", token: tokenAuth, cookies: [], hadAchievementsBefore: false, health: health, api: api, community: community)
        }
        func detail(_ o: GameFetchOutcome) -> [Achievement] { if case .loaded(let a, _, _, _, _) = o { return a }; return [] }
        
        let good = json(["response": ["achievements": [["internal_key": 11, "unlocked": true, "unlock_time": 1_700_000_000], ["internal_key": 12, "unlocked": false, "unlock_time": 0], ["internal_key": 999, "unlocked": true, "unlock_time": 5]]]])
        userCalls = 0
        let outcome = await tokenRun(appId: b + 9, userReply: (200, good))
        let list = detail(outcome)
        check(list.count == 3 && list.first { $0.apiName == "ACH_ONE" }?.isUnlocked == true && list.first { $0.apiName == "ACH_ONE" }?.unlockTimestamp == Date(timeIntervalSince1970: 1_700_000_000), "signed in: unlocks and times come from the player endpoint, mapped by numeric key")
        check(list.first { $0.apiName == "ACH_THREE" }?.isUnlocked == false && userCalls == 1, "achievements missing from the player's rows are locked; one request per game")
        check(lastUserURL.contains("access_token=TOK") && lastUserURL.contains("steamid=76561198000000001"), "the sign-in token is attached so the owner can read private data")
        
        let none = json(["response": ["schema_version": 3]])
        r = summarize(await tokenRun(appId: b + 10, userReply: (200, none)))
        check(r.count == 3 && r.unlocked == 0 && r.verified, "unplayed game: no rows -> everything listed as locked")
        
        r = summarize(await tokenRun(appId: b + 11, userReply: (500, Data())))
        check(r.count == 3 && r.unlocked == 1, "endpoint down -> falls back to the community page (still merged with the catalog)")
        
        // an older cached catalog without numeric keys is refreshed once, then the rows can be mapped
        let oldCache = AchievementCatalog(entries: [CatalogEntry(apiName: "ACH_ONE", displayName: "One", description: "", iconUrl: nil, grayIconUrl: nil, isHidden: false, percent: nil, groupId: 0, isArchived: false)], groups: [])
        check(oldCache.playerRows(from: [UserAchievementRow(internalKey: 11, unlocked: true)]) == nil, "catalog without numeric keys can't map rows (so it is refetched)")
        check(oldCache.playerRows(from: []) != nil, "...but nothing to map is fine")
    }
    
    
    // ===== Now Playing: reading what a player is doing
    print("Now Playing status")
    do {
        check(SteamCommunityService.currentGameName(onlineState: "in-game", stateMessage: "In-Game<br/>GUILTY GEAR", explicit: "") == "GUILTY GEAR", "page status 'In-Game<br/>NAME' -> game name")
        check(SteamCommunityService.currentGameName(onlineState: "in-game", stateMessage: "In-Game<br/>Marvel&#39;s Spider-Man &amp; Friends", explicit: "") == "Marvel's Spider-Man & Friends", "HTML entities in the game name are decoded")
        check(SteamCommunityService.currentGameName(onlineState: "in-game", stateMessage: "In-Non-Steam-Game<br/>Some Emulator", explicit: "") == "Some Emulator", "non-Steam game status also gives a name")
        check(SteamCommunityService.currentGameName(onlineState: "online", stateMessage: "Online", explicit: "") == nil, "online and not playing -> no game")
        check(SteamCommunityService.currentGameName(onlineState: "offline", stateMessage: "Last Online 3 hrs, 2 mins ago", explicit: "") == nil, "offline -> no game")
        check(SteamCommunityService.currentGameName(onlineState: "in-game", stateMessage: "In-Game", explicit: "") == nil, "in-game without a name -> nil")
        check(SteamCommunityService.currentGameName(onlineState: "online", stateMessage: "", explicit: "Portal") == "Portal", "an explicit inGameInfo name still wins")
        
        // End to end through the real profile parser with the XML Steam sends today
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><profile><steamID64>76561198000000002</steamID64><steamID><![CDATA[sampleuser]]></steamID>
        <onlineState>in-game</onlineState><stateMessage><![CDATA[In-Game<br/>GUILTY GEAR]]></stateMessage><privacyState>public</privacyState><customURL><![CDATA[yourname]]></customURL>
        <mostPlayedGames><mostPlayedGame><gameName><![CDATA[Arcade Paradise]]></gameName><gameLink><![CDATA[https://steamcommunity.com/app/1388870]]></gameLink><hoursOnRecord>8.1</hoursOnRecord></mostPlayedGame></mostPlayedGames></profile>
        """
        Stub.handler = { _ in (200, [:], Data(xml.utf8)) }
        let player = try! await SteamCommunityService(session: session).fetchPlayerProfile(steamId: "76561198000000002")
        check(player.isInGame && player.currentGameName == "GUILTY GEAR" && player.personaState == 1, "profile page XML -> player is in-game with the right title (not a 'most played' game)")
        
        check(GameNameMatcher.matches("DARK SOULS™ III", "Dark Souls III"), "title match ignores trademark signs and case")
        check(GameNameMatcher.matches("Pokémon Legends: Arceus", "Pokemon Legends Arceus"), "title match ignores accents and punctuation")
        check(GameNameMatcher.matches("Sonic & Knuckles", "Sonic and Knuckles"), "ampersand equals 'and'")
        check(!GameNameMatcher.matches("Portal", "Portal 2"), "different games do not match")
        check(!GameNameMatcher.matches("", ""), "empty titles never match")
        
        Stub.handler = { _ in (200, [:], json(["total": 2, "items": [["type": "app", "name": "GUILTY GEAR -STRIVE-", "id": 1384160], ["type": "app", "name": "GUILTY GEAR", "id": 850980]]])) }
        let found = await api.searchAppId(name: "GUILTY GEAR")
        check(found == 850980, "store search returns the exact-title app id (not the first result)")
        Stub.handler = { _ in (200, [:], json(["total": 1, "items": [["type": "app", "name": "Something Else", "id": 5]]])) }
        let notFound = await api.searchAppId(name: "GUILTY GEAR")
        check(notFound == nil, "no exact title match -> nil (never guess)")
        
        // merging the two sources
        let apiOffline = SteamPlayer(steamId: "1", personaName: "Me", avatarUrl: "a", personaState: 0)
        let pageInGame = SteamPlayer(steamId: "1", personaName: "Me", personaState: 1, currentGameName: "GUILTY GEAR")
        let merged = SteamPlayer.merge(api: apiOffline, community: pageInGame)
        check(merged?.isInGame == true && merged?.currentGameName == "GUILTY GEAR" && merged?.avatarUrl == "a" && merged?.personaState == 1, "API says offline but the page sees a game: the game wins, API fields kept")
        let apiGame = SteamPlayer(steamId: "1", personaName: "Me", personaState: 1, currentGameId: 850980, currentGameName: "GUILTY GEAR")
        check(SteamPlayer.merge(api: apiGame, community: SteamPlayer(steamId: "1", personaName: "Me", personaState: 0))?.currentGameId == 850980, "API game id survives a page that says nothing")
        check(SteamPlayer.merge(api: nil, community: pageInGame)?.currentGameName == "GUILTY GEAR", "page only")
        check(SteamPlayer.merge(api: nil, community: nil) == nil, "no answer from either source -> nil")
    }
    
    // ===== Live status (mini profile) and not erasing unlocks
    print("Live status")
    do {
        let sample = """
        <div class="miniprofile_container"><div class="miniprofile_playersection text_shadow">
        <div class="playersection_avatar_frame"><img src="https://shared.akamai.steamstatic.com/community_assets/images/items/1299690/7d375c0d29856cb5eb8c74fb9e5fb52cee17c930.png"></div>
        <div class="playersection_avatar border_color_in-game"><img src="https://avatars.akamai.steamstatic.com/e055058684742e62821e01cb6135550b61b41ca5_medium.jpg" srcset="x 1x"></div>
        <div class="player_content"><span class="persona in-game">sampleuser</span></div></div>
        <div class="miniprofile_gamesection miniprofile_backdropblur miniprofile_backdrop"><img class="game_logo" src="https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/215510/capsule_184x69.jpg?t=1666995931">
        <div class="miniprofile_game_details"><span class="game_state">In-Game</span><span class="miniprofile_game_name">Rocketbirds: Hardboiled Chicken</span></div></div></div>
        """
        let mini = SteamCommunityService.parseMiniProfile(sample)
        check(mini?.isInGame == true && mini?.gameName == "Rocketbirds: Hardboiled Chicken" && mini?.appId == 215510 && mini?.personaName == "sampleuser", "live card: in-game, name and app id read")
        check(mini?.avatarUrl == "https://avatars.akamai.steamstatic.com/e055058684742e62821e01cb6135550b61b41ca5_full.jpg", "live card: the real avatar picture (full size), NOT the avatar frame decoration that comes first in the markup")
        check(live0AvatarIsPicture(mini?.avatarUrl), "avatar URL is a profile picture, never a frame image")
        let offline = SteamCommunityService.parseMiniProfile("<div class=\"miniprofile_container\"><div class=\"player_content\"><span class=\"persona offline\">Me &amp; Co</span></div></div>")
        check(offline?.isInGame == false && offline?.stateClass == "offline" && offline?.personaName == "Me & Co", "live card: offline, entities decoded")
        check(SteamCommunityService.parseMiniProfile("<html>error</html>") == nil, "not a live card -> nil")
        
        Stub.requests = []
        Stub.handler = { _ in (200, [:], Data(sample.utf8)) }
        let live = await SteamCommunityService(session: session).fetchMiniProfileStatus(steamId64: "76561198000000002")
        check(live?.currentGameId == 215510 && live?.personaState == 1, "status as a player: game id and online state")
        check(Stub.requests.last?.absoluteString.contains("/miniprofile/39734274") == true, "SteamID64 converted to the account id")
        check(Stub.requests.last?.absoluteString.contains("_=") == true, "request carries a cache-busting value")
        let none = await SteamCommunityService(session: session).fetchMiniProfileStatus(steamId64: "not-a-number")
        check(none == nil, "invalid id -> nil without a request")
        
        // saved unlocks are never erased by an ambiguous answer
        let community = SteamCommunityService(session: session)
        let ref = FetchRef(target: "someone", vanity: nil, steamId64: "76561198000000001", steamId: "76561198000000001")
        let cat = json(["response": ["groups": [], "achievements": [["internal_name": "A", "localized_name": "A", "internal_key": 1, "groupid": 0], ["internal_name": "B", "localized_name": "B", "internal_key": 2, "groupid": 0]]]])
        let htmlNoStats = Data("<!DOCTYPE html><html><head><title>Steam Community :: me</title></head></html>".utf8)
        Stub.handler = { req in req.url!.absoluteString.contains("GetGameAchievements") ? (200, [:], cat) : (200, [:], htmlNoStats) }
        MetadataCache.clearTestEntry(appId: 970_000_001)
        let kept = await GameFetcher.fetch(appId: 970_000_001, ref: ref, apiKey: "", cookies: [], hadAchievementsBefore: true, health: SyncHealth(), previousUnlocked: 7, api: api, community: community)
        var wasFailure = false; if case .failed = kept { wasFailure = true }
        check(wasFailure, "ambiguous 'no data' reply for a game with saved unlocks -> failed (saved unlocks kept), not 'all locked'")
        MetadataCache.clearTestEntry(appId: 970_000_002)
        let fresh = await GameFetcher.fetch(appId: 970_000_002, ref: ref, apiKey: "", cookies: [], hadAchievementsBefore: false, health: SyncHealth(), previousUnlocked: 0, api: api, community: community)
        var count = -1; if case .loaded(let a, _, _, _, _) = fresh { count = a.count }
        check(count == 2, "the same reply for a never-played game is still a locked list")
    }
    
    // ===== Steam's bot filter: never prolong a block
    print("Community throttle")
    do {
        await CommunityThrottle.shared.reset()
        var hits = 0
        Stub.handler = { _ in hits += 1; return (403, [:], Data("<HTML><HEAD>\n<TITLE>Access Denied</TITLE></HEAD></HTML>".utf8)) }
        let community = SteamCommunityService(session: session)
        let first = await community.fetchMiniProfileStatus(steamId64: "76561198000000002")
        check(first == nil && hits == 1, "an 'Access Denied' answer is handled (no crash, no status)")
        let blocked = await CommunityThrottle.shared.isBlocked
        check(blocked, "after a refusal the community host is marked as cooling down")
        _ = await community.fetchMiniProfileStatus(steamId64: "76561198000000002")
        _ = try? await community.fetchPlayerProfile(steamId: "76561198000000002")
        check(hits == 1, "while cooling down NO further community request is sent (so the block is not prolonged)")
        await CommunityThrottle.shared.reset()
        
        // the gate paces requests
        let gate = CommunityThrottle(spacing: 0.15, coolDown: 5)
        let t0 = Date()
        for _ in 0..<4 { _ = await gate.acquire() }
        let elapsed = Date().timeIntervalSince(t0)
        check(elapsed >= 0.4 && elapsed < 1.5, "4 requests are spaced out (took \(String(format: "%.2f", elapsed))s)")
        await gate.noteRefused()
        let afterRefusal = await gate.acquire()
        check(!afterRefusal, "acquire() says no during the cool-down")
        await gate.reset()
        let afterReset = await gate.acquire()
        check(afterReset, "...and yes again after it")
    }
    
    // ===== Friends without an API key
    print("Friends (sign-in only)")
    do {
        Stub.requests = []
        Stub.handler = { _ in (200, [:], json(["response": ["friendslist": ["bincremental": false, "friends": [
            ["ulfriendid": "76561198000000011", "efriendrelationship": 3],
            ["ulfriendid": "76561198000000012", "efriendrelationship": 3],
            ["ulfriendid": "76561198000000013", "efriendrelationship": 2],   // pending request
            ["ulfriendid": "76561198000000014", "efriendrelationship": 1]    // blocked
        ]]]])) }
        let ids = try! await api.fetchFriendIds(steamId: "1", auth: SteamAuth(accessToken: "TOK"))
        check(ids == ["76561198000000011", "76561198000000012"], "sign-in token: friends service, only real friends (not pending or blocked)")
        check(Stub.requests.last?.absoluteString.contains("IFriendsListService/GetFriendsList") == true && Stub.requests.last?.absoluteString.contains("access_token=TOK") == true, "uses the friends service with the token")
        Stub.handler = { _ in (200, [:], json(["friendslist": ["friends": [["steamid": "5"], ["steamid": "6"]]]])) }
        let keyed = try! await api.fetchFriendIds(steamId: "1", auth: SteamAuth(apiKey: "KEY"))
        check(keyed == ["5", "6"] && Stub.requests.last?.absoluteString.contains("ISteamUser/GetFriendList") == true, "with an API key the classic endpoint is still used")
        
        // names + avatars from each friend's mini profile, cached
        let card = { (name: String) -> Data in Data("""
            <div class="miniprofile_container"><div class="playersection_avatar_frame"><img src="https://shared.akamai.steamstatic.com/community_assets/images/items/1/x.png"></div>
            <div class="playersection_avatar border_color_online"><img src="https://avatars.akamai.steamstatic.com/aaaa_medium.jpg"></div>
            <div class="player_content"><span class="persona online">\(name)</span></div></div>
            """.utf8) }
        var cardRequests = 0
        Stub.handler = { req in
            cardRequests += 1
            let id = req.url!.lastPathComponent
            return (200, [:], card("Friend \(id)"))
        }
        let dir = tmp()
        let store = FriendProfiles(directory: dir)
        var lastProgress = 0
        let first = await store.profiles(for: ["76561198000000011", "76561198000000012"], community: SteamCommunityService(session: session)) { lastProgress = max(lastProgress, $0) }
        check(first.count == 2 && first[0].personaName.hasPrefix("Friend ") && first[0].avatarUrl?.contains("avatars.akamai") == true && first[0].steamId == "76561198000000011", "friend names and real avatars (not frames) from the mini profile, in list order")
        check(cardRequests == 2 && lastProgress == 2, "one request per friend, progress reported")
        let second = await store.profiles(for: ["76561198000000011", "76561198000000012"], community: SteamCommunityService(session: session))
        check(second.count == 2 && cardRequests == 2, "second visit comes from the cache (no requests)")
        let reopened = await FriendProfiles(directory: dir).profiles(for: ["76561198000000011"], community: SteamCommunityService(session: session))
        check(reopened.first?.personaName.hasPrefix("Friend ") == true && cardRequests == 2, "cache survives a restart (saved on disk)")
        Stub.handler = { _ in (500, ["Retry-After": "0"], Data()) }
        let unknown = await FriendProfiles(directory: tmp()).profiles(for: ["76561198000000099"], community: SteamCommunityService(session: session))
        check(unknown.first?.personaName == "Steam user 0099", "a friend Steam doesn't answer for still appears, with a placeholder name")
        
        // batch progress runs its chunks in parallel and merges them
        Stub.handler = { req in
            let body = String(data: req.httpBodyStream.map { s -> Data in
                s.open(); defer { s.close() }
                var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
                while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
                return d } ?? Data(), encoding: .utf8) ?? ""
            _ = body
            return (200, [:], json(["response": ["achievement_progress": [["appid": 1, "unlocked": 2, "total": 3]]]]))
        }
        let many = Array(1...350)
        let progress = await api.fetchAchievementProgress(steamId: "1", appIds: many, auth: SteamAuth(accessToken: "T"))
        check(progress?[1]?.unlocked == 2, "batch progress with 4 chunks (350 games) still merges correctly")
    }
    
    // ===== Now Playing must not flicker
    print("Status debouncing")
    do {
        let playing = SteamPlayer(steamId: "1", personaName: "Me", personaState: 1, currentGameId: 215510, currentGameName: "Rocketbirds")
        let online = SteamPlayer(steamId: "1", personaName: "Me", personaState: 1)
        let other = SteamPlayer(steamId: "1", personaName: "Me", personaState: 1, currentGameId: 440, currentGameName: "TF2")
        let t0 = Date()
        var d = GameStatusDebouncer(graceSeconds: 60)
        
        var cur = d.resolve(observed: playing, previous: nil, now: t0)
        check(cur.isInGame && cur.currentGameId == 215510, "entering a game is shown immediately")
        cur = d.resolve(observed: online, previous: cur, now: t0.addingTimeInterval(15))
        check(cur.isInGame && cur.currentGameId == 215510, "one flicker to 'online, no game' does not drop Now Playing")
        cur = d.resolve(observed: online, previous: cur, now: t0.addingTimeInterval(45))
        check(cur.isInGame, "still held 45 s after the game was last seen")
        cur = d.resolve(observed: online, previous: cur, now: t0.addingTimeInterval(61))
        check(!cur.isInGame && cur.personaState == 1, "after the grace period the game is really gone")
        
        var e = GameStatusDebouncer(graceSeconds: 60)
        var c2 = e.resolve(observed: playing, previous: nil, now: t0)
        c2 = e.resolve(observed: other, previous: c2, now: t0.addingTimeInterval(10))
        check(c2.currentGameId == 440, "switching to another game is immediate")
        
        var f = GameStatusDebouncer(graceSeconds: 60)
        let off = SteamPlayer(steamId: "1", personaName: "Me", personaState: 0)
        check(!f.resolve(observed: off, previous: nil, now: t0).isInGame, "offline from the start stays offline")
        var g = GameStatusDebouncer(graceSeconds: 60)
        _ = g.resolve(observed: playing, previous: nil, now: t0)
        let wentOffline = g.resolve(observed: off, previous: playing, now: t0.addingTimeInterval(20))
        check(wentOffline.isInGame && wentOffline.personaState == 1, "a brief 'offline' blip while playing keeps the game and the online state")
    }
    
    // ===== Background sync: spotting games with new unlocks
    print("Change detection")
    do {
        func ach(_ n: Int, unlocked: Int) -> [Achievement] { (0..<n).map { Achievement(apiName: "A\($0)", displayName: "A", descriptionText: "", isUnlocked: $0 < unlocked) } }
        let a = SteamGame(appId: 1, name: "Same", achievements: ach(10, unlocked: 3), hasAchievementsLoaded: true)
        let b = SteamGame(appId: 2, name: "NewUnlock", achievements: ach(10, unlocked: 3), hasAchievementsLoaded: true)
        let c = SteamGame(appId: 3, name: "Unplayed", achievements: ach(10, unlocked: 0), hasAchievementsLoaded: true)
        let d = SteamGame(appId: 4, name: "NoAch", achievements: [], hasAchievementsLoaded: true)
        let e = SteamGame(appId: 5, name: "NotLoaded", hasAchievementsLoaded: false)
        let progress: [Int: (unlocked: Int, total: Int)] = [1: (3, 10), 2: (4, 10), 3: (1, 10), 4: (0, 0), 5: (2, 10), 99: (5, 5)]
        let changed = UnlockChangeDetector.changedAppIds(games: [a, b, c, d, e], progress: progress)
        check(changed == [2, 3], "only games whose unlock count differs are refetched (new unlock, first unlock); unchanged, empty, not-yet-loaded and unknown games are left alone")
        check(UnlockChangeDetector.changedAppIds(games: [a], progress: [:]).isEmpty, "no progress answer -> nothing flagged")
    }
    
    // ===== Quick wins and the daily plan
    print("Plan engine")
    do {
        func game(_ id: Int, _ name: String, unlocked: Int, percents: [Double], minutes: Int = 0, hiddenIdx: Set<Int> = []) -> SteamGame {
            let ach = percents.enumerated().map { (i, p) in Achievement(apiName: "G\(id)A\(i)", displayName: "A\(i)", descriptionText: "d", isUnlocked: i < unlocked, globalPercent: p, isHidden: hiddenIdx.contains(i)) }
            return SteamGame(appId: id, name: name, playtimeMinutes: minutes, achievements: ach, hasAchievementsLoaded: true)
        }
        let a = game(1, "Alpha", unlocked: 2, percents: [90, 80, 70, 60, 50, 40, 30], minutes: 600)
        let b = game(2, "Beta", unlocked: 0, percents: [95, 85, 75, 65, 55], minutes: 0)
        let c = game(3, "Gamma", unlocked: 5, percents: [50, 50, 50, 50, 50], minutes: 300)     // perfect
        let d = game(4, "Delta", unlocked: 1, percents: [99, 98, 97, 96], minutes: 60, hiddenIdx: [1])
        
        let wins = PlanEngine.quickWins(games: [a, b, c, d], limit: 50, perGameCap: 2)
        check(wins.first?.gameName == "Delta" && wins.first?.percent == 97, "the most common locked achievement comes first")
        check(wins.filter { $0.gameName == "Beta" }.count == 2 && wins.filter { $0.gameName == "Alpha" }.count == 2, "at most 2 per game when the cap is 2")
        check(!wins.contains { $0.gameName == "Gamma" }, "finished games are not suggested")
        check(!wins.contains { $0.achievement.isHidden }, "hidden achievements are skipped")
        check(wins.contains { $0.gameName == "Beta" && !$0.gameStarted } && wins.contains { $0.gameName == "Alpha" && $0.gameStarted }, "unstarted games are flagged so the list can hide them")
        check(wins.map { $0.percent } == wins.map { $0.percent }.sorted(by: >), "sorted by how many players have it")
        check(PlanEngine.quickWins(games: [a, b, c, d], limit: 3, perGameCap: 5).count == 3, "limit respected")
        
        // hours left at your own pace
        check(PlanEngine.hoursLeft(for: game(5, "Eps", unlocked: 4, percents: [50, 50, 50, 50, 50, 50, 50], minutes: 600)) == 7.5, "10 h played / 4 unlocked * 3 remaining = 7.5 h")
        check(PlanEngine.hoursLeft(for: b) == nil && PlanEngine.hoursLeft(for: c) == nil, "no estimate without history, or when nothing is left")
        check(PlanEngine.hoursLeft(for: d) == nil, "too little history (1 unlock, 1 h) -> no estimate")
        check(PlanEngine.hoursText(0.4) == "under 1 hour" && PlanEngine.hoursText(2.55) == "about 2.5 hours" && PlanEngine.hoursText(24.6) == "about 25 hours", "readable durations")
        
        // today's plan: deterministic per day, rotates, only sensible candidates
        func many(_ n: Int) -> [SteamGame] { (1...n).map { game(100 + $0, "G\($0)", unlocked: 20 + $0 % 3, percents: Array(repeating: 40, count: 30), minutes: 1200) } }
        let pool = many(10)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day1 = Date(timeIntervalSince1970: 1_700_000_000), day2 = day1.addingTimeInterval(86_400 + 3600)
        let p1 = PlanEngine.dailyPlan(games: pool, on: day1, calendar: cal), p1again = PlanEngine.dailyPlan(games: pool, on: day1.addingTimeInterval(1800), calendar: cal)
        let p2 = PlanEngine.dailyPlan(games: pool, on: day2, calendar: cal)
        check(p1 != nil && p1?.game.appId == p1again?.game.appId, "the same game all day")
        check(p1?.game.appId != p2?.game.appId, "a different game tomorrow")
        check((p1?.picks.count ?? 0) == 3 && p1!.picks.allSatisfy { !$0.isUnlocked }, "up to 3 locked achievements to start with")
        check(PlanEngine.dailyPlan(games: [b, c], on: day1, calendar: cal) == nil, "no candidate (unstarted or finished) -> no plan")
        let far = game(9, "Far", unlocked: 1, percents: Array(repeating: 40, count: 100))
        check(PlanEngine.dailyPlan(games: [far], on: day1, calendar: cal) == nil, "99 left is not a 'today' goal")
    }
    
    // ===== Notification rules
    print("Notification policy")
    do {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ h: Int, _ m: Int = 0, day: Int = 1) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))! }
        func ev(_ n: String, _ pct: Double?, detected: Date = at(12)) -> UnlockEvent {
            UnlockEvent(appId: 1, gameName: "G", achievement: Achievement(apiName: n, displayName: n, descriptionText: "", isUnlocked: true, globalPercent: pct), detectedAt: detected, isSeen: false)
        }
        var p = NotificationPolicy()
        let normal = ev("a", 40), rare = ev("b", 0.4)
        var r = p.route([normal, rare], at: at(12), calendar: cal)
        check(r.post.count == 2 && r.queue.isEmpty && r.celebrate.map { $0.id } == [rare.id], "default: banner for each, rare one celebrated")
        
        p.quietHoursEnabled = true   // 22:00 -> 08:00
        check(p.isQuiet(at: at(23), calendar: cal) && p.isQuiet(at: at(3), calendar: cal) && !p.isQuiet(at: at(8), calendar: cal) && !p.isQuiet(at: at(21, 59), calendar: cal), "quiet hours wrap past midnight")
        r = p.route([normal, rare], at: at(23), calendar: cal)
        check(r.post.isEmpty && r.queue.count == 2, "quiet: everything held, even rare banners")
        p.quietStartMinute = 13 * 60; p.quietEndMinute = 15 * 60
        check(p.isQuiet(at: at(14), calendar: cal) && !p.isQuiet(at: at(15), calendar: cal), "same-day quiet window")
        
        // held because of quiet hours: delivered once they end
        let held = [ev("c", 20, detected: at(23))]
        check(!p.summaryDue(pending: held, lastSummary: nil, now: at(14), calendar: cal), "not while quiet")
        check(p.summaryDue(pending: held, lastSummary: nil, now: at(15), calendar: cal), "right after quiet hours end")
        check(!p.summaryDue(pending: [], lastSummary: nil, now: at(15), calendar: cal), "nothing held -> nothing to say")
        
        // daily summary
        p = NotificationPolicy(); p.dailySummary = true
        r = p.route([normal, rare], at: at(12), calendar: cal)
        check(r.queue.map { $0.id } == [normal.id] && r.post.map { $0.id } == [rare.id], "summary mode: only ultra-rare gets its own banner")
        p.celebrateUltraRare = false
        r = p.route([rare], at: at(12), calendar: cal)
        check(r.queue.count == 1 && r.celebrate.isEmpty, "celebration off -> rare unlocks join the summary")
        check(!p.summaryDue(pending: [normal], lastSummary: nil, now: at(19, 59), calendar: cal) && p.summaryDue(pending: [normal], lastSummary: nil, now: at(20), calendar: cal), "summary goes out at the chosen time")
        check(!p.summaryDue(pending: [normal], lastSummary: at(20), now: at(21), calendar: cal), "only once a day")
        check(p.summaryDue(pending: [normal], lastSummary: at(20, day: 1), now: at(20, day: 2), calendar: cal), "again the next day")
        check(p.summaryDue(pending: [ev("old", 5, detected: at(10, day: 1))], lastSummary: at(20, day: 2), now: at(11, day: 3), calendar: cal), "never holds an unlock for more than a day")
        
        p = NotificationPolicy(); p.enabled = false
        r = p.route([normal, rare], at: at(12), calendar: cal)
        check(r.post.isEmpty && r.queue.isEmpty && r.celebrate.count == 1, "notifications off: no banners, in-app celebration still works")
        let t = NotificationPolicy.summaryText([ev("x", 50), ev("y", 2.5), ev("z", 30), ev("w", 20)])
        check(t.title == "4 new achievements" && t.body.contains("and 1 more") && t.body.contains("Rarest: y"), "summary text names the rarest")
    }
    
    // ===== Year recap
    print("Year recap")
    do {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: y, month: m, day: day, hour: h))! }
        func g(_ id: Int, _ name: String, _ items: [(Double?, Date?)]) -> SteamGame {
            let ach = items.enumerated().map { (i, it) in Achievement(apiName: "G\(id)A\(i)", displayName: "A\(i)", descriptionText: "", isUnlocked: it.1 != nil, unlockTimestamp: it.1, globalPercent: it.0) }
            return SteamGame(appId: id, name: name, playtimeMinutes: 0, achievements: ach, hasAchievementsLoaded: true)
        }
        let one = g(1, "One", [(50, d(2025, 3, 1)), (2.0, d(2025, 3, 1, 15)), (30, d(2025, 11, 20))])           // finished in 2025
        let two = g(2, "Two", [(0.8, d(2025, 3, 2)), (40, d(2024, 12, 31)), (10, nil)])                        // not finished
        let three = g(3, "Three", [(60, d(2024, 5, 5)), (70, d(2024, 6, 6))])                                  // finished in 2024
        let recap = YearRecap.compute(games: [one, two, three], year: 2025, calendar: cal)
        check(recap.totalUnlocks == 4, "counts only that year's unlocks (4)")
        check(recap.perMonth[2] == 3 && recap.perMonth[10] == 1 && recap.perMonth.reduce(0, +) == 4, "unlocks per month")
        check(recap.busiestMonth == 2, "busiest month is March")
        check(recap.activeDays == 3 && recap.busiestDay?.count == 2, "active days and busiest day")
        check(recap.rarest?.gameName == "Two" && recap.rarest?.achievement.globalPercent == 0.8, "rarest unlock of the year")
        check(recap.rareCount == 2, "rare (<10%) this year")
        check(recap.finishedGames == ["One"], "only games whose last unlock fell in the year count as finished")
        check(recap.topGames.first?.name == "One" && recap.topGames.first?.unlocks == 3, "most active game")
        check(YearRecap.availableYears(games: [one, two, three], calendar: cal) == [2025, 2024], "years with activity, newest first")
        let empty = YearRecap.compute(games: [one], year: 2019, calendar: cal)
        check(empty.totalUnlocks == 0 && empty.rarest == nil && empty.busiestMonth == nil && empty.finishedGames.isEmpty, "an empty year is handled")
    }
    
    // ===== Friend alerts
    print("Friend watch")
    do {
        func entry(_ n: String, _ key: Int, _ pct: Double?, archived: Bool = false) -> CatalogEntry {
            CatalogEntry(apiName: n, displayName: n, description: "", iconUrl: nil, grayIconUrl: nil, isHidden: false, percent: pct, groupId: 0, isArchived: archived, internalKey: key)
        }
        let entries = [entry("a", 1, 60), entry("b", 2, 3.0), entry("c", 3, 0.5), entry("old", 4, 1, archived: true)]
        func rows(_ keys: [Int]) -> [UserAchievementRow] { [1, 2, 3, 4].map { UserAchievementRow(internalKey: $0, unlocked: keys.contains($0)) } }
        func run(_ prev: Set<Int>?, _ now: [Int]) -> (alerts: [FriendAlert], unlocked: Set<Int>) {
            FriendWatch.alerts(friendId: "f", friendName: "Fox", appId: 9, gameName: "Game", previous: prev, rows: rows(now), entries: entries)
        }
        check(run(nil, [1, 2]).alerts.isEmpty && run(nil, [1, 2]).unlocked == [1, 2], "first look is a baseline, no alerts")
        check(run([1], [1]).alerts.isEmpty, "nothing new, nothing said")
        check(run([1], [1, 2]).alerts.map { $0.kind } == [.rare], "a new rare unlock is reported")
        check(run([1], [1, 2]).alerts.first?.text.contains("Fox unlocked b in Game") == true, "alert text names the friend, achievement and game")
        check(run([], [1]).alerts.isEmpty, "a common unlock is not news")
        let fin = run([1, 2], [1, 2, 3])
        check(fin.alerts.map { $0.kind }.sorted { $0.rawValue < $1.rawValue } == [.finished, .rare], "finishing the game (archived ones ignored) and its rare last unlock")
        check(run([1, 2, 3], [1, 2, 3]).alerts.isEmpty, "an already finished game does not alert again")
        check(FriendWatch.gamesToCheck(friendGameId: 5, lastSeen: [5, 6, 7, 8, 9], owned: [5, 7, 9, 10]) == [5, 7, 9], "only owned games, current one first, at most 3")
        check(FriendWatch.gamesToCheck(friendGameId: nil, lastSeen: [], owned: [1]).isEmpty, "idle friend with no history: nothing to check")
    }
    
    // ===== DLC ownership from Steam's own answer
    print("DLC ownership")
    do {
        let ref = FetchRef(target: "x", vanity: nil, steamId64: "76561198000000001", steamId: "76561198000000001")
        let catalog = json(["response": ["groups": [["groupid": 0, "localized_name": "", "dlcappid": 0], ["groupid": 1, "localized_name": "Pale Reach", "dlcappid": 2561440], ["groupid": 2, "localized_name": "Iron Rig", "dlcappid": 2561450]],
                                         "achievements": [["internal_name": "B1", "internal_key": 1, "localized_name": "Base 1", "groupid": 0], ["internal_name": "B2", "internal_key": 2, "localized_name": "Base 2", "groupid": 0],
                                                          ["internal_name": "D1", "internal_key": 3, "localized_name": "Pale 1", "groupid": 1], ["internal_name": "D2", "internal_key": 4, "localized_name": "Pale 2", "groupid": 1],
                                                          ["internal_name": "R1", "internal_key": 5, "localized_name": "Rig 1", "groupid": 2]]]])
        func run(appId: Int, playerGroups: [Int], rows: [[String: Any]], knownLocked: Bool = false) async -> (Int, SteamGame) {
            var calls = 0
            Stub.handler = { req in
                let u = req.url!.absoluteString
                if u.contains("GetGameAchievements") { return (200, [:], catalog) }
                if u.contains("GetUserAchievements") { calls += 1; return (200, [:], json(["response": ["achievements": rows, "groups": playerGroups.map { ["groupid": $0] }]])) }
                return (500, [:], Data())
            }
            MetadataCache.clearTestEntry(appId: appId)
            let o = await GameFetcher.fetch(appId: appId, ref: ref, apiKey: "", token: SteamAuth(accessToken: "T"), cookies: [], hadAchievementsBefore: false, health: SyncHealth(), knownLocked: knownLocked, api: api, community: SteamCommunityService(session: session))
            guard case .loaded(let ach, let groups, _, _, _) = o else { return (calls, SteamGame(appId: appId, name: "x")) }
            var g = SteamGame(appId: appId, name: "x", achievements: ach, hasAchievementsLoaded: true)
            g.achievementGroups = groups
            return (calls, g)
        }
        let b = 960_000_000 + Int.random(in: 0..<1000) * 10
        
        // owns one DLC (Pale Reach) but has unlocked nothing in it: the set must count anyway
        var (_, owned) = await run(appId: b + 1, playerGroups: [0, 1], rows: [["internal_key": 1, "unlocked": true, "unlock_time": 100]])
        check(owned.group(1)?.ownedByPlayer == true && owned.group(2)?.ownedByPlayer == false, "DLC sets Steam lists for the player are owned; the others are not")
        check(owned.totalAchievements == 4 && owned.unlockedAchievements == 1, "owned DLC counts toward completion with zero unlocks in it (4 of 5; the unowned Iron Rig is out)")
        
        // owns no DLC
        var (_, none) = await run(appId: b + 2, playerGroups: [0], rows: [["internal_key": 1, "unlocked": true, "unlock_time": 100]])
        check(none.totalAchievements == 2 && none.group(1)?.ownedByPlayer == false, "no DLC owned -> only the base game counts")
        
        // the user's own override still wins
        none.dlcOverrides = ["1": true]
        check(none.totalAchievements == 4, "'I own this DLC' overrides Steam's answer")
        
        // a base-game-only 0-unlock game is answered without a request, a game with DLC sets is always asked
        let (callsDlc, _) = await run(appId: b + 3, playerGroups: [0, 2], rows: [], knownLocked: true)
        check(callsDlc == 1, "a game with DLC sets is asked even when batch progress says 0 unlocked (ownership needs the player's answer)")
        
        // unowned DLC the player has unlocked achievements in (e.g. family sharing): Steam's answer decides, data stays consistent
        let heuristic = SteamGame(appId: 5, name: "old data", achievements: [
            Achievement(apiName: "D1", displayName: "D1", descriptionText: "", isUnlocked: true, groupId: 1),
            Achievement(apiName: "B1", displayName: "B1", descriptionText: "", isUnlocked: false, groupId: 0)], hasAchievementsLoaded: true)
        var h = heuristic; h.achievementGroups = [AchievementGroup(groupId: 0, name: ""), AchievementGroup(groupId: 1, name: "DLC", dlcAppId: 9)]
        check(h.isGroupAccessible(1), "without ownership data the old rule still applies (an unlock proves access)")
    }
    
    // ===== Activity feed windowing
    print("Activity windowing")
    do {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day0 = Date(timeIntervalSince1970: Double((1_700_000_000 / 86400) * 86400))   // a midnight (UTC)
        func ev(_ n: Int, dayOffset: Int, secondsIntoDay: Double) -> UnlockEvent {
            UnlockEvent(appId: n, gameName: "G\(n)", achievement: Achievement(apiName: "A\(n)", displayName: "A", descriptionText: "", unlockTimestamp: day0.addingTimeInterval(Double(dayOffset) * 86400 + secondsIntoDay)), detectedAt: day0, isSeen: true)
        }
        // days: 0 (25 events), -2 (3), -3 (1), -7 (4), -9 (2), -12 (1), -20 (6): 7 days with activity, 3 empty gaps
        var all: [UnlockEvent] = []; var n = 0
        for (d, c) in [(0, 25), (-2, 3), (-3, 1), (-7, 4), (-9, 2), (-12, 1), (-20, 6)] { for k in 0..<c { n += 1; all.append(ev(n, dayOffset: d, secondsIntoDay: Double(3600 + k * 60))) } }
        all.sort { $0.happenedAt > $1.happenedAt }
        
        let five = ActivityWindow.recentDays(from: all, maxDays: 5, calendar: cal)
        check(five.days.count == 5 && five.hasMore, "5 days with activity are returned, and there are earlier ones")
        check(five.days.map { $0.count } == [25, 3, 1, 4, 2], "empty days are skipped; each day keeps all of its events")
        check(five.days.first!.events.first!.happenedAt >= five.days.first!.events.last!.happenedAt, "events inside a day are newest first")
        check(five.days.first!.day == day0, "days are calendar days, newest first")
        
        let ten = ActivityWindow.recentDays(from: all, maxDays: 10, calendar: cal)
        check(ten.days.count == 7 && !ten.hasMore, "asking for more than exist returns everything, no 'more'")
        let exactly7 = ActivityWindow.recentDays(from: all, maxDays: 7, calendar: cal)
        check(exactly7.days.count == 7 && !exactly7.hasMore, "exactly all days: nothing earlier")
        let none = ActivityWindow.recentDays(from: [], maxDays: 5, calendar: cal)
        check(none.days.isEmpty && !none.hasMore, "empty feed")
        let one = ActivityWindow.recentDays(from: all, maxDays: 1, calendar: cal)
        check(one.days.count == 1 && one.days[0].count == 25 && one.hasMore, "one day only")
        check(Array(five.days[0].events.prefix(10)).count == 10 && five.days[0].count - 10 == 15, "a 25-unlock day shows 10 and offers '15 more'")
    }
    
    // ===== Which unlocks are "new"
    print("Unlock detection")
    do {
        func ach(_ n: Int, unlockedAt: [Int: TimeInterval]) -> [Achievement] {
            (0..<n).map { i in Achievement(apiName: "A\(i)", displayName: "A\(i)", descriptionText: "", isUnlocked: unlockedAt[i] != nil, unlockTimestamp: unlockedAt[i].map { Date(timeIntervalSince1970: $0) }) }
        }
        let t: TimeInterval = 1_700_000_000
        let lastSync = Date(timeIntervalSince1970: t)
        
        let before = SteamGame(appId: 1, name: "G", achievements: ach(10, unlockedAt: [0: t - 5000, 1: t - 4000, 2: t - 3000]), hasAchievementsLoaded: true)
        var new = UnlockDetector.newUnlocks(previous: before, fresh: ach(10, unlockedAt: [0: t - 5000, 1: t - 4000, 2: t - 3000, 3: t + 60]), previousSyncAt: lastSync)
        check(new.map { $0.apiName } == ["A3"], "with a baseline, the difference is new")
        
        let allLocked = SteamGame(appId: 2, name: "Unplayed", achievements: ach(10, unlockedAt: [:]), hasAchievementsLoaded: true)
        new = UnlockDetector.newUnlocks(previous: allLocked, fresh: ach(10, unlockedAt: Dictionary(uniqueKeysWithValues: (0..<6).map { ($0, t + Double($0) * 100) })), previousSyncAt: lastSync)
        check(new.count == 6, "first session of a game (6 unlocks, all after the last sync) -> all 6 are new (the old rule dropped them)")
        check(new.first?.apiName == "A5", "newest first")
        
        new = UnlockDetector.newUnlocks(previous: allLocked, fresh: ach(10, unlockedAt: Dictionary(uniqueKeysWithValues: (0..<6).map { ($0, t - 90_000 + Double($0)) })), previousSyncAt: lastSync)
        check(new.isEmpty, "a repaired/re-imported library (unlock times long before the last sync) -> nothing is new")
        
        new = UnlockDetector.newUnlocks(previous: nil, fresh: ach(5, unlockedAt: [0: t + 30, 1: t - 99_999]), previousSyncAt: lastSync)
        check(new.map { $0.apiName } == ["A0"], "a game added since the last sync: only unlocks made after that sync")
        
        new = UnlockDetector.newUnlocks(previous: nil, fresh: ach(5, unlockedAt: [0: t + 30]), previousSyncAt: nil)
        check(new.isEmpty, "the very first sync only sets a baseline")
        
        let empty = SteamGame(appId: 3, name: "Was empty", achievements: [], hasAchievementsLoaded: true)
        new = UnlockDetector.newUnlocks(previous: empty, fresh: ach(4, unlockedAt: [1: t + 10]), previousSyncAt: lastSync)
        check(new.map { $0.apiName } == ["A1"], "a game saved as empty by an old bug: by unlock time")
        
        new = UnlockDetector.newUnlocks(previous: before, fresh: ach(300, unlockedAt: Dictionary(uniqueKeysWithValues: (0..<250).map { ($0, t + 10) })), previousSyncAt: lastSync)
        check(new.isEmpty, "hundreds at once is a data import, not play")
        
        new = UnlockDetector.newUnlocks(previous: before, fresh: ach(10, unlockedAt: [0: t - 5000, 1: t - 4000, 2: t - 3000]), previousSyncAt: lastSync)
        check(new.isEmpty, "nothing changed -> nothing new")
    }
    
    // ===== Activity feed hygiene
    print("Activity feed")
    do {
        func ev(_ n: Int, at t: TimeInterval) -> UnlockEvent {
            UnlockEvent(appId: n, gameName: "G\(n)", achievement: Achievement(apiName: "A\(n)", displayName: "A", descriptionText: ""), detectedAt: Date(timeIntervalSince1970: 1_700_000_000 + t), isSeen: false)
        }
        let burst = (0..<300).map { ev($0, at: Double($0) * 0.03) }
        check(UnlockEvent.removingImportBursts(from: burst).isEmpty, "300 'unlocks' detected within 9 seconds are dropped (data import, not play)")
        let real = (0..<30).map { ev($0, at: Double($0) * 3600) }
        check(UnlockEvent.removingImportBursts(from: real).count == 30, "30 real unlocks spread over hours are kept")
        let mixed = real + (100..<200).map { ev($0, at: 200_000 + Double($0) * 0.05) }
        let cleaned = UnlockEvent.removingImportBursts(from: mixed)
        check(cleaned.count == 30 && cleaned.allSatisfy { $0.appId < 100 }, "a burst is removed while the real events around it stay")
        check(UnlockEvent.removingImportBursts(from: (0..<10).map { ev($0, at: 0) }).count == 10, "a handful of simultaneous unlocks (one game) is fine")
    }
    
    // ===== Secret store (replaces the Keychain, which prompted for the login password after each update)
    print("Secret store")
    do {
        let dir = tmp()
        let store = SecretStore(directory: dir, machineID: "MACHINE-A")
        check(store.read("k") == nil, "empty store reads nil")
        check(store.writeString("super-secret-key", account: "api") && store.readString("api") == "super-secret-key", "write + read")
        
        let blob = try! Data(contentsOf: dir.appendingPathComponent("secrets.bin"))
        check(!String(decoding: blob, as: UTF8.self).contains("super-secret-key") && !blob.isEmpty, "file contents are encrypted")
        let perms = (try! FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("secrets.bin").path)[.posixPermissions] as! NSNumber).intValue
        check(perms == 0o600, "secret file is owner-only (0600), got \(String(perms, radix: 8))")
        
        check(SecretStore(directory: dir, machineID: "MACHINE-A").readString("api") == "super-secret-key", "a new process on the same Mac can read it back")
        check(SecretStore(directory: dir, machineID: "MACHINE-B").readString("api") == nil, "a copy of the file is unreadable on a different Mac")
        
        check(store.writeString("second", account: "other") && store.readString("api") == "super-secret-key" && store.readString("other") == "second", "several secrets coexist")
        store.writeString(nil, account: "api")
        check(store.readString("api") == nil && store.readString("other") == "second", "delete removes only that secret")
        store.writeString("", account: "other")
        check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("secrets.bin").path), "storing nothing leaves no file behind")
        
        // tampering / corruption never crashes and never returns garbage
        store.writeString("x", account: "a")
        try! Data("corrupted".utf8).write(to: dir.appendingPathComponent("secrets.bin"))
        check(SecretStore(directory: dir, machineID: "MACHINE-A").readString("a") == nil, "corrupted file reads as empty")
        
        // no hardware id available -> per-install random key file, still round-trips
        let dir2 = tmp()
        let noHW = SecretStore(directory: dir2, machineID: nil)
        check(noHW.writeString("v", account: "a") && SecretStore(directory: dir2, machineID: nil).readString("a") == "v", "fallback random key works")
        
        // cookies
        let cookie = HTTPCookie(properties: [.name: "steamLoginSecure", .value: "abc", .domain: "steamcommunity.com", .path: "/", .secure: "TRUE", .expires: Date().addingTimeInterval(3600)])!
        let other = HTTPCookie(properties: [.name: "tracker", .value: "z", .domain: "example.com", .path: "/"])!
        let expired = HTTPCookie(properties: [.name: "old", .value: "q", .domain: "steamcommunity.com", .path: "/", .expires: Date().addingTimeInterval(-60)])!
        let cs = SecretStore(directory: tmp(), machineID: "M")
        cs.saveCookies([cookie, other, expired])
        let back = cs.loadCookies()
        check(back.count == 1 && back[0].name == "steamLoginSecure" && back[0].value == "abc" && back[0].isSecure, "only live Steam cookies are stored and restored")
        cs.saveCookies([])
        check(cs.loadCookies().isEmpty, "sign-out clears cookies")
    }
    
    // ===== Sign-in token / auth
    print("Sign-in token")
    do {
        func jwt(_ payload: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: payload)
            let b64 = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            return "eyJhbGciOiJFZERTQSJ9.\(b64).sig"
        }
        let future = Date().addingTimeInterval(3600).timeIntervalSince1970
        let token = SteamWebToken(jwt: jwt(["sub": "76561198000000001", "exp": future]))
        check(token != nil && token?.steamId == "76561198000000001" && token?.isFresh == true, "JWT: subject and expiry read from the payload")
        let expired = SteamWebToken(jwt: jwt(["sub": "1", "exp": Date().addingTimeInterval(-10).timeIntervalSince1970]))
        check(expired?.isFresh == false, "expired token is not fresh")
        let soon = SteamWebToken(jwt: jwt(["sub": "1", "exp": Date().addingTimeInterval(120).timeIntervalSince1970]))
        check(soon?.isFresh == false, "token about to expire (<5 min) is renewed early")
        check(SteamWebToken(jwt: "not-a-jwt") == nil && SteamWebToken(jwt: "a.b.c") == nil, "malformed tokens are rejected")
        
        let good = Data("{\"success\":1,\"data\":{\"webapi_token\":\"\(jwt(["sub": "7", "exp": future]))\"}}".utf8)
        check(SteamWebSession.parseToken(from: good)?.steamId == "7", "config response -> token")
        check(SteamWebSession.parseToken(from: Data("{\"success\":1,\"data\":[]}".utf8)) == nil, "signed-out response (data: []) -> no token")
        check(SteamWebSession.parseToken(from: Data("garbage".utf8)) == nil, "garbage response -> no token")
        
        check(SteamAuth(apiKey: "KEY", accessToken: "TOK").queryItems == ["key": "KEY"], "an API key wins over a token")
        check(SteamAuth(accessToken: "TOK").queryItems == ["access_token": "TOK"], "token-only auth uses access_token")
        check(SteamAuth(apiKey: "  ").queryItems.isEmpty, "blank key is no auth")
        check(SteamAuth.resolve(apiKey: "", token: expired) == nil, "expired token and no key -> no auth")
        check(SteamAuth.resolve(apiKey: "", token: token)?.accessToken == token?.value, "fresh token and no key -> token auth")
        
        // The service uses access_token on the wire, and refuses to call without credentials.
        Stub.requests = []
        Stub.handler = { _ in (200, [:], json(["response": ["game_count": 1, "games": [["appid": 10, "name": "Counter", "playtime_forever": 90]]]])) }
        let owned = try! await api.fetchOwnedGames(steamId: "1", auth: SteamAuth(accessToken: "TOK123"))
        check(owned.count == 1 && Stub.requests.last?.absoluteString.contains("access_token=TOK123") == true && Stub.requests.last?.absoluteString.contains("key=") == false, "owned games via access_token (no key= parameter)")
        do { _ = try await api.fetchOwnedGames(steamId: "1", auth: SteamAuth()); check(false, "should throw") }
        catch SteamAPIError.accessDenied { check(true, "no credentials -> accessDenied without a network call") }
        catch { check(false, "wrong error \(error)") }
    }
    
    // ===== Cached progress counts / Codable
    print("SteamGame counts")
    do {
        func A(_ n: String, _ unlocked: Bool, group: Int = 0) -> Achievement { Achievement(apiName: n, displayName: n, descriptionText: "", isUnlocked: unlocked, groupId: group) }
        var g = SteamGame(appId: 1, name: "G", achievements: [A("a", true), A("b", false)], hasAchievementsLoaded: true)
        check(g.totalAchievements == 2 && g.unlockedAchievements == 1, "counts at init")
        g.achievements[1].isUnlocked = true
        check(g.unlockedAchievements == 2 && g.isPerfect, "in-place mutation refreshes cached counts")
        g.achievements.append(A("c", false))
        check(g.totalAchievements == 3 && !g.isPerfect, "append refreshes cached counts")
        g.achievementGroups = [AchievementGroup(groupId: 0, name: ""), AchievementGroup(groupId: 1, name: "DLC", dlcAppId: 9)]
        g.achievements.append(A("d", false, group: 1))
        check(g.totalAchievements == 3, "DLC group without access is excluded from the cache")
        g.dlcOverrides = ["1": true]
        check(g.totalAchievements == 4, "override refreshes cached counts")
        let data = try! JSONEncoder.library.encode(g)
        let back = try! JSONDecoder.library.decode(SteamGame.self, from: data)
        check(back.totalAchievements == 4 && back.unlockedAchievements == 2 && back == g, "counts survive an encode/decode round trip")
        check(!(String(data: data, encoding: .utf8) ?? "").contains("cachedTotal"), "cache fields are not written to disk")
        // an old cache file (no new fields at all) still decodes
        let old = Data("{\"appId\":5,\"name\":\"Old\",\"playtimeMinutes\":3,\"achievements\":[],\"hasAchievementsLoaded\":false}".utf8)
        check((try? JSONDecoder.library.decode(SteamGame.self, from: old))?.name == "Old", "pre-update cache entries still decode")
    }
    
    // ===== Walkthrough links
    print("Walkthrough links")
    check(WalkthroughLinks.tsaSlug("Bitburner") == "Bitburner", "slug: simple")
    check(WalkthroughLinks.tsaSlug("Portal: Still Alive") == "Portal-Still-Alive", "slug: punctuation")
    check(WalkthroughLinks.tsaSlug("Marvel's Spider-Man Remastered™") == "Marvels-Spider-Man-Remastered", "slug: apostrophe, trademark")
    check(WalkthroughLinks.tsaSlug("Pokémon & Friends") == "Pokemon-and-Friends", "slug: accents and ampersand")
    check(WalkthroughLinks.tsaGameURL(gameName: "Bitburner")?.absoluteString == "https://truesteamachievements.com/game/Bitburner/walkthrough", "game walkthrough URL")
    check(WalkthroughLinks.tsaGameURL(gameName: "!!!") == nil, "no slug -> no URL")
    let q = WalkthroughLinks.tsaSearchURL(gameName: "Bitburner", achievement: "Hack it").absoluteString
    check(q.contains("site:truesteamachievements.com") && q.contains("Bitburner") && q.contains("Hack%20it"), "achievement search URL is encoded")
    print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
}

Task { await run() }
RunLoop.main.run()
