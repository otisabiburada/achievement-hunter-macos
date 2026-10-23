import SwiftUI
import AppKit

// MARK: - Templates

/// Templates for single-achievement and 100%-game cards. `.classic` is the original Core Graphics renderer.
public enum ShareTemplate: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case spotlight = "Spotlight"
    case poster = "Poster"
    case minimal = "Minimal"
    
    public var id: String { rawValue }
    
    public var size: CGSize {
        switch self {
        case .classic: return CGSize(width: 1080, height: 600)
        case .spotlight: return CGSize(width: 1200, height: 675)
        case .poster: return CGSize(width: 1080, height: 1350)
        case .minimal: return CGSize(width: 1200, height: 630)
        }
    }
    
    public var subtitle: String {
        switch self {
        case .classic: return "Original blurred-art card"
        case .spotlight: return "Big icon, wide 16:9"
        case .poster: return "Portrait 4:5 for stories & feeds"
        case .minimal: return "Clean light card"
        }
    }
}

public enum ProfileShareTemplate: String, CaseIterable, Identifiable {
    case hunter = "Hunter Card"
    case trophies = "Rarest Trophies"
    case compact = "Compact"
    case year = "Your Year"
    
    public var id: String { rawValue }
    
    public var size: CGSize {
        switch self {
        case .year: return CGSize(width: 1200, height: 675)
        case .hunter: return CGSize(width: 1200, height: 675)
        case .trophies: return CGSize(width: 1200, height: 630)
        case .compact: return CGSize(width: 1200, height: 360)
        }
    }
    
    public var subtitle: String {
        switch self {
        case .hunter: return "Stats + game covers (Exophase style)"
        case .trophies: return "Your rarest unlocks"
        case .compact: return "Slim stats banner"
        case .year: return "Unlocks per month, rarest, finished"
        }
    }
}

public enum ProfileGameSource: String, CaseIterable, Identifiable {
    case mostCompleted = "Most completed"
    case mostPlayed = "Most played"
    case perfectOnly = "100% games"
    
    public var id: String { rawValue }
}

// MARK: - Models

/// Everything a single-achievement / perfect-game card needs, with images already loaded (ImageRenderer can't await).
public struct ShareCardModel {
    public var eyebrow: String          // "ACHIEVEMENT UNLOCKED" / "100% COMPLETED"
    public var title: String
    public var subtitle: String         // description or progress line
    public var gameName: String
    public var badge: String?           // "Ultra Rare · 3.4% of players"
    public var accent: Color
    public var percent: Double?         // rarity bar
    public var dateText: String?
    public var stats: [(label: String, value: String)]
    public var playerName: String
    public var isPerfect: Bool
    public var icon: NSImage?
    public var art: NSImage?
    public var avatar: NSImage?
    public var symbol: String           // SF Symbol shown when there is no icon
}

public struct ProfileCardModel {
    public struct GameTile { public var name: String; public var percent: Double; public var isPerfect: Bool; public var art: NSImage? }
    public struct Trophy { public var name: String; public var game: String; public var percent: Double; public var icon: NSImage? }
    
    public var playerName: String
    public var avatar: NSImage?
    public var games: Int
    public var unlocked: Int
    public var total: Int
    public var completion: Double
    public var perfect: Int
    public var rareCount: Int            // achievements held by < 10% of players
    public var playtimeHours: Double
    public var tiles: [GameTile]
    public var trophies: [Trophy]
}

/// Fills exactly the space it is offered (a scaled-to-fill image would otherwise enlarge its parent).
private struct FillImage: View {
    let image: NSImage
    var blur: CGFloat = 0
    var body: some View {
        Color.clear
            .overlay(Image(nsImage: image).resizable().scaledToFill().blur(radius: blur))
            .clipped()
    }
}

private let gold = Color(red: 1.0, green: 0.82, blue: 0.2)
private let navy = Color(red: 0.05, green: 0.07, blue: 0.14)

