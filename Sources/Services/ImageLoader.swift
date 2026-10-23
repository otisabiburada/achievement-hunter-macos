import AppKit
import CryptoKit
import ImageIO

/// NSImage isn't Sendable, but loaded images are treated as immutable here.
struct SendableImage: @unchecked Sendable {
    let value: NSImage
}

/// Two-level image cache: bounded in-memory NSCache + size-capped disk cache in ~/Library/Caches.
/// Images are downsampled on decode so thousands of covers don't blow up memory, and concurrent
/// requests for the same URL share one download.
actor ImageLoader {
    static let shared = ImageLoader()
    
    private let memory = NSCache<NSURL, NSImage>()
    private var inflight: [URL: Task<SendableImage?, Never>] = [:]
    private var failedAt: [URL: Date] = [:]
    private let dir: URL
    private let maxDiskBytes = 400 * 1024 * 1024
    private let maxPixelSize = 1200
    // Scrolling a long list must not open hundreds of connections at once.
    private let maxConcurrentDownloads = 8
    private var activeDownloads = 0
    private var downloadWaiters: [CheckedContinuation<Void, Never>] = []
    
    init() {
        memory.countLimit = 600
        memory.totalCostLimit = 160 * 1024 * 1024
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AchievementHunter/images")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dir = self.dir, cap = maxDiskBytes
        Task.detached(priority: .utility) { ImageLoader.prune(dir: dir, maxBytes: cap) }
    }
    
    func image(for rawURL: URL) async -> SendableImage? {
        let url = rawURL.upgradedToHTTPS
        if let hit = memory.object(forKey: url as NSURL) { return SendableImage(value: hit) }
        if let failed = failedAt[url], Date().timeIntervalSince(failed) < 300 { return nil }
        if let task = inflight[url] { return await task.value }
        
        let task = Task { await self.load(url) }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if image == nil { failedAt[url] = Date() }
        return image
    }
    
    private func load(_ url: URL) async -> SendableImage? {
        let file = dir.appendingPathComponent(Self.fileName(for: url))
        
        if let data = try? Data(contentsOf: file), let image = Self.decode(data, maxPixel: maxPixelSize) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            remember(image, for: url)
            return SendableImage(value: image)
        }
        
        await acquireDownloadSlot()
        defer { releaseDownloadSlot() }
        if Task.isCancelled { return nil }
        guard let (data, http) = try? await HTTPClient.data(for: URLRequest(url: url), maxAttempts: 2),
              (200..<300).contains(http.statusCode),
              let image = Self.decode(data, maxPixel: maxPixelSize) else { return nil }
        try? data.write(to: file, options: .atomic)
        remember(image, for: url)
        return SendableImage(value: image)
    }
    
    private func acquireDownloadSlot() async {
        if activeDownloads < maxConcurrentDownloads {
            activeDownloads += 1
            return
        }
        await withCheckedContinuation { downloadWaiters.append($0) }
    }
    
    private func releaseDownloadSlot() {
        if downloadWaiters.isEmpty {
            activeDownloads -= 1
        } else {
            downloadWaiters.removeFirst().resume()   // hand the slot straight to the next waiter
        }
    }
    
    private func remember(_ image: NSImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        memory.setObject(image, forKey: url as NSURL, cost: cost)
    }
    
    func clearDisk() {
        memory.removeAllObjects()
        failedAt.removeAll()
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    // MARK: helpers
    
    private static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".img"
    }
    
    private static func decode(_ data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    
    /// Least-recently-used eviction down to 80% of the cap.
    nonisolated private static func prune(dir: URL, maxBytes: Int) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var entries: [(url: URL, date: Date, size: Int)] = files.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        entries.sort { $0.date < $1.date }
        let target = maxBytes * 8 / 10
        for entry in entries where total > target {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
