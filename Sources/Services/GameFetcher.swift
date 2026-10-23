import Foundation

/// Which account a sync is for.
public struct FetchRef: Sendable {
    public let target: String
    public let vanity: String?
    public let steamId64: String?
    public let steamId: String
    
    public init(target: String, vanity: String?, steamId64: String?, steamId: String) {
        self.target = target
        self.vanity = vanity
        self.steamId64 = steamId64
        self.steamId = steamId
    }
}

public enum GameFetchOutcome: Sendable {
    /// `verified` is false when the player's own unlocks couldn't be read (private data): the list is then the
    /// catalog with everything locked, and the game is re-checked on the next sync.
    case loaded(achievements: [Achievement], groups: [AchievementGroup], name: String?, logo: String?, verified: Bool)
    case failed(String)
    case cancelled
}

public enum GameFetcher {
    /// Fetches one game.
    /// 1. Steam's public catalog (no key): names, icons, rarity and Achievement Sets. If it says the game has
    ///    no achievements we stop right here (one cheap request), unless we previously saw achievements.
    /// 2. The player's unlock state: Web API first (if a key is set), then the community pages.
    ///
    /// Important: "the player source returned nothing" is NOT the same as "the game has no achievements". Steam's
    /// stats pages answer "no stats" for a game you own but never played, and refuse private profiles. In both cases
    /// the game still has achievements (all locked as far as we can tell), so the catalog is used to list them.
    public static func fetch(
        appId: Int,
        ref: FetchRef,
        apiKey: String,
        token: SteamAuth? = nil,
        cookies: [HTTPCookie],
        hadAchievementsBefore: Bool,
        health: SyncHealth,
        knownLocked: Bool = false,
        previousUnlocked: Int = 0,
        api: SteamAPIService = .shared,
        community: SteamCommunityService = .shared
    ) async -> GameFetchOutcome {
        var catalog: AchievementCatalog?          // non-empty catalog, used to build lists
        var fetchedCatalog: AchievementCatalog?   // whatever Steam answered (possibly empty); nil if the request failed
        do {
            let fetched = try await api.fetchCatalog(appId: appId)
            fetchedCatalog = fetched
            if fetched.isEmpty && !hadAchievementsBefore {
                return .loaded(achievements: [], groups: [], name: nil, logo: nil, verified: true)
            }
            if !fetched.isEmpty { catalog = fetched }
        } catch is CancellationError {
            return .cancelled
        } catch SteamAPIError.rateLimited {
            return .failed(SteamAPIError.rateLimited.localizedDescription)
        } catch {
            // catalog unavailable: the player sources below can still produce a (less detailed) result
        }
        var groups: [AchievementGroup] { catalog?.groups ?? [] }
        
        /// Turns "nothing from the player source" into the right result.
        func resolveEmpty(name: String?, logo: String?, verified: Bool) -> GameFetchOutcome {
            switch EmptyPlayerResult.resolve(catalog: fetchedCatalog) {
            case .lockedFromCatalog:
                let locked = AchievementMerger.merge(rows: [], catalog: catalog, appId: appId, gameName: name)
                return .loaded(achievements: locked, groups: groups, name: name, logo: logo, verified: verified)
            case .noAchievements:
                return .loaded(achievements: [], groups: groups, name: name, logo: logo, verified: true)
            case .unknown:
                return .failed("Steam didn't say whether this game has achievements. It will be retried.")
            }
        }
        
        // Already known (batch progress says 0 unlocked): the catalog alone is the answer, no per-game request.
        // (Games with DLC sets are always asked: only the player's own answer says which DLC they own.)
        if knownLocked, let known = catalog, !known.hasDLCSets {
            return resolveEmpty(name: nil, logo: nil, verified: true)
        }
        
        // 1. Signed in (no API key): Steam's own player endpoint, authorised by the sign-in token. It is what Steam's
        //    achievements page uses, is far lighter than the old stats pages, and shows the owner private data too.
        if apiKey.isEmpty, let token = token, !token.queryItems.isEmpty, let cat = catalog {
            do {
                var activeCatalog = cat
                let answer = try await api.fetchUserAchievementsDetailed(steamId: ref.steamId, appId: appId, auth: token)
                var rows = answer.rows
                var mapped = activeCatalog.playerRows(from: rows)
                if mapped == nil {
                    // A cached catalog from an older version lacks the numeric keys: fetch a fresh one once.
                    if let fresh = try? await api.fetchCatalog(appId: appId, force: true) {
                        activeCatalog = fresh
                        catalog = fresh
                        mapped = fresh.playerRows(from: rows)
                    }
                }
                if let mapped = mapped {
                    rows = []
                    let ach = AchievementMerger.merge(rows: mapped, catalog: activeCatalog, appId: appId)
                    health.recordSuccess()
                    return .loaded(achievements: ach, groups: activeCatalog.groups(markingOwnedBy: answer.accessibleGroupIds), name: nil, logo: nil, verified: true)
                }
            } catch is CancellationError {
                return .cancelled
            } catch SteamAPIError.rateLimited {
                return .failed(SteamAPIError.rateLimited.localizedDescription)
            } catch {
                // fall through to the older sources below
            }
        }
        
        // 2. The user's own API key (explicit privacy errors, works without the sign-in).
        if !apiKey.isEmpty {
            do {
                let ach = try await api.fetchAchievementsForGame(appId: appId, steamId: ref.steamId, apiKey: apiKey, catalog: catalog)
                if ach.isEmpty { return resolveEmpty(name: nil, logo: nil, verified: true) }
                health.recordSuccess()
                return .loaded(achievements: ach, groups: groups, name: nil, logo: nil, verified: true)
            } catch is CancellationError {
                return .cancelled
            } catch SteamAPIError.noAchievements {
                // "Requested app has no stats": for this player. The game itself may well have achievements.
                return resolveEmpty(name: nil, logo: nil, verified: true)
            } catch SteamAPIError.rateLimited {
                return .failed(SteamAPIError.rateLimited.localizedDescription)
            } catch {
                // privacy / key problems: fall through to the community pages
            }
        }
        
        if health.communityBlocked, catalog != nil, previousUnlocked == 0 {
            // This profile's achievements are private and we have no sign-in: stop asking Steam for each game.
            health.recordPrivate()
            return resolveEmpty(name: nil, logo: nil, verified: false)
        }
        
        do {
            let (ach, name, logo) = try await community.fetchAchievementsForGame(
                target: ref.target,
                vanitySlug: ref.vanity,
                steamId64: ref.steamId64,
                appId: appId,
                cookies: cookies,
                catalog: catalog
            )
            // The community pages can answer with an unrelated HTML page instead of data. When that would erase unlocks
            // we already have, keep the saved ones and retry later instead of trusting it.
            if previousUnlocked > 0 && !ach.contains(where: { $0.isUnlocked }) {
                return .failed("Steam returned no unlock data this time. Your saved unlocks were kept; it will be retried.")
            }
            if ach.isEmpty { return resolveEmpty(name: name, logo: logo, verified: true) }
            health.recordSuccess()
            return .loaded(achievements: ach, groups: groups, name: name, logo: logo, verified: true)
        } catch is CancellationError {
            return .cancelled
        } catch SteamAPIError.privateProfile {
            health.recordPrivate()
            if previousUnlocked > 0 { return .failed("This game's achievements couldn't be read this time. Your saved unlocks were kept.") }
            if catalog != nil { return resolveEmpty(name: nil, logo: nil, verified: false) }
            return .failed(SteamAPIError.privateProfile.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
