import Foundation

/// A small diagnostic log (no secrets, never tokens or cookies) written to
/// `~/Library/Application Support/AchievementHunter/app.log`. It records sign-in stages and sync summaries so a
/// problem can be understood from the file instead of guessed at. Trimmed automatically.
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()
    
    private let queue = DispatchQueue(label: "com.achievementhunter.log", qos: .utility)
    private let fileURL: URL
    private let maxBytes = 300_000
    private let formatter: DateFormatter
    
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AchievementHunter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("app.log")
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }
    
    var url: URL { fileURL }
    
    func log(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.async { [fileURL, maxBytes] in
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
            // Keep only the newest part once the file gets big.
            if let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int), size > maxBytes,
               let data = try? Data(contentsOf: fileURL) {
                let tail = data.suffix(maxBytes / 2)
                if let newline = tail.firstIndex(of: 0x0A) {
                    try? Data(tail[tail.index(after: newline)...]).write(to: fileURL)
                }
            }
        }
    }
    
    /// Blocks until queued lines are written (tests).
    func flush() { queue.sync {} }
}
