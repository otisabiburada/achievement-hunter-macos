import SwiftUI

public struct AnalyticsView: View {
    @ObservedObject var state: AppState
    
    private var unlockedAchievements: [Achievement] {
        state.unlockedItems.map { $0.achievement }
    }
    
    private var totalPlaytimeHours: Double {
        Double(state.visibleGames.reduce(0) { $0 + $1.playtimeMinutes }) / 60.0
    }
    
    private var unlocksPerHour: Double {
        guard totalPlaytimeHours > 0 else { return 0.0 }
        return Double(unlockedAchievements.count) / totalPlaytimeHours
    }
    
    // Rarity Breakdown
    private var rarityCounts: [RarityTier: Int] {
        var counts: [RarityTier: Int] = [:]
        for t in RarityTier.allCases { counts[t] = 0 }
        for ach in unlockedAchievements {
            if let tier = ach.rarityTier {
                counts[tier, default: 0] += 1
            } else {
                counts[.common, default: 0] += 1
            }
        }
        return counts
    }
    
    // Milestone badges
    private var milestones: [(name: String, target: Int, icon: String, color: Color)] {
        [
            ("Novice Hunter", 1, "trophy", .brown),
            ("Skilled Completionist", 5, "trophy.fill", .gray),
            ("Master Perfectionist", 10, "trophy.fill", Color(red: 1.0, green: 0.82, blue: 0.2)),
            ("Elite Hunter", 25, "diamond.fill", Color.cyan),
            ("Legendary God", 50, "crown.fill", Color(red: 1.0, green: 0.4, blue: 0.8))
        ]
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        Text("Analytics & Perfectionist Stats")
                            .font(.system(size: 24, weight: .bold))
                    }
                    Text("Deep metrics on your Steam achievement hunting velocity, consistency, and milestones.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                // 1. Activity Heatmap
                HeatmapView(counts: state.unlockCountsByDay, totalUnlocked: state.unlockedItems.count)
                
                // 2. Efficiency & Key Metrics Grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("EFFICIENCY & SPEED METRICS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(
                            title: "Unlocks / Hour",
                            value: String(format: "%.2f", unlocksPerHour),
                            subtitle: "Pace of unlocking",
                            icon: "speedometer",
                            color: .cyan
                        )
                        MetricCard(
                            title: "Total Playtime",
                            value: String(format: "%.0f hrs", totalPlaytimeHours),
                            subtitle: "\(state.visibleGames.count) games tracked",
                            icon: "clock.fill",
                            color: .blue
                        )
                        MetricCard(
                            title: "Completion Rate",
                            value: "\(Int(state.overallCompletionPercentage))%",
                            subtitle: "\(state.totalUnlockedCount)/\(state.totalAchievementsCount) total",
                            icon: "chart.bar.fill",
                            color: .green
                        )
                        MetricCard(
                            title: "Perfect Games",
                            value: "\(state.perfectGamesCount)",
                            subtitle: "100% completed",
                            icon: "crown.fill",
                            color: Color(red: 1.0, green: 0.82, blue: 0.2)
                        )
                    }
                }
                
                // 3. Perfectionist Milestones Progress
                VStack(alignment: .leading, spacing: 14) {
                    Text("PERFECTIONIST MILESTONES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 10) {
                        ForEach(milestones, id: \.target) { m in
                            let isAchieved = state.perfectGamesCount >= m.target
                            let progress = min(1.0, Double(state.perfectGamesCount) / Double(m.target))
                            
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(isAchieved ? m.color.opacity(0.2) : Color.primary.opacity(0.05))
                                        .frame(width: 42, height: 42)
                                    Image(systemName: m.icon)
                                        .font(.system(size: 18))
                                        .foregroundColor(isAchieved ? m.color : .secondary.opacity(0.5))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(m.name)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(isAchieved ? .primary : .secondary)
                                        
                                        Spacer()
                                        
                                        if isAchieved {
                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark.circle.fill")
                                                Text("UNLOCKED")
                                            }
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.green)
                                        } else {
                                            Text("\(state.perfectGamesCount) / \(m.target) Games")
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    CustomProgressBar(
                                        value: progress * 100.0,
                                        height: 4,
                                        isPerfect: isAchieved
                                    )
                                }
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                            .cornerRadius(10)
                        }
                    }
                }
                
                // 4. Rarity Tier Breakdown
                VStack(alignment: .leading, spacing: 12) {
                    Text("UNLOCKED RARITY DISTRIBUTION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        ForEach(RarityTier.allCases, id: \.self) { tier in
                            let count = rarityCounts[tier] ?? 0
                            VStack(spacing: 6) {
                                Image(systemName: tier.iconName)
                                    .foregroundColor(tier.color)
                                    .font(.system(size: 16))
                                Text("\(count)")
                                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                                Text(tier.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 13))
            }
            
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
            
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(12)
    }
}
