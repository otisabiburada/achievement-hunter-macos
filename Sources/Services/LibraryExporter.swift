import Foundation
import AppKit

public final class LibraryExporter {
    public static let shared = LibraryExporter()
    
    public func exportToMarkdown(games: [SteamGame], player: SteamPlayer?) -> String {
        var md = "# 🏆 Achievement Hunter - Games & Backlog Report\n\n"
        let playerName = player?.personaName ?? "Steam Hunter"
        md += "**Hunter:** \(playerName)  \n"
        md += "**Generated:** \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))  \n"
        
        let perfectCount = games.filter { $0.isPerfect }.count
        let totalUnlocked = games.reduce(0) { $0 + $1.unlockedAchievements }
        let totalAch = games.reduce(0) { $0 + $1.totalAchievements }
        let overallPct = totalAch > 0 ? (Double(totalUnlocked) / Double(totalAch)) * 100.0 : 0.0
        
        md += "**Total Games:** \(games.count) | **Perfect Games (100%):** \(perfectCount) | **Overall Completion:** \(Int(overallPct))% (\(totalUnlocked)/\(totalAch))\n\n"
        md += "---\n\n"
        
        md += "## 🎮 Games Library Summary\n\n"
        md += "| Game | Playtime | Progress | Unlocked | Completion % | Status |\n"
        md += "| :--- | :--- | :--- | :--- | :--- | :--- |\n"
        
        for g in games {
            let status = g.isPerfect ? "👑 100% Perfect" : (g.unlockedAchievements > 0 ? "⚡ In Progress" : "⏳ Unstarted")
            md += "| **\(g.name)** | \(g.playtimeHoursFormatted) | \(g.unlockedAchievements)/\(g.totalAchievements) | \(Int(g.completionPercentage))% | \(status) |\n"
        }
        
        md += "\n---\n\n"
        md += "## 🎯 Detailed Achievements Breakdown\n\n"
        
        for g in games where !g.trackableAchievements.isEmpty {
            md += "### \(g.name) (\(g.unlockedAchievements)/\(g.totalAchievements) • \(Int(g.completionPercentage))%)\n\n"
            for a in g.trackableAchievements {
                let check = a.isUnlocked ? "[x]" : "[ ]"
                let rarity = a.formattedRarity
                let unlockStr = a.formattedUnlockDate.map { " (Unlocked: \($0))" } ?? ""
                md += "- \(check) **\(a.displayName)** - \(a.descriptionText) `[\(rarity) rarity]`\(unlockStr)\n"
            }
            md += "\n"
        }
        
        md += "\n*Exported via Achievement Hunter for macOS*\n"
        return md
    }
    
    public func exportToCSV(games: [SteamGame]) -> String {
        var csv = "Game Title,App ID,Playtime (Hours),Unlocked Achievements,Total Achievements,Completion Percentage,Status\n"
        for g in games {
            let hours = String(format: "%.1f", Double(g.playtimeMinutes) / 60.0)
            let status = g.isPerfect ? "100% Perfect" : (g.unlockedAchievements > 0 ? "In Progress" : "Unstarted")
            let escapedName = "\"\(g.name.replacingOccurrences(of: "\"", with: "\"\""))\""
            csv += "\(escapedName),\(g.appId),\(hours),\(g.unlockedAchievements),\(g.totalAchievements),\(Int(g.completionPercentage))%,\(status)\n"
        }
        return csv
    }
    
    public func saveExportFile(content: String, filename: String, ext: String) -> URL? {
        let fileManager = FileManager.default
        let downloadsUrl = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destination = downloadsUrl.appendingPathComponent("\(filename).\(ext)")
        
        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            return destination
        } catch {
            return nil
        }
    }
}
