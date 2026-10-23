import SwiftUI

public struct DailyUnlockCount: Identifiable {
    public var id: String { dateKey }
    public let date: Date
    public let dateKey: String
    public let count: Int
}

public struct HeatmapView: View {
    public let dateCountMap: [String: Int]
    public let totalUnlocked: Int
    @State private var hoveredDay: DailyUnlockCount? = nil
    
    /// `counts`: unlocks per day ("yyyy-MM-dd"), built once by the app state. (This view used to rebuild that map from
    /// every achievement of the library for each of the 364 days, on every redraw.)
    public init(counts: [String: Int], totalUnlocked: Int) {
        self.dateCountMap = counts
        self.totalUnlocked = totalUnlocked
    }
    
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    // 52 weeks of dates ending today
    private var calendarDays: [[DailyUnlockCount]] {
        let calendar = Calendar.current
        let today = Date()
        let formatter = Self.keyFormatter
        
        // 52 weeks * 7 days = 364 days
        var weeks: [[DailyUnlockCount]] = []
        var currentWeek: [DailyUnlockCount] = []
        
        for dayOffset in (0..<364).reversed() {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
                let key = formatter.string(from: date)
                let count = dateCountMap[key] ?? 0
                currentWeek.append(DailyUnlockCount(date: date, dateKey: key, count: count))
                
                if currentWeek.count == 7 {
                    weeks.append(currentWeek)
                    currentWeek = []
                }
            }
        }
        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }
        return weeks
    }
    
    // Current streak
    private var currentStreak: Int {
        let calendar = Calendar.current
        let today = Date()
        let formatter = Self.keyFormatter
        
        var streak = 0
        var checkDate = today
        
        while streak < 4000 {
            let key = formatter.string(from: checkDate)
            if (dateCountMap[key] ?? 0) > 0 {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            } else {
                // If today has 0, check if yesterday had streak
                if streak == 0, let yesterday = calendar.date(byAdding: .day, value: -1, to: today), (dateCountMap[formatter.string(from: yesterday)] ?? 0) > 0 {
                    checkDate = yesterday
                    continue
                }
                break
            }
        }
        return max(streak, (dateCountMap[formatter.string(from: today)] ?? 0) > 0 ? 1 : 0)
    }
    
    private func colorForCount(_ count: Int) -> Color {
        switch count {
        case 0:
            return Color.primary.opacity(0.06)
        case 1:
            return Color.green.opacity(0.4)
        case 2:
            return Color.green.opacity(0.65)
        case 3:
            return Color.green.opacity(0.85)
        default:
            return Color.green
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header stats
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UNLOCK ACTIVITY HEATMAP")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("\(totalUnlocked) Total Achievements")
                        .font(.system(size: 16, weight: .bold))
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(currentStreak) Days")
                                .font(.system(size: 13, weight: .bold))
                            Text("Current Streak")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(dateCountMap.keys.count) Active Days")
                                .font(.system(size: 13, weight: .bold))
                            Text("Past Year")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Heatmap grid (horizontal scrolling)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(calendarDays.indices, id: \.self) { weekIndex in
                        VStack(spacing: 3) {
                            ForEach(calendarDays[weekIndex]) { day in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorForCount(day.count))
                                    .frame(width: 10, height: 10)
                                    .onHover { isHovering in
                                        if isHovering {
                                            hoveredDay = day
                                        } else if hoveredDay?.id == day.id {
                                            hoveredDay = nil
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Footer & Legend
            HStack {
                if let hovered = hoveredDay {
                    Text("\(hovered.count) unlocks on \(hovered.dateKey)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                } else {
                    Text("Hover over squares to inspect daily unlock frequency")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("Less")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    ForEach([0, 1, 2, 3, 5], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorForCount(level))
                            .frame(width: 8, height: 8)
                    }
                    Text("More")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
}
