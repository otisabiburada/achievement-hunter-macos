import SwiftUI
import AppKit

public struct WidgetStudioView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var floatingManager = FloatingWidgetManager.shared
    @State private var selectedWidgetType: Int = 0
    @State private var selectedWallpaper: Int = 0
    
    private let wallpapers: [(name: String, colors: [Color])] = [
        ("Cosmic Midnight", [Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.03, green: 0.04, blue: 0.08)]),
        ("Ventura Sunset", [Color(red: 0.35, green: 0.12, blue: 0.18), Color(red: 0.12, green: 0.06, blue: 0.16)]),
        ("Sonoma Aurora", [Color(red: 0.06, green: 0.22, blue: 0.18), Color(red: 0.02, green: 0.08, blue: 0.12)]),
        ("Cyberpunk Steam", [Color(red: 0.05, green: 0.15, blue: 0.28), Color(red: 0.18, green: 0.05, blue: 0.22)]),
        ("Pure Minimalist", [Color(red: 0.07, green: 0.08, blue: 0.11), Color(red: 0.03, green: 0.03, blue: 0.05)])
    ]
    
    public init(state: AppState) {
        self.state = state
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.3.group.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.purple)
                            Text("macOS Desktop & Lock Screen Widgets Studio")
                                .font(.system(size: 24, weight: .bold))
                        }
                        Text("Configure, customize, and float live desktop & lock screen widgets for your Steam achievements.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Pin to macOS Desktop Button
                    Button(action: {
                        floatingManager.toggle(widgetType: selectedWidgetType, state: state)
                    }) {
                        HStack(spacing: 7) {
                            Image(systemName: floatingManager.isVisible ? "xmark.circle.fill" : "macwindow.on.rectangle")
                                .font(.system(size: 13, weight: .semibold))
                            Text(floatingManager.isVisible ? "Dismiss Desktop Widget" : "Pin Live to macOS Desktop")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(floatingManager.isVisible ? Color.red.opacity(0.18) : Color.accentColor)
                        .foregroundColor(floatingManager.isVisible ? .red : .white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(floatingManager.isVisible ? Color.red.opacity(0.4) : Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Widget Style Segmented Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("CHOOSE WIDGET PRESET")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<widgetCatalog.count, id: \.self) { idx in
                                let item = widgetCatalog[idx]
                                Button(action: {
                                    selectedWidgetType = idx
                                    if floatingManager.isVisible {
                                        floatingManager.show(widgetType: idx, state: state)
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: item.icon)
                                            .foregroundColor(selectedWidgetType == idx ? .white : item.color)
                                            .font(.system(size: 12))
                                        Text(item.title)
                                            .font(.system(size: 12, weight: selectedWidgetType == idx ? .bold : .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selectedWidgetType == idx ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.6))
                                    .foregroundColor(selectedWidgetType == idx ? .white : .primary)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(selectedWidgetType == idx ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Widget Preview Canvas (Simulating macOS Desktop Wallpaper)
                VStack(spacing: 12) {
                    HStack {
                        Text("DESKTOP WIDGET PREVIEW")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Wallpaper Selector
                        HStack(spacing: 6) {
                            Text("Wallpaper:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $selectedWallpaper) {
                                ForEach(0..<wallpapers.count, id: \.self) { i in
                                    Text(wallpapers[i].name).tag(i)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }
                    }
                    
                    ZStack {
                        // Simulated macOS wallpaper backdrop
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: wallpapers[selectedWallpaper].colors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 290)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 12, y: 6)
                        
                        // Active Live Widget Renderer
                        WidgetRendererView(widgetType: selectedWidgetType, state: state)
                            .transition(.scale.combined(with: .opacity))
                            .id(selectedWidgetType)
                    }
                }
                
                // Widget Descriptions & Features Gallery
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("ALL AVAILABLE WIDGET FORMATS (9 PRESETS)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("Click any widget to preview or detach")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(0..<widgetCatalog.count, id: \.self) { idx in
                            let item = widgetCatalog[idx]
                            WidgetFormatInfoCard(
                                title: item.title,
                                subtitle: item.subtitle,
                                description: item.description,
                                icon: item.icon,
                                color: item.color,
                                isSelected: selectedWidgetType == idx,
                                onSelect: {
                                    selectedWidgetType = idx
                                    if floatingManager.isVisible {
                                        floatingManager.show(widgetType: idx, state: state)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private var widgetCatalog: [(title: String, subtitle: String, description: String, icon: String, color: Color)] {
        [
            ("Rarest Trophy Showcase", "Medium Desktop", "Highlights your lowest-percentage unlocked achievement with glowing rarity tier badges.", "crown.fill", Color(red: 1.0, green: 0.82, blue: 0.2)),
            ("Perfectionist Streak", "Small / Circular", "Monitors your daily hunting consistency, perfect games count, and overall completion rate.", "flame.fill", .orange),
            ("Active Game Progress", "Medium Desktop", "Live gauge showing hours played, achievements left, and completion % for your current game.", "gamecontroller.fill", .blue),
            ("Road to 100% (Closer)", "Medium Desktop", "Tracks the game nearest to 100% and previews the exact locked trophies remaining.", "flag.checkered.2.crossed", Color(red: 1.0, green: 0.75, blue: 0.1)),
            ("Pinned Targets Grind", "Large Desktop", "Dedicated dashboard monitoring your pinned grinding targets across all games.", "pin.fill", Color(red: 1.0, green: 0.4, blue: 0.3)),
            ("Recent Trophy Triumph", "Medium Desktop", "Real-time spotlight celebrating your latest unlocked achievement and timestamp.", "sparkles", .cyan),
            ("Trophy Hall & Milestones", "Medium Desktop", "Hall of Fame trophy case with milestone progress toward the next perfectionist badge.", "trophy.fill", Color(red: 0.95, green: 0.75, blue: 0.2)),
            ("Hunter Velocity & Stats", "Medium Desktop", "Deep metrics showing unlocks per hour, total playtime, completion rate, and hunter rank.", "bolt.fill", Color(red: 0.2, green: 0.85, blue: 0.5)),
            ("Compact Lock Screen Glance", "Lock Screen Pill", "Ultra-minimalist horizontal status bar designed for macOS Lock Screen and Notification glance.", "lock.desktopcomputer", .purple)
        ]
    }
}

// MARK: - Universal Widget Renderer (Used in Studio & Floating Desktop Window)

public struct WidgetRendererView: View {
    public let widgetType: Int
    @ObservedObject public var state: AppState
    
    public init(widgetType: Int, state: AppState) {
        self.widgetType = widgetType
        self.state = state
    }
    
    public var body: some View {
        switch widgetType {
        case 0:
            RarestWidgetCard(state: state)
        case 1:
            StreakWidgetCard(state: state)
        case 2:
            GameProgressWidgetCard(game: state.selectedGame ?? state.games.first)
        case 3:
            RoadTo100WidgetCard(state: state)
        case 4:
            PinnedTargetsWidgetCard(state: state)
        case 5:
            RecentTriumphWidgetCard(state: state)
        case 6:
            TrophyCaseWidgetCard(state: state)
        case 7:
            HunterVelocityWidgetCard(state: state)
        case 8:
            LockScreenGlanceWidgetCard(state: state)
        default:
            RarestWidgetCard(state: state)
        }
    }
}

// MARK: - 1. Rarest Trophy Showcase Widget

private struct RarestWidgetCard: View {
    @ObservedObject var state: AppState
    
    private var rarestItem: (achievement: Achievement, gameName: String)? {
        state.unlockedByRarity.first.map { ($0.achievement, $0.gameName) }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.18))
                    .frame(width: 80, height: 80)
                
                if let urlStr = rarestItem?.achievement.iconUrl, let url = URL(string: urlStr) {
                    RemoteImageView(url: url, fallbackSystemName: "crown.fill", cornerRadius: 14)
                        .frame(width: 70, height: 70)
                } else {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 34))
                        .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.4), lineWidth: 1.5)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("RAREST TROPHY SHOWCASE")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                        .tracking(1.0)
                    Spacer()
                    if let pct = rarestItem?.achievement.globalPercent {
                        Text("\(String(format: "%.1f%%", pct)) of players")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                    }
                }
                
                Text(rarestItem?.achievement.displayName ?? "No achievements yet")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(rarestItem?.gameName ?? "Steam Game")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                
                Text(rarestItem?.achievement.descriptionText ?? "Unlock rare achievements in your games to showcase them here.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }
        }
        .padding(18)
        .frame(width: 440, height: 140)
        .background(Color.black.opacity(0.58))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - 2. Perfectionist Streak Widget

private struct StreakWidgetCard: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("ACTIVE STREAK")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.orange)
                        .tracking(1.0)
                }
                Text("7 Days")
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                Text("Daily hunting consistency")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Divider()
                .frame(height: 70)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("COMPLETION")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.secondary)
                    .tracking(1.0)
                Text("\(Int(state.overallCompletionPercentage))%")
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color.cyan)
                Text("\(state.perfectGamesCount) Perfect Games")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(20)
        .frame(width: 380, height: 130)
        .background(Color.black.opacity(0.58))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - 3. Active Game Progress Widget

private struct GameProgressWidgetCard: View {
    let game: SteamGame?
    
    var body: some View {
        HStack(spacing: 16) {
            RemoteImageView(url: game?.headerImageUrl, fallbackSystemName: "gamecontroller.fill", cornerRadius: 10)
                .frame(width: 80, height: 44)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(game?.name ?? "Steam Game")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(game?.completionPercentage ?? 0))%")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color.accentColor)
                }
                
                CustomProgressBar(value: game?.completionPercentage ?? 0, height: 4, isPerfect: game?.isPerfect ?? false)
                
                HStack {
                    Text("\(game?.unlockedAchievements ?? 0)/\(game?.totalAchievements ?? 0) Unlocked")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                    Text(game?.playtimeHoursFormatted ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(18)
        .frame(width: 420, height: 120)
        .background(Color.black.opacity(0.58))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - 4. Road to 100% (Closer) Widget

private struct RoadTo100WidgetCard: View {
    @ObservedObject var state: AppState
    
    private var targetGame: SteamGame? {
        let near = state.games.filter { $0.completionPercentage >= 60.0 && $0.completionPercentage < 100.0 && $0.totalAchievements > 0 }
            .sorted { $0.completionPercentage > $1.completionPercentage }
        return near.first ?? state.games.filter { !$0.isPerfect && $0.totalAchievements > 0 }.max(by: { $0.completionPercentage < $1.completionPercentage })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RemoteImageView(url: targetGame?.headerImageUrl, fallbackSystemName: "gamecontroller.fill", cornerRadius: 8)
                    .frame(width: 72, height: 38)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("ROAD TO 100% • ALMOST THERE")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                            .tracking(1.0)
                        Spacer()
                        Text("\(Int(targetGame?.completionPercentage ?? 0))%")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                    }
                    
                    Text(targetGame?.name ?? "Steam Game")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
            
            // Progress Bar
            CustomProgressBar(value: targetGame?.completionPercentage ?? 0, height: 5, isPerfect: false)
            
            HStack {
                let remaining = targetGame?.lockedAchievements ?? 0
                Text(remaining > 0 ? "Only \(remaining) achievements left to complete!" : "Complete all achievements to master!")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                // Remaining locked achievement icon previews
                HStack(spacing: 4) {
                    if let lockedAchs = targetGame?.trackableAchievements.filter({ !$0.isUnlocked }).prefix(3) {
                        ForEach(Array(lockedAchs), id: \.apiName) { ach in
                            RemoteImageView(url: ach.iconUrl.flatMap { URL(string: $0) }, fallbackSystemName: "lock.fill", cornerRadius: 4)
                                .frame(width: 22, height: 22)
                                .saturation(0.0)
                                .opacity(0.6)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 440, height: 140)
        .background(Color.black.opacity(0.58))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - 5. Pinned Targets Grind Widget

private struct PinnedTargetsWidgetCard: View {
    @ObservedObject var state: AppState
    
    private var targets: [(name: String, game: String, percent: Double?, icon: String?)] {
        if !state.pinnedTargets.isEmpty {
            return state.pinnedTargets.prefix(3).map {
                ($0.achievement.displayName, $0.gameName, $0.achievement.globalPercent, $0.achievement.iconUrl)
            }
        }
        // Fallback: up to 3 rarest locked achievements
        return state.rarestLockedItems.prefix(3).map { ($0.name, $0.gameName, Optional($0.percent), $0.iconUrl) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "pin.fill")
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.3))
                        .font(.system(size: 11))
                    Text("PINNED GRIND TARGETS")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.3))
                        .tracking(1.0)
                }
                Spacer()
                Text("\(targets.count) Active Targets")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.2))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.3))
                    .cornerRadius(5)
            }
            
            VStack(spacing: 6) {
                if targets.isEmpty {
                    Text("Pin achievements from any game to track your grind live here.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                } else {
                    ForEach(0..<targets.count, id: \.self) { i in
                        let item = targets[i]
                        HStack(spacing: 10) {
                            RemoteImageView(url: item.icon.flatMap { URL(string: $0) }, fallbackSystemName: "target", cornerRadius: 6)
                                .frame(width: 26, height: 26)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(item.game)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            if let p = item.percent {
                                Text("\(String(format: "%.1f%%", p))")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color.cyan)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 440, height: 160)
        .background(Color.black.opacity(0.58))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - 6. Recent Trophy Triumph Widget

private struct RecentTriumphWidgetCard: View {
    @ObservedObject var state: AppState
    
    private var latestUnlock: (achievement: Achievement, gameName: String)? {
        if let newest = state.unlockedByTime.first { return (newest.achievement, newest.gameName) }
        // no unlock times known: any unlocked achievement will do
        return state.unlockedItems.first.map { ($0.achievement, $0.gameName) }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.cyan.opacity(0.18))
                    .frame(width: 76, height: 76)
                
                if let urlStr = latestUnlock?.achievement.iconUrl, let url = URL(string: urlStr) {
                    RemoteImageView(url: url, fallbackSystemName: "trophy.fill", cornerRadius: 12)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(.cyan)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1.5)
            )
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundColor(.cyan)
                        Text("LATEST UNLOCKED TRIUMPH")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.cyan)
                            .tracking(1.0)
                    }
                    Spacer()
                    if let dateStr = latestUnlock?.achievement.formattedUnlockDate {
                        Text(dateStr)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Text(latestUnlock?.achievement.displayName ?? "No unlocks recorded yet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text(latestUnlock?.gameName ?? "Steam Game")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                
                if let tier = latestUnlock?.achievement.rarityTier {
                    HStack(spacing: 4) {
                        Text("★ \(tier.rawValue)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(tier.color)
                        if let pct = latestUnlock?.achievement.globalPercent {
                            Text("• \(String(format: "%.1f%%", pct)) of hunters")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(18)
        .frame(width: 430, height: 135)
        .background(Color.black.opacity(0.58))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.cyan.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - 7. Trophy Hall & Milestones Widget

private struct TrophyCaseWidgetCard: View {
    @ObservedObject var state: AppState
    
    private var nextMilestone: (target: Int, name: String) {
        let count = state.perfectGamesCount
        if count < 1 { return (1, "Novice Hunter") }
        if count < 5 { return (5, "Skilled Perfectionist") }
        if count < 10 { return (10, "Master Perfectionist") }
        if count < 25 { return (25, "Elite Hunter") }
        if count < 50 { return (50, "Legendary God") }
        return (100, "Hall of Fame Mythic")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                    Text("TROPHY HALL OF FAME")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                        .tracking(1.0)
                }
                Spacer()
                Text("\(state.totalUnlockedCount) Trophies Unlocked")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
            }
            
            HStack(spacing: 16) {
                // Trophy Count Box
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                            .font(.system(size: 16))
                        Text("\(state.perfectGamesCount)")
                            .font(.system(size: 26, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Text("100% Games")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
                
                // Milestone Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Next Milestone: \(nextMilestone.name)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(state.perfectGamesCount)/\(nextMilestone.target)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                    }
                    
                    let progress = min(1.0, Double(state.perfectGamesCount) / Double(nextMilestone.target))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.82, blue: 0.2), Color.orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                    
                    // Medallion Icons
                    HStack(spacing: 8) {
                        let tiers = [(1, "1"), (5, "5"), (10, "10"), (25, "25"), (50, "50")]
                        ForEach(tiers, id: \.0) { t in
                            let reached = state.perfectGamesCount >= t.0
                            HStack(spacing: 2) {
                                Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 9))
                                Text(t.1)
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(reached ? Color(red: 1.0, green: 0.82, blue: 0.2) : .white.opacity(0.3))
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .frame(width: 440, height: 140)
        .background(Color.black.opacity(0.58))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(red: 1.0, green: 0.82, blue: 0.2).opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - 8. Hunter Velocity & Stats Widget

private struct HunterVelocityWidgetCard: View {
    @ObservedObject var state: AppState
    
    private var totalPlaytimeHours: Double {
        Double(state.visibleGames.reduce(0) { $0 + $1.playtimeMinutes }) / 60.0
    }
    
    private var unlocksPerHour: Double {
        guard totalPlaytimeHours > 0 else { return 0.0 }
        return Double(state.totalUnlockedCount) / totalPlaytimeHours
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.5))
                    Text("HUNTER VELOCITY & STATS")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.5))
                        .tracking(1.0)
                }
                Spacer()
                Text("S-Tier Hunter")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.2, green: 0.85, blue: 0.5).opacity(0.2))
                    .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.5))
                    .cornerRadius(5)
            }
            
            HStack(spacing: 12) {
                // Metric 1: Speed
                VStack(alignment: .leading, spacing: 2) {
                    Text("UNLOCK SPEED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                    Text(String(format: "%.1f/hr", unlocksPerHour))
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                    Text("achievements/hr")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                
                // Metric 2: Total Time
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL PLAYTIME")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                    Text(String(format: "%.0f hrs", totalPlaytimeHours))
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color.cyan)
                    Text("\(state.visibleGames.count) games tracked")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                
                // Metric 3: Completion Rate
                VStack(alignment: .leading, spacing: 2) {
                    Text("COMPLETION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                    Text("\(Int(state.overallCompletionPercentage))%")
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                    Text("\(state.totalUnlockedCount) unlocked")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
            }
        }
        .padding(16)
        .frame(width: 440, height: 135)
        .background(Color.black.opacity(0.58))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(red: 0.2, green: 0.85, blue: 0.5).opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - 9. Compact Lock Screen Glance Widget

private struct LockScreenGlanceWidgetCard: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            RemoteImageView(
                url: state.player?.avatarImageURL,
                fallbackSystemName: "person.crop.circle.fill",
                cornerRadius: 18
            )
            .frame(width: 38, height: 38)
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(state.player?.personaName ?? "Steam Hunter")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("Achievement Hunter")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Compact Badges
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                    Text("\(state.totalUnlockedCount)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.2))
                    Text("\(state.perfectGamesCount)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                
                HStack(spacing: 3) {
                    Text("\(Int(state.overallCompletionPercentage))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.cyan)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 420, height: 72)
        .background(Color.black.opacity(0.65))
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Widget Format Info Card

private struct WidgetFormatInfoCard: View {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let color: Color
    var isSelected: Bool = false
    var onSelect: () -> Void = {}
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 16))
                    Spacer()
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