// MARK: - Shared pieces

private struct CardBackground: View {
    let art: NSImage?
    let accent: Color
    var blur: CGFloat = 40
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [navy, Color(red: 0.10, green: 0.14, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let art = art {
                FillImage(image: art, blur: blur).opacity(0.55)
            }
            RadialGradient(colors: [accent.opacity(0.28), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
            LinearGradient(colors: [Color.black.opacity(0.15), Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct IconTile: View {
    let image: NSImage?
    let symbol: String
    let accent: Color
    let size: CGFloat
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(Color.black.opacity(0.35))
            if let image = image {
                FillImage(image: image)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            } else {
                Image(systemName: symbol).font(.system(size: size * 0.45)).foregroundColor(accent)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).strokeBorder(accent.opacity(0.9), lineWidth: max(3, size * 0.02)))
        .shadow(color: accent.opacity(0.55), radius: size * 0.12)
    }
}

private struct PlayerChip: View {
    let name: String
    let avatar: NSImage?
    var light = false
    var size: CGFloat = 44
    
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let avatar = avatar {
                    FillImage(image: avatar)
                } else {
                    Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.gray)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            Text(name)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(light ? .black.opacity(0.8) : .white)
        }
    }
}

private struct Brand: View {
    var light = false
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
            Text("Achievement Hunter")
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(light ? .black.opacity(0.45) : .white.opacity(0.6))
    }
}

private struct BadgePill: View {
    let text: String
    let color: Color
    var size: CGFloat = 22
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, size * 0.7)
            .padding(.vertical, size * 0.35)
            .background(color.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1.5))
    }
}

private struct StatsRow: View {
    let stats: [(label: String, value: String)]
    var light = false
    var valueSize: CGFloat = 38
    var body: some View {
        HStack(spacing: 40) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.value).font(.system(size: valueSize, weight: .heavy, design: .rounded))
                        .foregroundColor(light ? .black.opacity(0.85) : .white)
                    Text(s.label.uppercased()).font(.system(size: 13, weight: .bold))
                        .foregroundColor(light ? .black.opacity(0.4) : .white.opacity(0.5))
                        .kerning(1)
                }
            }
        }
    }
}

// MARK: - Achievement / perfect-game cards

public struct ShareCardView: View {
    let model: ShareCardModel
    let template: ShareTemplate
    
    public var body: some View {
        switch template {
        case .spotlight, .classic: spotlight
        case .poster: poster
        case .minimal: minimal
        }
    }
    
