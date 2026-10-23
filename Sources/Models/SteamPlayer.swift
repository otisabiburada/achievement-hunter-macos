import Foundation

public struct SteamPlayer: Identifiable, Hashable, Codable, Sendable {
    public var id: String { steamId }
    public let steamId: String
    public let personaName: String
    public let avatarUrl: String?
    public let profileUrl: String?
    public let personaState: Int
    public var currentGameId: Int?
    public var currentGameName: String?
    
    public init(
        steamId: String,
        personaName: String,
        avatarUrl: String? = nil,
        profileUrl: String? = nil,
        personaState: Int = 1,
        currentGameId: Int? = nil,
        currentGameName: String? = nil
    ) {
        self.steamId = steamId
        self.personaName = personaName
        self.avatarUrl = avatarUrl
        self.profileUrl = profileUrl
        self.personaState = personaState
        self.currentGameId = currentGameId
        self.currentGameName = currentGameName
    }
    
    public var isInGame: Bool {
        if let name = currentGameName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let id = currentGameId, id > 0 {
            return true
        }
        return false
    }
    
    public var avatarImageURL: URL? {
        guard let avatarUrl = avatarUrl else { return nil }
        return URL(string: avatarUrl)
    }
    
    public var statusText: String {
        if isInGame {
            return "Playing \(currentGameName ?? "Game")"
        }
        switch personaState {
        case 1:
            return "Online"
        case 2:
            return "Busy"
        case 3:
            return "Away"
        case 4:
            return "Snooze"
        case 5:
            return "Looking to Trade"
        case 6:
            return "Looking to Play"
        default:
            return "Offline"
        }
    }
}

extension SteamPlayer {
    /// Combines what the Web API and the public profile page say about the same player. Either one can lag or be
    /// limited (a sign-in token may see less than a key; the page may lack details), so "playing a game" or
    /// "online" from either source counts, and the API's richer fields win otherwise.
    public static func merge(api: SteamPlayer?, community: SteamPlayer?) -> SteamPlayer? {
        guard let base = api ?? community else { return nil }
        let gameId = api?.currentGameId ?? community?.currentGameId
        let gameName = api?.currentGameName ?? community?.currentGameName
        let state = max(api?.personaState ?? 0, community?.personaState ?? 0)
        return SteamPlayer(
            steamId: base.steamId,
            personaName: base.personaName,
            avatarUrl: api?.avatarUrl ?? community?.avatarUrl,
            profileUrl: api?.profileUrl ?? community?.profileUrl,
            personaState: state,
            currentGameId: gameId,
            currentGameName: gameName
        )
    }
}

/// Steam's status sources flicker: the live card can report "online, no game" for a moment while a game is still
/// running (loading screens, overlays, a Steam hiccup). Leaving a game is only believed after a grace period;
/// entering or switching games is immediate.
public struct GameStatusDebouncer {
    public var graceSeconds: TimeInterval
    private var lastSeenInGame: Date?
    
    public init(graceSeconds: TimeInterval = 60) {
        self.graceSeconds = graceSeconds
    }
    
    public mutating func resolve(observed: SteamPlayer, previous: SteamPlayer?, now: Date = Date()) -> SteamPlayer {
        if observed.isInGame {
            lastSeenInGame = now
            return observed
        }
        if let previous = previous, previous.isInGame, let seen = lastSeenInGame, now.timeIntervalSince(seen) < graceSeconds {
            // keep the running game for now, but take everything else from the fresh answer
            return SteamPlayer.merge(api: observed, community: previous) ?? observed
        }
        return observed
    }
}
