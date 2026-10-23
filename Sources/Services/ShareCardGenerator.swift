import AppKit
import SwiftUI
import CoreImage

@MainActor
public final class ShareCardGenerator {
    public static let shared = ShareCardGenerator()
    
    public func copyToClipboard(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    public func saveToDownloads(image: NSImage, filename: String) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let fileManager = FileManager.default
        let downloadsUrl = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let safeName = filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let destination = downloadsUrl.appendingPathComponent("\(safeName).png")
        
        do {
            try pngData.write(to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            return destination
        } catch {
            return nil
        }
    }
    
    // MARK: - Network & Image Processing Helpers
    
    private func downloadImage(from url: URL?) async -> NSImage? {
        guard let url = url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url.upgradedToHTTPS)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
    
    private func fetchGameArt(game: SteamGame?, appId: Int?) async -> NSImage? {
        // 1. Try game's heroBannerUrl (1920x620)
        if let heroUrl = game?.heroBannerUrl, let img = await downloadImage(from: heroUrl) {
            return img
        }
        // 2. Try game's headerImageUrl (460x215)
        if let headerUrl = game?.headerImageUrl, let img = await downloadImage(from: headerUrl) {
            return img
        }
        // 3. Fallback direct appId lookup
        if let id = appId ?? game?.appId, id > 0 {
            if let hero = URL(string: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(id)/library_hero.jpg"),
               let img = await downloadImage(from: hero) {
                return img
            }
            if let header = URL(string: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg"),
               let img = await downloadImage(from: header) {
                return img
            }
        }
        return nil
    }
    
    private func createBlurredCGImage(from nsImage: NSImage, radius: Double = 45.0) -> CGImage? {
        guard let tiffData = nsImage.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }
        let clamped = ciImage.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: ciImage.extent) else {
            return nil
        }
        let ciContext = CIContext(options: nil)
        return ciContext.createCGImage(output, from: ciImage.extent)
    }
    
    // MARK: - 100% Perfect Game Social Card
    
    public func renderPerfectGameCard(game: SteamGame, player: SteamPlayer?) async -> NSImage {
        // Asynchronously fetch artwork and prepare blurred background
        let gameArt = await fetchGameArt(game: game, appId: game.appId)
        let blurredCG = gameArt.flatMap { createBlurredCGImage(from: $0, radius: 45.0) }
        
        let width: CGFloat = 1200
        let height: CGFloat = 675
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size)
        
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        
        let rect = CGRect(origin: .zero, size: size)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // 1. Blurred Game Art Background (or dark gradient fallback)
        if let blurredCG = blurredCG {
            let blurredNS = NSImage(cgImage: blurredCG, size: size)
            blurredNS.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            
            // Dark vignette overlay over blurred art for readability
            let overlayColors = [
                NSColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.68).cgColor,
                NSColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 0.88).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: overlayColors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: width * 0.5, y: height), end: CGPoint(x: width * 0.5, y: 0), options: [])
            }
        } else {
            // Dark linear gradient fallback
            let bgColors = [
                NSColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1.0).cgColor,
                NSColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 1.0).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: width * 0.5, y: height), end: CGPoint(x: width * 0.5, y: 0), options: [])
            }
        }
        
        // 2. Golden Accent Radial Glow in top center
        let goldGlowColors = [
            NSColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 0.28).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: goldGlowColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(glowGrad,
                                   startCenter: CGPoint(x: width * 0.5, y: height * 0.72),
                                   startRadius: 20,
                                   endCenter: CGPoint(x: width * 0.5, y: height * 0.72),
                                   endRadius: 420,
                                   options: [])
        }
        
        // 3. Outer Decorative Border
        let borderPath = CGPath(roundedRect: rect.insetBy(dx: 24, dy: 24), cornerWidth: 28, cornerHeight: 28, transform: nil)
        ctx.setStrokeColor(NSColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 0.5).cgColor)
        ctx.setLineWidth(2.5)
        ctx.addPath(borderPath)
        ctx.strokePath()
        
        // 4. Golden Trophy Icon
        let trophyConfig = NSImage.SymbolConfiguration(pointSize: 85, weight: .bold)
            .applying(.init(paletteColors: [NSColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 1.0)]))
        if let trophy = NSImage(systemSymbolName: "trophy.fill", accessibilityDescription: nil)?.withSymbolConfiguration(trophyConfig) {
            let trophyRect = NSRect(x: (width - 110) * 0.5, y: height - 175, width: 110, height: 95)
            trophy.draw(in: trophyRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        
        // 5. Ribbon Text: 100% PERFECT GAME COMPLETED
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        
        let ribbonAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .heavy),
            .foregroundColor: NSColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 1.0),
            .paragraphStyle: titleStyle,
            .kern: 3.0
        ]
        "★ 100% PERFECT GAME COMPLETED ★".draw(in: NSRect(x: 50, y: height - 215, width: width - 100, height: 32), withAttributes: ribbonAttr)
        
        // 6. Game Title (with shadow for maximum contrast)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 8
        
        let gameTitleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .heavy),
            .foregroundColor: NSColor.white,
            .paragraphStyle: titleStyle,
            .shadow: shadow
        ]
        game.name.draw(in: NSRect(x: 60, y: height - 315, width: width - 120, height: 85), withAttributes: gameTitleAttr)
        
        // 7. Stats Pills Container
        let pillWidth: CGFloat = 320
        let pillHeight: CGFloat = 95
        let spacing: CGFloat = 30
        let totalPillsWidth = pillWidth * 3 + spacing * 2
        let startX = (width - totalPillsWidth) * 0.5
        let pillY: CGFloat = height - 445
        
        let stats = [
            ("ACHIEVEMENTS", "\(game.unlockedAchievements) / \(game.totalAchievements) (100%)", "trophy.circle.fill"),
            ("PLAYTIME", game.playtimeHoursFormatted, "clock.fill"),
            ("PERFECTION STATUS", "Perfectionist Master", "crown.fill")
        ]
        
        for (i, stat) in stats.enumerated() {
            let px = startX + CGFloat(i) * (pillWidth + spacing)
            let pRect = CGRect(x: px, y: pillY, width: pillWidth, height: pillHeight)
            let pPath = CGPath(roundedRect: pRect, cornerWidth: 18, cornerHeight: 18, transform: nil)
            
            ctx.setFillColor(NSColor(white: 0.05, alpha: 0.65).cgColor)
            ctx.addPath(pPath)
            ctx.fillPath()
            
            ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(pPath)
            ctx.strokePath()
            
            let labelAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor(white: 0.75, alpha: 1.0),
                .paragraphStyle: titleStyle,
                .kern: 1.5
            ]
            stat.0.draw(in: NSRect(x: px, y: pillY + 54, width: pillWidth, height: 20), withAttributes: labelAttr)
            
            let valAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .heavy),
                .foregroundColor: NSColor.white,
                .paragraphStyle: titleStyle,
                .shadow: shadow
            ]
            stat.1.draw(in: NSRect(x: px, y: pillY + 18, width: pillWidth, height: 32), withAttributes: valAttr)
        }
        
        // 8. Footer: Player Name and App Watermark
        let footerY: CGFloat = 55
        let playerName = player?.personaName ?? "Steam Player"
        let playerAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1.0)
        ]
        "★ Mastered by \(playerName)".draw(at: CGPoint(x: 60, y: footerY), withAttributes: playerAttr)
        
        let appWatermarkAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.gray
        ]
        "Tracked with Achievement Hunter for Mac".draw(at: CGPoint(x: width - 390, y: footerY), withAttributes: appWatermarkAttr)
        
        image.unlockFocus()
        return image
    }
    
    // MARK: - Individual Achievement Social Card
    
    public func renderAchievementCard(achievement: Achievement, game: SteamGame? = nil, gameName: String, player: SteamPlayer?) async -> NSImage {
        // Asynchronously fetch game art and achievement icon
        let gameArt = await fetchGameArt(game: game, appId: achievement.gameAppId ?? game?.appId)
        let blurredCG = gameArt.flatMap { createBlurredCGImage(from: $0, radius: 45.0) }
        let achIcon = await downloadImage(from: achievement.iconUrl.flatMap { URL(string: $0) })
        
        let width: CGFloat = 1080
        let height: CGFloat = 600
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size)
        
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }
        
        let rect = CGRect(origin: .zero, size: size)
        let tierColor = achievement.rarityTier?.color ?? Color.blue
        let nsTierColor = NSColor(tierColor)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // 1. Blurred Game Art Background (or dark gradient fallback)
        if let blurredCG = blurredCG {
            let blurredNS = NSImage(cgImage: blurredCG, size: size)
            blurredNS.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            
            // Dark vignette overlay over blurred art
            let overlayColors = [
                NSColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.70).cgColor,
                NSColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 0.90).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: overlayColors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: width * 0.5, y: height), end: CGPoint(x: width * 0.5, y: 0), options: [])
            }
        } else {
            // Dark fallback
            let bgColors = [
                NSColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1.0).cgColor,
                NSColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 1.0).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: width * 0.5, y: height), end: CGPoint(x: width * 0.5, y: 0), options: [])
            }
        }
        
        // 2. Rarity-colored ambient glow behind the badge area
        let badgeGlowColors = [
            nsTierColor.withAlphaComponent(0.25).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: badgeGlowColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(glowGrad,
                                   startCenter: CGPoint(x: 130, y: height - 125),
                                   startRadius: 20,
                                   endCenter: CGPoint(x: 130, y: height - 125),
                                   endRadius: 280,
                                   options: [])
        }
        
        // 3. Outer Rarity Border
        let borderPath = CGPath(roundedRect: rect.insetBy(dx: 24, dy: 24), cornerWidth: 24, cornerHeight: 24, transform: nil)
        ctx.setStrokeColor(nsTierColor.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(2.5)
        ctx.addPath(borderPath)
        ctx.strokePath()
        
        // 4. Achievement Icon Frame (140x140)
        let iconFrame = CGRect(x: 60, y: height - 195, width: 140, height: 140)
        let iconPath = CGPath(roundedRect: iconFrame, cornerWidth: 20, cornerHeight: 20, transform: nil)
        ctx.setFillColor(NSColor(white: 0.05, alpha: 0.70).cgColor)
        ctx.addPath(iconPath)
        ctx.fillPath()
        ctx.setStrokeColor(nsTierColor.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(2.5)
        ctx.addPath(iconPath)
        ctx.strokePath()
        
        if let icon = achIcon {
            // Draw achievement icon with rounded clipping
            ctx.saveGState()
            let innerRect = iconFrame.insetBy(dx: 10, dy: 10)
            let clipPath = CGPath(roundedRect: innerRect, cornerWidth: 14, cornerHeight: 14, transform: nil)
            ctx.addPath(clipPath)
            ctx.clip()
            icon.draw(in: innerRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            ctx.restoreGState()
        } else {
            // Fallback SF Symbol
            let trophyConfig = NSImage.SymbolConfiguration(pointSize: 60, weight: .bold)
                .applying(.init(paletteColors: [nsTierColor]))
            if let trophy = NSImage(systemSymbolName: "trophy.fill", accessibilityDescription: nil)?.withSymbolConfiguration(trophyConfig) {
                let tRect = NSRect(x: 60 + 35, y: height - 195 + 35, width: 70, height: 70)
                trophy.draw(in: tRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }
        
        // Text Shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 6
        
        // 5. Game Name
        let gameAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor(white: 0.82, alpha: 1.0),
            .kern: 1.5
        ]
        let displayGameName = gameName.isEmpty ? (game?.name ?? "Steam Game") : gameName
        displayGameName.uppercased().draw(at: CGPoint(x: 230, y: height - 90), withAttributes: gameAttr)
        
        // 6. Achievement Display Name
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 36, weight: .heavy),
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
        achievement.displayName.draw(in: NSRect(x: 230, y: height - 150, width: width - 290, height: 50), withAttributes: nameAttr)
        
        // 7. Rarity Pill
        let rarityText = "★ \(achievement.rarityTier?.rawValue ?? "Achievement") • \(achievement.formattedRarity) of players"
        let pillRect = CGRect(x: 230, y: height - 195, width: 340, height: 32)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.setFillColor(nsTierColor.withAlphaComponent(0.18).cgColor)
        ctx.addPath(pillPath)
        ctx.fillPath()
        ctx.setStrokeColor(nsTierColor.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(pillPath)
        ctx.strokePath()
        
        let pillAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: nsTierColor
        ]
        rarityText.draw(at: CGPoint(x: 245, y: height - 190), withAttributes: pillAttr)
        
        // 8. Description Glassmorphic Box
        let descBox = CGRect(x: 60, y: 130, width: width - 120, height: 230)
        let descPath = CGPath(roundedRect: descBox, cornerWidth: 18, cornerHeight: 18, transform: nil)
        ctx.setFillColor(NSColor(white: 0.06, alpha: 0.65).cgColor)
        ctx.addPath(descPath)
        ctx.fillPath()
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(descPath)
        ctx.strokePath()
        
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.lightGray,
            .kern: 1.5
        ]
        "ACHIEVEMENT DETAILS".draw(at: CGPoint(x: 85, y: 325), withAttributes: labelAttr)
        
        let descStyle = NSMutableParagraphStyle()
        descStyle.lineBreakMode = .byWordWrapping
        let descAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: NSColor(white: 0.95, alpha: 1.0),
            .paragraphStyle: descStyle
        ]
        let rawDesc = achievement.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let descContent = rawDesc.isEmpty ? "Hidden achievement details kept secret until unlocked." : rawDesc
        descContent.draw(
            in: NSRect(x: 85, y: 190, width: 890, height: 120),
            withAttributes: descAttr
        )
        
        // Tags if present
        if !achievement.tags.isEmpty {
            var tagX: CGFloat = 85
            for tag in achievement.tags {
                let tagText = tag.rawValue
                let tagFont = NSFont.systemFont(ofSize: 12, weight: .bold)
                let tagWidth = (tagText as NSString).size(withAttributes: [.font: tagFont]).width + 20
                let tagRect = CGRect(x: tagX, y: 150, width: tagWidth, height: 24)
                let tagPath = CGPath(roundedRect: tagRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                ctx.setFillColor(NSColor(tag.color).withAlphaComponent(0.2).cgColor)
                ctx.addPath(tagPath)
                ctx.fillPath()
                ctx.setStrokeColor(NSColor(tag.color).withAlphaComponent(0.5).cgColor)
                ctx.setLineWidth(1)
                ctx.addPath(tagPath)
                ctx.strokePath()
                
                tagText.draw(at: CGPoint(x: tagX + 10, y: 154), withAttributes: [
                    .font: tagFont,
                    .foregroundColor: NSColor(tag.color)
                ])
                tagX += tagWidth + 10
            }
        }
        
        // 9. Footer: Date and Player
        let footerY: CGFloat = 55
        let footerText = "★ Unlocked by \(player?.personaName ?? "Steam Player") • \(achievement.formattedUnlockDate ?? "Unlocked")"
        let footerPlayerAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1.0)
        ]
        footerText.draw(at: CGPoint(x: 60, y: footerY), withAttributes: footerPlayerAttr)
        
        let footerAppAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.gray
        ]
        "Tracked with Achievement Hunter for Mac".draw(at: CGPoint(x: width - 390, y: footerY), withAttributes: footerAppAttr)
        
        image.unlockFocus()
        return image
    }
}