    private var spotlight: some View {
        ZStack {
            CardBackground(art: model.art, accent: model.accent)
            HStack(spacing: 56) {
                IconTile(image: model.icon, symbol: model.symbol, accent: model.accent, size: 300)
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.eyebrow).font(.system(size: 20, weight: .heavy)).kerning(3).foregroundColor(model.accent)
                    Text(model.title).font(.system(size: 60, weight: .heavy)).foregroundColor(.white)
                        .lineLimit(2).minimumScaleFactor(0.6)
                    Text(model.subtitle).font(.system(size: 26)).foregroundColor(.white.opacity(0.78))
                        .lineLimit(3)
                    if let badge = model.badge { BadgePill(text: badge, color: model.accent) }
                    if !model.stats.isEmpty { StatsRow(stats: model.stats).padding(.top, 8) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 72)
            VStack {
                Spacer()
                HStack {
                    PlayerChip(name: model.playerName, avatar: model.avatar)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(model.gameName).font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                        if let d = model.dateText { Text(d).font(.system(size: 16)).foregroundColor(.white.opacity(0.6)) }
                    }
                }
                .padding(.horizontal, 56).padding(.bottom, 40)
            }
            VStack { HStack { Spacer(); Brand().padding(32) }; Spacer() }
        }
    }
    
    private var poster: some View {
        ZStack(alignment: .top) {
            CardBackground(art: model.art, accent: model.accent, blur: 12)
            VStack(spacing: 0) {
                // Hero art band, faded into the background (no hard seam)
                Group {
                    if let art = model.art {
                        FillImage(image: art)
                    } else {
                        Color.black.opacity(0.3)
                    }
                }
                .frame(width: 1080, height: 640)
                .mask(
                    LinearGradient(stops: [.init(color: .black, location: 0.0), .init(color: .black, location: 0.5), .init(color: .clear, location: 1.0)],
                                   startPoint: .top, endPoint: .bottom)
                )
                Spacer(minLength: 0)
            }
            VStack(spacing: 22) {
                Spacer().frame(height: 360)
                IconTile(image: model.icon, symbol: model.symbol, accent: model.accent, size: 300)
                Text(model.eyebrow).font(.system(size: 24, weight: .heavy)).kerning(4).foregroundColor(model.accent)
                Text(model.title).font(.system(size: 66, weight: .heavy)).foregroundColor(.white)
                    .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.6)
                    .padding(.horizontal, 70)
                Text(model.subtitle).font(.system(size: 28)).foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 90)
                if let badge = model.badge { BadgePill(text: badge, color: model.accent, size: 26) }
                if !model.stats.isEmpty { StatsRow(stats: model.stats, valueSize: 44).padding(.top, 10) }
                Spacer(minLength: 0)
                VStack(spacing: 14) {
                    Text(model.gameName).font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                    HStack(spacing: 24) {
                        PlayerChip(name: model.playerName, avatar: model.avatar, size: 52)
                        Brand()
                    }
                }
                .padding(.bottom, 56)
            }
        }
    }
    
    private var minimal: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.98)
            Rectangle().fill(model.accent).frame(width: 14).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 56) {
                IconTile(image: model.icon, symbol: model.symbol, accent: model.accent, size: 260)
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.eyebrow).font(.system(size: 18, weight: .heavy)).kerning(3).foregroundColor(model.accent.opacity(0.9))
                    Text(model.title).font(.system(size: 56, weight: .heavy)).foregroundColor(.black.opacity(0.88))
                        .lineLimit(2).minimumScaleFactor(0.6)
                    Text(model.subtitle).font(.system(size: 24)).foregroundColor(.black.opacity(0.6)).lineLimit(3)
                    if let pct = model.percent {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.08)).frame(width: 460, height: 12)
                                Capsule().fill(model.accent).frame(width: max(12, 460 * min(pct, 100) / 100), height: 12)
                            }
                            if let badge = model.badge { Text(badge).font(.system(size: 18, weight: .semibold)).foregroundColor(.black.opacity(0.55)) }
                        }
                    } else if let badge = model.badge {
                        Text(badge).font(.system(size: 20, weight: .semibold)).foregroundColor(.black.opacity(0.55))
                    }
                    if !model.stats.isEmpty { StatsRow(stats: model.stats, light: true, valueSize: 34).padding(.top, 6) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 76)
            VStack {
                Spacer()
                HStack {
                    PlayerChip(name: model.playerName, avatar: model.avatar, light: true, size: 40)
                    Spacer()
                    Text(model.gameName).font(.system(size: 20, weight: .bold)).foregroundColor(.black.opacity(0.7))
                    Text("•").foregroundColor(.black.opacity(0.3))
                    Brand(light: true)
                }
                .padding(.horizontal, 60).padding(.bottom, 34)
            }
        }
    }
}

// MARK: - Profile card (Exophase-style)

public struct ProfileCardView: View {
    let model: ProfileCardModel
    let template: ProfileShareTemplate
    
    public var body: some View {
        switch template {
        case .hunter: hunter
        case .trophies: trophies
        case .compact: compact
        case .year: hunter   // the year card has its own view (YearCardView)
        }
    }
    
