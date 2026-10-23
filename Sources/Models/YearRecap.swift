import Foundation

/// "Your year": what you unlocked in one calendar year. Pure logic over the library.
public struct YearRecap: Sendable {
    public struct TopGame: Sendable { public let name: String; public let appId: Int; public let unlocks: Int }
    public struct Rarest: Sendable { public let achievement: Achievement; public let gameName: String }
    
    public let year: Int
    public let totalUnlocks: Int
    public let perMonth: [Int]               // 12 entries, January first
    public let activeDays: Int
    public let busiestDay: (date: Date, count: Int)?
    public let rarest: Rarest?
    public let rareCount: Int                // unlocked this year held by < 10% of players
    public let finishedGames: [String]       // games whose last achievement fell in this year
    public let topGames: [TopGame]
    
    public var busiestMonth: Int? {
        guard let m = perMonth.max(), m > 0 else { return nil }
        return perMonth.firstIndex(of: m)
    }
    
    /// Years that have at least one dated unlock, newest first.
    public static func availableYears(games: [SteamGame], calendar: Calendar = .current) -> [Int] {
        var years = Set<Int>()
        for g in games { for a in g.achievements { if a.isUnlocked, let t = a.unlockTimestamp { years.insert(calendar.component(.year, from: t)) } } }
        return years.sorted(by: >)
    }
    
    public static func compute(games: [SteamGame], year: Int, calendar: Calendar = .current) -> YearRecap {
        var perMonth = Array(repeating: 0, count: 12)
        var perDay: [Date: Int] = [:]
        var rarest: Rarest?
        var rareCount = 0
        var finished: [(String, Date)] = []
        var top: [TopGame] = []
        var total = 0
        for g in games where g.totalAchievements > 0 {
            var inYear = 0
            for a in g.achievements where a.isUnlocked {
                guard let t = a.unlockTimestamp, calendar.component(.year, from: t) == year else { continue }
                inYear += 1
                perMonth[calendar.component(.month, from: t) - 1] += 1
                perDay[calendar.startOfDay(for: t), default: 0] += 1
                if let p = a.globalPercent {
                    if p < 10 { rareCount += 1 }
                    if p < (rarest?.achievement.globalPercent ?? .infinity) { rarest = Rarest(achievement: a, gameName: g.name) }
                }
            }
            total += inYear
            if inYear > 0 { top.append(TopGame(name: g.name, appId: g.appId, unlocks: inYear)) }
            if g.isPerfect, let last = g.achievements.compactMap({ $0.unlockTimestamp }).max(), calendar.component(.year, from: last) == year {
                finished.append((g.name, last))
            }
        }
        let busiest = perDay.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { (date: $0.key, count: $0.value) }
        return YearRecap(
            year: year, totalUnlocks: total, perMonth: perMonth, activeDays: perDay.count, busiestDay: busiest,
            rarest: rarest, rareCount: rareCount,
            finishedGames: finished.sorted { $0.1 < $1.1 }.map { $0.0 },
            topGames: Array(top.sorted { ($0.unlocks, $1.name) > ($1.unlocks, $0.name) }.prefix(3))
        )
    }
}
