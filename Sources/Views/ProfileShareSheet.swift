import SwiftUI
import AppKit

/// Shareable profile card (Exophase-style): totals, game covers and rarest unlocks.
public struct ProfileShareSheet: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var template: ProfileShareTemplate = .hunter
    @State private var source: ProfileGameSource = .mostCompleted
    @State private var model: ProfileCardModel? = nil
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var yearModel: YearCardModel? = nil
    @State private var renderedImage: NSImage? = nil
    @State private var isRendering = false
    @State private var message: String? = nil
    
    public init(state: AppState) {
        self.state = state
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.rectangle.stack.fill").foregroundColor(.accentColor)
                    Text("Share Your Profile").font(.system(size: 15, weight: .bold))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            
            Divider()
            
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    ForEach(ProfileShareTemplate.allCases) { t in
                        Button(action: { template = t }) {
                            VStack(spacing: 2) {
                                Text(t.rawValue).font(.system(size: 12, weight: .bold))
                                Text(t.subtitle).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(template == t ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(template == t ? Color.accentColor : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if template == .year {
                    let years = YearRecap.availableYears(games: state.visibleGames)
                    HStack {
                        Text("Year").font(.system(size: 12)).foregroundColor(.secondary)
                        Picker("Year", selection: $year) {
                            ForEach(years.isEmpty ? [year] : years, id: \.self) { Text(String($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                        Spacer()
                    }
                    .onAppear { if let first = years.first, !years.contains(year) { year = first } }
                }
                
                if template == .hunter {
                    HStack {
                        Text("Games shown").font(.system(size: 12)).foregroundColor(.secondary)
                        Picker("Games shown", selection: $source) {
                            ForEach(ProfileGameSource.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 340)
                        Spacer()
                    }
                }
                
                if let image = renderedImage, !isRendering {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 330)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)
                } else {
                    VStack(spacing: 12) {
                        ProgressView().scaleEffect(1.1)
                        Text("Rendering your card...").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                    }
                    .frame(height: 300)
                }
                
                if let message = message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                }
                
                HStack(spacing: 14) {
                    Button(action: {
                        if let img = renderedImage {
                            ShareCardGenerator.shared.copyToClipboard(image: img)
                            message = "Copied to the clipboard."
                        }
                    }) {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc.fill").padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(renderedImage == nil || isRendering)
                    
                    Button(action: {
                        if let img = renderedImage {
                            let name = "\(state.player?.personaName ?? "Profile")_\(template.rawValue)"
                            if let url = ShareCardGenerator.shared.saveToDownloads(image: img, filename: name) {
                                message = "Saved to Downloads: \(url.lastPathComponent)"
                            }
                        }
                    }) {
                        Label("Save PNG to Downloads", systemImage: "arrow.down.circle.fill").padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(renderedImage == nil || isRendering)
                }
            }
            .padding(20)
        }
        .frame(width: 720, height: 590)
        .task(id: source) {
            model = nil
            await render()
        }
        .onChange(of: year) { _, _ in
            yearModel = nil
            Task { await render() }
        }
        .onChange(of: template) { _, _ in
            Task { await render() }
        }
    }
    
    @MainActor
    private func render() async {
        isRendering = true
        defer { isRendering = false }
        message = nil
        if template == .year {
            if yearModel == nil { yearModel = await ShareCardFactory.yearModel(state: state, year: year) }
            if let ym = yearModel { renderedImage = ShareCardFactory.render(YearCardView(model: ym), size: template.size) }
            return
        }
        if model == nil {
            model = await ShareCardFactory.profileModel(state: state, source: source)
        }
        guard let model = model else { return }
        renderedImage = ShareCardFactory.render(ProfileCardView(model: model, template: template), size: template.size)
    }
}