    private func big(_ value: String, _ label: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.5)
            Text(label.uppercased()).font(.system(size: 14, weight: .bold)).kerning(1.2).foregroundColor(.white.opacity(0.5))
        }
    }
    
    private func header(size: CGFloat = 96) -> some View {
        HStack(spacing: 22) {
            Group {
                if let a = model.avatar { FillImage(image: a) }
                else { Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.gray) }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 2))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.playerName).font(.system(size: size * 0.46, weight: .heavy)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.5)
                Text("Steam achievement hunter").font(.system(size: 18, weight: .medium)).foregroundColor(.white.opacity(0.55))
            }
        }
    }
    
    private var hunter: some View {
        ZStack {
            LinearGradient(colors: [navy, Color(red: 0.10, green: 0.16, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.blue.opacity(0.25), .clear], center: .topLeading, startRadius: 0, endRadius: 760)
            HStack(alignment: .top, spacing: 48) {
                VStack(alignment: .leading, spacing: 34) {
                    header()
                    VStack(alignment: .leading, spacing: 26) {
                        HStack(spacing: 44) {
                            big("\(model.games)", "Games")
                            big("\(model.unlocked)", "Achievements")
                        }
                        HStack(spacing: 44) {
                            big("\(Int(model.completion.rounded()))%", "Completion", color: Color(red: 0.3, green: 0.8, blue: 1.0))
                            big("\(model.perfect)", "Perfect games", color: gold)
                        }
                        HStack(spacing: 44) {
                            big("\(model.rareCount)", "Rare (<10%)", color: Color(red: 0.85, green: 0.5, blue: 1.0))
                            big(model.playtimeHours >= 1000 ? String(format: "%.1fk", model.playtimeHours / 1000) : "\(Int(model.playtimeHours))", "Hours played")
                        }
                    }
                    Spacer(minLength: 0)
                    Brand()
                }
                .frame(width: 470, alignment: .leading)
                
                // Game cover grid
                let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(Array(model.tiles.prefix(9).enumerated()), id: \.offset) { _, t in
                        ZStack(alignment: .bottom) {
                            Group {
                                if let art = t.art { FillImage(image: art) }
                                else { Color.white.opacity(0.08) }
                            }
                            .frame(height: 172)
                            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                            HStack {
                                Text(t.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(t.isPerfect ? "100%" : "\(Int(t.percent))%")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundColor(t.isPerfect ? gold : .white)
                            }
                            .padding(.horizontal, 10).padding(.bottom, 8)
                            GeometryReader { geo in
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    Rectangle().fill(t.isPerfect ? gold : Color.accentColor)
                                        .frame(width: max(2, geo.size.width * min(t.percent, 100) / 100), height: 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(height: 172)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.isPerfect ? gold.opacity(0.8) : Color.white.opacity(0.12), lineWidth: t.isPerfect ? 2 : 1))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 60).padding(.vertical, 54)
        }
    }
    
    private var trophies: some View {
        ZStack {
            LinearGradient(colors: [navy, Color(red: 0.16, green: 0.10, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [gold.opacity(0.18), .clear], center: .top, startRadius: 0, endRadius: 700)
            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .center) {
                    header(size: 84)
                    Spacer()
                    HStack(spacing: 36) {
                        VStack(alignment: .leading) { Text(String(model.unlocked)).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundColor(.white); Text("ACHIEVEMENTS").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.5)) }
                        VStack(alignment: .leading) { Text(String(model.perfect)).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundColor(gold); Text("PERFECT").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.5)) }
                        VStack(alignment: .leading) { Text(String(Int(model.completion.rounded())) + "%").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 0.3, green: 0.8, blue: 1.0)); Text("COMPLETION").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.5)) }
                    }
                }
                Text("RAREST UNLOCKS").font(.system(size: 18, weight: .heavy)).kerning(3).foregroundColor(gold)
                HStack(spacing: 18) {
                    ForEach(Array(model.trophies.prefix(5).enumerated()), id: \.offset) { _, t in
                        let tier = RarityTier(percentage: t.percent)
                        VStack(spacing: 10) {
                            IconTile(image: t.icon, symbol: "trophy.fill", accent: tier.color, size: 120)
                            Text(t.name).font(.system(size: 17, weight: .bold)).foregroundColor(.white).lineLimit(2).multilineTextAlignment(.center).frame(height: 44)
                            Text(t.game).font(.system(size: 13)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                            Text(String(format: "%.1f%%", t.percent)).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(tier.color)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tier.color.opacity(0.35), lineWidth: 1.5))
                    }
                }
                Spacer(minLength: 0)
                HStack { Spacer(); Brand() }
            }
            .padding(.horizontal, 60).padding(.vertical, 48)
        }
    }
    
    private var compact: some View {
        ZStack {
            LinearGradient(colors: [navy, Color(red: 0.10, green: 0.16, blue: 0.34)], startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 48) {
                header(size: 120)
                Spacer(minLength: 0)
                big("\(model.games)", "Games")
                big("\(model.unlocked)", "Achievements")
                big("\(Int(model.completion.rounded()))%", "Completion", color: Color(red: 0.3, green: 0.8, blue: 1.0))
                big("\(model.perfect)", "Perfect", color: gold)
            }
            .padding(.horizontal, 60)
            VStack { Spacer(); HStack { Spacer(); Brand().padding(.trailing, 28).padding(.bottom, 16) } }
        }
    }
}

