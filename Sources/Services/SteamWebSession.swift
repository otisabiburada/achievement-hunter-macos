import Foundation

/// Credentials for Steam Web API calls: either the user's own API key, or a short-lived access token that
/// Steam issues to a signed-in browser session. The token lets people use the app by just signing in.
public struct SteamAuth: Sendable, Equatable {
    public let apiKey: String?
    public let accessToken: String?
    
    public init(apiKey: String? = nil, accessToken: String? = nil) {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = (key?.isEmpty == false) ? key : nil
        self.accessToken = (accessToken?.isEmpty == false) ? accessToken : nil
    }
    
    /// A key wins over a token (it doesn't expire); nil when neither is available.
    public static func resolve(apiKey: String, token: SteamWebToken?) -> SteamAuth? {
        let auth = SteamAuth(apiKey: apiKey, accessToken: (token?.isFresh == true) ? token?.value : nil)
        return auth.queryItems.isEmpty ? nil : auth
    }
    
    public var queryItems: [String: String] {
        if let key = apiKey { return ["key": key] }
        if let token = accessToken { return ["access_token": token] }
        return [:]
    }
}

/// The short-lived web API token Steam gives to a signed-in session (a JWT).
public struct SteamWebToken: Codable, Sendable, Equatable {
    public let value: String
    public let expiresAt: Date
    public let steamId: String?
    
    public var isFresh: Bool { expiresAt > Date().addingTimeInterval(300) }
    
    /// Builds a token from the raw JWT, reading its expiry and subject (the SteamID) from the payload.
    public init?(jwt: String) {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let exp = (json["exp"] as? NSNumber)?.doubleValue
        value = jwt
        // Without an expiry assume a short life rather than trusting it forever.
        expiresAt = exp.map { Date(timeIntervalSince1970: $0) } ?? Date().addingTimeInterval(3600)
        steamId = json["sub"] as? String
    }
}

public enum SteamWebSession {
    static let configURLs = [
        "https://steamcommunity.com/pointssummary/ajaxgetasyncconfig",
        "https://store.steampowered.com/pointssummary/ajaxgetasyncconfig"
    ]
    
    /// Parses `{"success":1,"data":{"webapi_token":"..."}}`. Signed-out sessions get `"data":[]` -> nil.
    public static func parseToken(from data: Data) -> SteamWebToken? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["data"] as? [String: Any],
              let jwt = payload["webapi_token"] as? String, !jwt.isEmpty else { return nil }
        return SteamWebToken(jwt: jwt)
    }
    
    /// Asks Steam for the session's API token using the saved login cookies. nil if signed out or unavailable.
    public static func fetchToken(cookies: [HTTPCookie], expectedSteamId: String? = nil) async -> SteamWebToken? {
        guard !cookies.isEmpty else { return nil }
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        for urlString in configURLs {
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.setValue(HTTPClient.browserUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(header, forHTTPHeaderField: "Cookie")
            guard let (data, http) = try? await HTTPClient.data(for: request, maxAttempts: 2),
                  (200..<300).contains(http.statusCode),
                  let token = parseToken(from: data) else { continue }
            if let expected = expectedSteamId, let sub = token.steamId, sub != expected { continue }
            return token
        }
        return nil
    }
    
    /// Body for `WKWebView.callAsyncJavaScript`, run inside the signed-in login page (it already has every
    /// cookie, including httpOnly ones). Returns the raw `webapi_token` string or "".
    public static let tokenScriptBody = """
    try {
        const r = await fetch('https://steamcommunity.com/pointssummary/ajaxgetasyncconfig', { credentials: 'include' });
        const j = await r.json();
        return (j && j.data && j.data.webapi_token) ? String(j.data.webapi_token) : '';
    } catch (e) { return ''; }
    """
}
