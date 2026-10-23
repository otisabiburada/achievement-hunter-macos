import SwiftUI

public struct RemoteImageView: View {
    public let url: URL?
    public var fallbackSystemName: String = "gamecontroller"
    public var cornerRadius: CGFloat = 8
    
    @State private var image: NSImage?
    @State private var failed = false
    
    public init(url: URL?, fallbackSystemName: String = "gamecontroller", cornerRadius: CGFloat = 8) {
        self.url = url
        self.fallbackSystemName = fallbackSystemName
        self.cornerRadius = cornerRadius
    }
    
    public var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if url == nil || failed {
                fallbackView
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            image = nil
            failed = false
            guard let url = url else { return }
            if let loaded = await ImageLoader.shared.image(for: url) {
                image = loaded.value
            } else {
                failed = true
            }
        }
    }
    
    private var fallbackView: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: fallbackSystemName)
                .font(.system(size: 20))
                .foregroundColor(.secondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension URL {
    /// App Transport Security is on, so plain-http Steam image URLs are upgraded to https.
    var upgradedToHTTPS: URL {
        guard scheme == "http", var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        comps.scheme = "https"
        return comps.url ?? self
    }
}