// MARK: - Builders & rendering

@MainActor
public enum ShareCardFactory {
    private static func load(_ url: URL?) async -> NSImage? {
        guard let url = url else { return nil }
        return await ImageLoader.shared.image(for: url)?.value
    }
    
    private static func art(for game: SteamGame?, appId: Int?) async -> NSImage? {
        if let url = game?.heroBannerUrl, let img = await load(url) { return img }
        if let url = game?.headerImageUrl, let img = await load(url) { return img }
        if let id = appId ?? game?.appId, let url = URL(string: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg") {
            return await load(url)
        }
        return nil
    }
    
    public static func achievementModel(achievement a: Achievement, game: SteamGame?, gameName: String, player: SteamPlayer?) async -> ShareCardModel {
        let tier = a.rarityTier
        let accent = tier?.color ?? Color(red: 0.3, green: 0.65, blue: 1.0)
        var badge: String?
        if let pct = a.globalPercent, let tier = tier { badge = "\(tier.rawValue) · \(String(format: "%.1f", pct))% of players" }
        let icon = await load(a.iconUrl.flatMap { URL(string: $0) })
        let artImage = await art(for: game, appId: a.gameAppId)
        let avatar = await load(player?.avatarImageURL)
        return ShareCardModel(
            eyebrow: "ACHIEVEMENT UNLOCKED",
            title: a.displayName,
            subtitle: a.descriptionText,
            gameName: gameName,
            badge: badge,
            accent: accent,
            percent: a.globalPercent,
            dateText: a.formattedUnlockDate.map { "Unlocked \($0)" },
            stats: [],
            playerName: player?.personaName ?? "Steam Hunter",
            isPerfect: false,
            icon: icon, art: artImage, avatar: avatar,
            symbol: "trophy.fill"
        )
    }
    
