import SwiftUI
import AppKit

public struct ShareCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let achievement: Achievement?
    public let game: SteamGame?
    public let gameName: String
    public let player: SteamPlayer?
    
    @State private var renderedImage: NSImage? = nil
    @State private var copySuccessMessage: String? = nil
    @State private var template: ShareTemplate = .spotlight
    @State private var model: ShareCardModel? = nil
    @State private var isRendering = false
    
    public init(achievement: Achievement? = nil, game: SteamGame? = nil, gameName: String = "", player: SteamPlayer? = nil) {
        self.achievement = achievement
        self.game = game
        self.gameName = gameName.isEmpty ? (game?.name ?? "") : gameName
        self.player = player
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .foregroundColor(.accentColor)
                    Text("Export Social Achievement Card")
                        .font(.system(size: 15, weight: .bold))
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            
            Divider()
            
            VStack(spacing: 16) {
                // Template picker
                HStack(spacing: 10) {
                    ForEach(ShareTemplate.allCases) { t in
                        Button(action: { template = t }) {
                            VStack(spacing: 2) {
                                Text(t.rawValue).font(.system(size: 12, weight: .bold))
                                Text(t.subtitle).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(template == t ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(template == t ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Card Preview
                if let image = renderedImage, !isRendering {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 340)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Rendering high-res card with blurred game art...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 320)
                }
                
                if let msg = copySuccessMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 4)
                }
                
                // Action Buttons
                HStack(spacing: 14) {
                    Button(action: {
                        if let img = renderedImage {
                            ShareCardGenerator.shared.copyToClipboard(image: img)
                            copySuccessMessage = "Copied high-res PNG to Clipboard! Ready to paste into Discord or Twitter."
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.doc.fill")
                            Text("Copy to Clipboard")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(renderedImage == nil)
                    
                    Button(action: {
                        if let img = renderedImage {
                            let base = achievement != nil ? "\(gameName)_\(achievement!.displayName)" : "\(gameName)_100_Percent"
                            let filename = "\(base)_\(template.rawValue)"
                            if let savedUrl = ShareCardGenerator.shared.saveToDownloads(image: img, filename: filename) {
                                copySuccessMessage = "Saved to Downloads: \(savedUrl.lastPathComponent)"
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Save PNG to Downloads")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(renderedImage == nil)
                }
            }
            .padding(20)
        }
        .frame(width: 700, height: 560)
        .task(id: template) {
            await renderCard()
        }
    }
    
    @MainActor
    private func renderCard() async {
        isRendering = true
        defer { isRendering = false }
        
        if template == .classic {
            // Original Core Graphics renderer
            if let g = game, achievement == nil {
                renderedImage = await ShareCardGenerator.shared.renderPerfectGameCard(game: g, player: player)
            } else if let ach = achievement {
                renderedImage = await ShareCardGenerator.shared.renderAchievementCard(achievement: ach, game: game, gameName: gameName, player: player)
            }
            return
        }
        
        if model == nil {
            if let g = game, achievement == nil {
                model = await ShareCardFactory.perfectModel(game: g, player: player)
            } else if let ach = achievement {
                model = await ShareCardFactory.achievementModel(achievement: ach, game: game, gameName: gameName, player: player)
            }
        }
        guard let model = model else { return }
        renderedImage = ShareCardFactory.render(ShareCardView(model: model, template: template), size: template.size)
    }
}
