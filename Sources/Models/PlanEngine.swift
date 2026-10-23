import Foundation

/// One locked achievement worth going for, with the game it belongs to.
public struct QuickWin: Identifiable, Sendable {
    public let appId: Int
    public let gameName: String
    public let achievement: Achievement
    /// The game has been played (playtime or an unlock): its wins are closer than those of a game never opened.
    public let gameStarted: Bool
    public var id: String { "\(appId)-\(achievement.apiName)" }
    public var percent: Double { achievement.globalPercent ?? 0 }
}

/// Today's suggestion: one game worth finishing and the achievements to start with.
public struct DailyPlan: Sendable {
    public let game: SteamGame
    public let remaining: Int
    public let estimatedHours: Double?
    public let picks: [Achievement]
}

/// Pure planning logic for "what should I unlock next". Everything is derived from data already in the library.
public enum PlanEngine {
    /// Rough hours left to finish a game: your own pace (hours played per unlocked achievement) times what remains.
    /// Only given when there is enough history to mean something; it is an estimate, not a promise.
    public static func hoursLeft(for game: SteamGame) -> Double? {
        guard game.playtimeIsKnown != false else { return nil }
        let hours = Double(game.playtimeMinutes) / 60
        let unlocked = game.unlockedAchievements
        let remaining = game.lockedAchievements
        guard remaining > 0, unlocked >= 3, hours >= 1 else { return nil }
        let estimate = hours / Double(unlocked) * Double(remaining)
        return min(max(estimate, 0.25), 500)
    }
    
    public static func hoursText(_ hours: Double) -> String {
        if hours < 1 { return "under 1 hour" }
        if hours < 10 { return String(format: "about %.1f hours", hours) }
        return "about \(Int(hours.rounded())) hours"
    }
    
    /// The easiest locked achievements across the library: the ones most players have. At most `perGameCap` per game, so one
    /// game with hundreds of easy achievements doesn't fill the list. Hidden ones are skipped (their description is a secret).
    public static func quickWins(games: [SteamGame], limit: Int = 200, perGameCap: Int = 3) -> [QuickWin] {
        var wins: [QuickWin] = []
        for game in games where game.totalAchievements > 0 && !game.isPerfect {
            let started = game.playtimeMinutes > 0 || game.unlockedAchievements > 0
            let easiest = game.achievements
                .filter { !$0.isUnlocked && !$0.isHidden && $0.globalPercent != nil && game.countsTowardCompletion($0) && game.isGroupAccessible($0.groupId) }
                .sorted { ($0.globalPercent ?? 0) > ($1.globalPercent ?? 0) }
                .prefix(perGameCap)
            for achievement in easiest {
                wins.append(QuickWin(appId: game.appId, gameName: game.name, achievement: achievement, gameStarted: started))
            }
        }
        wins.sort { $0.percent > $1.percent }
        return Array(wins.prefix(limit))
    }
    
    /// One game to finish today, the same all day and different tomorrow. Candidates are games that are well underway
    /// but not nearly done by luck: 30% or more finished, 1 to 30 achievements left. The closest ones come first and
    /// the day number rotates through the best few.
    public static func dailyPlan(games: [SteamGame], on date: Date = Date(), calendar: Calendar = .current) -> DailyPlan? {
        let candidates = games
            .filter { $0.totalAchievements > 0 && !$0.isPerfect && $0.completionPercentage >= 30 && (1...30).contains($0.lockedAchievements) }
            .map { ($0, $0.completionPercentage - Double($0.lockedAchievements) * 0.7) }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map { $0.0 }
        guard !candidates.isEmpty else { return nil }
        let dayNumber = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let game = candidates[dayNumber % candidates.count]
        let picks = game.achievements
            .filter { !$0.isUnlocked && game.countsTowardCompletion($0) && game.isGroupAccessible($0.groupId) }
            .sorted { (!$0.isHidden ? 1 : 0, $0.globalPercent ?? 0) > (!$1.isHidden ? 1 : 0, $1.globalPercent ?? 0) }
            .prefix(3)
        return DailyPlan(game: game, remaining: game.lockedAchievements, estimatedHours: hoursLeft(for: game), picks: Array(picks))
    }
}