    public static func perfectModel(game: SteamGame, player: SteamPlayer?) async -> ShareCardModel {
        let rarest = game.achievements.filter { $0.isUnlocked && $0.globalPercent != nil }.min { ($0.globalPercent ?? 100) < ($1.globalPercent ?? 100) }
        var stats: [(label: String, value: String)] = [("Achievements", "\(game.unlockedAchievements)/\(game.totalAchievements)")]
        if game.playtimeIsKnown != false && game.playtimeMinutes > 0 { stats.append(("Playtime", game.playtimeHoursFormatted)) }
        if let r = rarest, let p = r.globalPercent { stats.append(("Rarest", String(format: "%.1f%%", p))) }
        let artImage = await art(for: game, appId: game.appId)
        let avatar = await load(player?.avatarImageURL)
        let icon = await load(rarest?.iconUrl.flatMap { URL(string: $0) })
        return ShareCardModel(
            eyebrow: game.hasMultipleSets ? "100% · ALL SETS COMPLETE" : "100% COMPLETED",
            title: game.name,
            subtitle: rarest.map { "Rarest unlock: \($0.displayName)" } ?? "Every achievement unlocked",
            gameName: game.name,
            badge: nil,
            accent: gold,
            percent: 100,
            dateText: game.achievements.compactMap { $0.unlockTimestamp }.max().map { "Finished \(DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none))" },
            stats: stats,
            playerName: player?.personaName ?? "Steam Hunter",
            isPerfect: true,
            icon: icon ?? artImage, art: artImage, avatar: avatar,
            symbol: "crown.fill"
        )
    }
    
    public static func profileModel(state: AppState, source: ProfileGameSource) async -> ProfileCardModel {
        let games = state.visibleGames
        let withAch = games.filter { $0.totalAchievements > 0 }
        let ranked: [SteamGame]
        switch source {
        case .mostCompleted: ranked = withAch.sorted { ($0.isPerfect ? 1 : 0, $0.completionPercentage, $0.totalAchievements) > ($1.isPerfect ? 1 : 0, $1.completionPercentage, $1.totalAchievements) }
        case .mostPlayed: ranked = withAch.sorted { $0.playtimeMinutes > $1.playtimeMinutes }
        case .perfectOnly: ranked = withAch.filter { $0.isPerfect }.sorted { $0.playtimeMinutes > $1.playtimeMinutes }
        }
        var rare: [(Achievement, String)] = []
        var rareCount = 0
        for g in games {
            for a in g.trackableAchievements where a.isUnlocked {
                if let p = a.globalPercent {
                    rare.append((a, g.name))
                    if p < 10 { rareCount += 1 }
                }
            }
        }
        let topRare = rare.sorted { ($0.0.globalPercent ?? 100) < ($1.0.globalPercent ?? 100) }.prefix(5)
        
        let tileGames = Array(ranked.prefix(9))
        var tiles: [ProfileCardModel.GameTile] = []
        for g in tileGames {
            tiles.append(.init(name: g.name, percent: g.completionPercentage, isPerfect: g.isPerfect, art: await load(g.headerImageUrl)))
        }
        var trophies: [ProfileCardModel.Trophy] = []
        for (a, gameName) in topRare {
            trophies.append(.init(name: a.displayName, game: gameName, percent: a.globalPercent ?? 0, icon: await load(a.iconUrl.flatMap { URL(string: $0) })))
        }
        let known = games.filter { $0.playtimeIsKnown != false }
        return ProfileCardModel(
            playerName: state.player?.personaName ?? "Steam Hunter",
            avatar: await load(state.player?.avatarImageURL),
            games: withAch.count,
            unlocked: state.totalUnlockedCount,
            total: state.totalAchievementsCount,
            completion: state.overallCompletionPercentage,
            perfect: state.perfectGamesCount,
            rareCount: rareCount,
            playtimeHours: Double(known.reduce(0) { $0 + $1.playtimeMinutes }) / 60,
            tiles: tiles,
            trophies: trophies
        )
    }
    
    /// Renders any SwiftUI card at 2x into a PNG-ready NSImage.
    public static func render<V: View>(_ view: V, size: CGSize) -> NSImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).clipped().environment(\.colorScheme, .dark))
        renderer.scale = 2
        return renderer.nsImage
    }
}


// MARK: - Year in review

public struct YearCardModel {
    public var recap: YearRecap
    public var playerName: String
    public var avatar: NSImage?
    public var rarestIcon: NSImage?
}

public struct YearCardView: View {
    let model: YearCardModel
    
