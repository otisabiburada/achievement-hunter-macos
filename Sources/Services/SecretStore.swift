import Foundation
import CryptoKit
import IOKit

/// Stores the app's few secrets (optional API key, Steam session cookies) in one encrypted file:
/// `~/Library/Application Support/AchievementHunter/secrets.bin`, mode 0600, AES-256-GCM.
///
/// Why not the macOS Keychain: the app is signed ad hoc, so its identity changes with every build, and macOS then
/// asks for the user's *login password* the first time a new version touches an existing Keychain item. That
/// prompt is alarming and it recurs on every update. The key here is derived from this Mac's hardware UUID, so a
/// copy of the file (Time Machine, cloud folders, a shared backup) can't be read on another computer.
final class SecretStore: @unchecked Sendable {
    static let shared = SecretStore()
    
    private let fileURL: URL
    private let keyFileURL: URL
    private let machineID: String?
    private let lock = NSLock()
    private var cache: [String: String]?
    
    /// `machineID` is injectable for tests; by default this Mac's hardware UUID is used.
    init(directory: URL? = nil, machineID: String? = SecretStore.hardwareUUID()) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AchievementHunter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        fileURL = dir.appendingPathComponent("secrets.bin")
        keyFileURL = dir.appendingPathComponent("secrets.key")
        self.machineID = machineID
    }
    
    // MARK: Key
    
    static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
    
    private func symmetricKey() -> SymmetricKey? {
        if let id = machineID, !id.isEmpty {
            return SymmetricKey(data: SHA256.hash(data: Data("com.achievementhunter.mac.secrets.v1|\(id)".utf8)))
        }
        // No hardware id available: fall back to a random per-install key kept next to the file.
        if let existing = try? Data(contentsOf: keyFileURL), existing.count == 32 { return SymmetricKey(data: existing) }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let data = Data(bytes)
        guard writePrivate(data, to: keyFileURL) else { return nil }
        return SymmetricKey(data: data)
    }
    
    // MARK: File
    
    /// Writes with owner-only permissions from the start (no window where the file is world-readable).
    private func writePrivate(_ data: Data, to url: URL) -> Bool {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
        if rename(tmp.path, url.path) != 0 {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        return true
    }
    
    private func load() -> [String: String] {
        if let cache = cache { return cache }
        var result: [String: String] = [:]
        if let key = symmetricKey(),
           let blob = try? Data(contentsOf: fileURL),
           let box = try? AES.GCM.SealedBox(combined: blob),
           let plain = try? AES.GCM.open(box, using: key),
           let decoded = try? JSONDecoder().decode([String: String].self, from: plain) {
            result = decoded
        }
        cache = result
        return result
    }
    
    private func save(_ values: [String: String]) -> Bool {
        guard let key = symmetricKey(),
              let plain = try? JSONEncoder().encode(values),
              let sealed = try? AES.GCM.seal(plain, using: key).combined,
              writePrivate(sealed, to: fileURL) else { return false }
        cache = values
        return true
    }
    
    // MARK: API
    
    func read(_ account: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return load()[account].flatMap { Data(base64Encoded: $0) }
    }
    
    /// Pass nil to delete. Returns true if the store now reflects the requested state.
    @discardableResult
    func write(_ data: Data?, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var values = load()
        if let data = data { values[account] = data.base64EncodedString() } else { values.removeValue(forKey: account) }
        if values.isEmpty {
            cache = [:]
            try? FileManager.default.removeItem(at: fileURL)
            return true
        }
        return save(values)
    }
    
    func readString(_ account: String) -> String? {
        read(account).flatMap { String(data: $0, encoding: .utf8) }
    }
    
    @discardableResult
    func writeString(_ value: String?, account: String) -> Bool {
        write(value.flatMap { $0.isEmpty ? nil : $0.data(using: .utf8) }, account: account)
    }
    
    // MARK: Steam session cookies
    
    private struct StoredCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expires: Date?
        let secure: Bool
    }
    
    private static let cookieAccount = "steam_session_cookies"
    
    func saveCookies(_ cookies: [HTTPCookie]) {
        let relevant = cookies.filter {
            $0.domain.contains("steamcommunity.com") || $0.domain.contains("steampowered.com")
        }
        guard !relevant.isEmpty else {
            write(nil, account: Self.cookieAccount)
            return
        }
        let stored = relevant.map {
            StoredCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path, expires: $0.expiresDate, secure: $0.isSecure)
        }
        write(try? JSONEncoder().encode(stored), account: Self.cookieAccount)
    }
    
    func loadCookies() -> [HTTPCookie] {
        guard let data = read(Self.cookieAccount),
              let stored = try? JSONDecoder().decode([StoredCookie].self, from: data) else { return [] }
        let now = Date()
        return stored.compactMap { c in
            if let exp = c.expires, exp < now { return nil }
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: c.name,
                .value: c.value,
                .domain: c.domain,
                .path: c.path
            ]
            if let exp = c.expires { props[.expires] = exp }
            if c.secure { props[.secure] = "TRUE" }
            return HTTPCookie(properties: props)
        }
    }
}