    private static let months = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    
    private func big(_ value: String, _ label: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 54, weight: .heavy, design: .rounded)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.5)
            Text(label.uppercased()).font(.system(size: 14, weight: .bold)).kerning(1.2).foregroundColor(.white.opacity(0.5))
        }
    }
    
    public var body: some View {
        let r = model.recap
        let peak = max(r.perMonth.max() ?? 1, 1)
        ZStack {
            LinearGradient(colors: [navy, Color(red: 0.16, green: 0.10, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.purple.opacity(0.3), .clear], center: .topTrailing, startRadius: 0, endRadius: 800)
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 20) {
                    Group {
                        if let a = model.avatar { FillImage(image: a) }
                        else { Image(systemName: "person.crop.circle.fill").resizable().foregroundColor(.gray) }
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.playerName).font(.system(size: 34, weight: .heavy)).foregroundColor(.white).lineLimit(1)
                        Text("Steam achievements").font(.system(size: 18, weight: .medium)).foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    Text(String(r.year)).font(.system(size: 84, weight: .black, design: .rounded)).foregroundColor(gold)
                }
                
                HStack(alignment: .bottom, spacing: 50) {
                    VStack(alignment: .leading, spacing: 22) {
                        big("\(r.totalUnlocks)", "Unlocked in \(r.year)")
                        big("\(r.finishedGames.count)", "Games finished", color: gold)
                        big("\(r.rareCount)", "Rare (<10%)", color: Color(red: 0.85, green: 0.5, blue: 1.0))
                    }
                    .frame(width: 330, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 18) {
                        Text("UNLOCKS PER MONTH").font(.system(size: 14, weight: .bold)).kerning(1.2).foregroundColor(.white.opacity(0.5))
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(0..<12, id: \.self) { i in
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(r.perMonth[i] == (r.perMonth.max() ?? 0) && r.perMonth[i] > 0 ? gold : Color(red: 0.3, green: 0.8, blue: 1.0).opacity(0.75))
                                        .frame(height: max(4, CGFloat(r.perMonth[i]) / CGFloat(peak) * 150))
                                    Text(Self.months[i]).font(.system(size: 14, weight: .bold)).foregroundColor(.white.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 180, alignment: .bottom)
                        
                        HStack(spacing: 14) {
                            if let rare = r.rarest {
                                HStack(spacing: 12) {
                                    IconTile(image: model.rarestIcon, symbol: "sparkles", accent: gold, size: 62)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("RAREST UNLOCK").font(.system(size: 11, weight: .bold)).kerning(1).foregroundColor(.white.opacity(0.5))
                                        Text(rare.achievement.displayName).font(.system(size: 18, weight: .bold)).foregroundColor(.white).lineLimit(1)
                                        Text(rare.gameName + (rare.achievement.globalPercent.map { String(format: " - %.1f%%", $0) } ?? "")).font(.system(size: 13)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("BUSIEST").font(.system(size: 11, weight: .bold)).kerning(1).foregroundColor(.white.opacity(0.5))
                                Text(r.busiestMonth.map { Self.monthNames[$0] } ?? "-").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                                Text("\(r.activeDays) active days").font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer(minLength: 0)
                HStack {
                    if !r.topGames.isEmpty {
                        Text("Most active: " + r.topGames.map { $0.name }.joined(separator: "  -  "))
                            .font(.system(size: 15, weight: .medium)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer()
                    Brand()
                }
            }
            .padding(48)
        }
    }
}

extension ShareCardFactory {
    public static func yearModel(state: AppState, year: Int) async -> YearCardModel {
        let recap = YearRecap.compute(games: state.visibleGames, year: year)
        return YearCardModel(
            recap: recap,
            playerName: state.player?.personaName ?? "Steam Hunter",
            avatar: await load(state.player?.avatarImageURL),
            rarestIcon: await load(recap.rarest?.achievement.iconUrl.flatMap { URL(string: $0) })
        )
    }
}
