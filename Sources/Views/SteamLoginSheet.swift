import SwiftUI
import WebKit

/// What a successful Steam sign-in hands back to the app.
public struct SteamLoginResult {
    public var steamId: String
    public var games: [SteamGame] = []
    public var apiKey: String? = nil
    public var cookies: [HTTPCookie] = []
    /// API token issued to the signed-in session; lets the app work without the user's own API key.
    public var webToken: String? = nil
}

public struct SteamLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let onLoginSuccess: (SteamLoginResult) -> Void
    
    @State private var loginMode: Int
    @State private var profileInput: String = ""
    @State private var apiKeyInput: String = ""
    @State private var isLoadingPage: Bool = true
    @State private var loadProgress: Double = 0.0
    @State private var authStageText: String = "Sign in on Steam's own page. The app never sees your password."
    @State private var quickConnectError: String? = nil
    @State private var isResolvingQuickConnect: Bool = false
    
    /// `initialMode`: 0 = sign in with Steam, 1 = API key.
    public init(
        initialMode: Int = 0,
        onLoginSuccess: @escaping (SteamLoginResult) -> Void
    ) {
        self._loginMode = State(initialValue: initialMode)
        self.onLoginSuccess = onLoginSuccess
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.key.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 18))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect Your Steam Account")
                            .font(.system(size: 15, weight: .bold))
                        Text(authStageText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Picker("", selection: $loginMode) {
                    Text("Sign in with Steam").tag(0)
                    Text("Use an API key").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if loginMode == 0 {
                VStack(spacing: 0) {
                    if isLoadingPage {
                        ProgressView(value: loadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(height: 3)
                    }
                    
                    SteamLoginWebView(
                        isLoading: $isLoadingPage,
                        progress: $loadProgress,
                        stageText: $authStageText,
                        onAuthComplete: { result in
                            onLoginSuccess(result)
                            dismiss()
                        }
                    )
                }
            } else {
                // API key mode: the official Web API, for people who prefer not to sign in
                VStack(spacing: 20) {
                    Spacer()
                    
                    VStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                        
                        Text("Connect with a Steam Web API Key")
                            .font(.system(size: 18, weight: .bold))
                        
                        Text("A free key from Valve lets the app read your library through Steam's official API. Your profile's \"Game details\" must be Public. Signing in with Steam doesn't need either.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Steam Profile URL, Vanity Name or SteamID64")
                                .font(.system(size: 11, weight: .semibold))
                            
                            TextField("e.g. steamcommunity.com/id/name or 76561198000000001", text: $profileInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Steam Web API Key")
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Button("Get a free key ↗") {
                                    if let url = URL(string: "https://steamcommunity.com/dev/apikey") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                            SecureField("Enter 32-character API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        
                        if let err = quickConnectError {
                            Text(err)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: 480)
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(10)
                    
                    Button(action: {
                        handleKeyConnect()
                    }) {
                        HStack(spacing: 8) {
                            if isResolvingQuickConnect {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                            Text(isResolvingQuickConnect ? "Connecting..." : "Connect with API Key")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: 480)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(profileInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || isResolvingQuickConnect)
                    
                    Spacer()
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 760, height: 640)
    }
    
    /// Checks the key against Steam before accepting it, so a typo is reported right here instead of as an empty library.
    private func handleKeyConnect() {
        let input = profileInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !key.isEmpty else { return }
        
        isResolvingQuickConnect = true
        quickConnectError = nil
        
        Task {
            do {
                let steamId = try await SteamAPIService.shared.resolveVanityURL(input, apiKey: key)
                _ = try await SteamAPIService.shared.fetchPlayerSummary(steamId: steamId, apiKey: key)
                let games = try await SteamAPIService.shared.fetchOwnedGames(steamId: steamId, apiKey: key)
                AppLog.shared.log("API key connect: \(games.count) games for \(steamId)")
                
                DispatchQueue.main.async {
                    self.isResolvingQuickConnect = false
                    self.onLoginSuccess(SteamLoginResult(steamId: steamId, games: games, apiKey: key))
                    self.dismiss()
                }
            } catch {
                AppLog.shared.log("API key connect failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isResolvingQuickConnect = false
                    switch error {
                    case SteamAPIError.accessDenied:
                        self.quickConnectError = "Steam rejected the API key. Check that you copied all 32 characters."
                    case SteamAPIError.privateProfile:
                        self.quickConnectError = SteamAPIError.privateProfile.localizedDescription
                    default:
                        self.quickConnectError = error.localizedDescription
                    }
                }
            }
        }
    }
}

public struct SteamLoginWebView: NSViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var progress: Double
    @Binding var stageText: String
    let onAuthComplete: (SteamLoginResult) -> Void
    
    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.suppressesIncrementalRendering = false
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        
        context.coordinator.setup(webView: webView)
        
        let returnUrl = "https://steamcommunity.com/openid_login_complete"
        let realm = "https://steamcommunity.com"
        
        var components = URLComponents(string: "https://steamcommunity.com/openid/login")!
        components.queryItems = [
            URLQueryItem(name: "openid.ns", value: "http://specs.openid.net/auth/2.0"),
            URLQueryItem(name: "openid.mode", value: "checkid_setup"),
            URLQueryItem(name: "openid.return_to", value: returnUrl),
            URLQueryItem(name: "openid.realm", value: realm),
            URLQueryItem(name: "openid.identity", value: "http://specs.openid.net/auth/2.0/identifier_select"),
            URLQueryItem(name: "openid.claimed_id", value: "http://specs.openid.net/auth/2.0/identifier_select")
        ]
        
        if let url = components.url {
            let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
            webView.load(request)
        }
        
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SteamLoginWebView
        var capturedSteamId: String? = nil
        var capturedCookies: [HTTPCookie] = []
        var hasCompletedExtraction = false
        private var progressObservation: NSKeyValueObservation?
        
        init(_ parent: SteamLoginWebView) {
            self.parent = parent
        }
        
        deinit {
            progressObservation?.invalidate()
        }
        
        func setup(webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.parent.progress = webView.estimatedProgress
                    if webView.estimatedProgress >= 0.75 {
                        self?.parent.isLoading = false
                    }
                }
            }
        }
        
        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }
        
        public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
            
            if let steamId = capturedSteamId, !hasCompletedExtraction {
                let urlStr = webView.url?.absoluteString ?? ""
                if urlStr.contains("/games") {
                    startExtractingGames(webView: webView, steamId: steamId)
                }
            }
        }
        
        private func startExtractingGames(webView: WKWebView, steamId: String) {
            guard !hasCompletedExtraction else { return }
            hasCompletedExtraction = true
            
            DispatchQueue.main.async {
                self.parent.stageText = "Extracting your full library..."
                self.parent.isLoading = true
            }
            
            pollForGames(webView: webView, steamId: steamId, attemptsRemaining: 25)
        }
        
        private func pollForGames(webView: WKWebView, steamId: String, attemptsRemaining: Int) {
            let jsScript = """
            (function() {
                var games = window.rgGames;
                if (!games || !Array.isArray(games) || games.length === 0) {
                    var cfg = document.querySelector('#gameslist_config');
                    var raw = cfg ? cfg.getAttribute('data-profile-gameslist') : null;
                    if (raw) {
                        try {
                            var parsed = JSON.parse(raw);
                            games = parsed.rgGames || parsed.games || (parsed.strProfileName && parsed.rgGames) || null;
                        } catch(e) {}
                    }
                }
                if (!games || !Array.isArray(games) || games.length === 0) {
                    var html = document.documentElement ? document.documentElement.innerHTML : '';
                    var idx = html.indexOf('var rgGames = ');
                    if (idx !== -1) {
                        var start = idx + 14;
                        var end = html.indexOf(';\\n', start);
                        if (end === -1) end = html.indexOf(';\\r\\n', start);
                        if (end === -1) end = html.indexOf(';', start);
                        if (end > start) {
                            try {
                                games = JSON.parse(html.substring(start, end).trim());
                            } catch(e) {}
                        }
                    }
                }
                if (games && Array.isArray(games) && games.length > 0) {
                    return games.map(function(g) {
                        var h = 0;
                        if (typeof g.hours_forever !== 'undefined') {
                            h = parseFloat(String(g.hours_forever).replace(/,/g, '')) || 0;
                        } else if (typeof g.playtime_forever !== 'undefined') {
                            h = (parseFloat(g.playtime_forever) || 0) / 60.0;
                        }
                        return {
                            appid: parseInt(g.appid, 10) || 0,
                            name: String(g.name || 'Steam Game #' + g.appid),
                            playtimeMinutes: Math.round(h * 60),
                            logo: String(g.logo || '')
                        };
                    });
                }
                return null;
            })()
            """
            
            webView.evaluateJavaScript(jsScript) { [weak self] result, _ in
                guard let self = self else { return }
                
                if let rawList = result as? [[String: Any]], !rawList.isEmpty {
                    let games: [SteamGame] = rawList.compactMap { dict in
                        guard let appId = dict["appid"] as? Int, appId > 0 else { return nil }
                        let name = dict["name"] as? String ?? "Steam Game #\(appId)"
                        let minutes = dict["playtimeMinutes"] as? Int ?? 0
                        let logo = dict["logo"] as? String ?? ""
                        let header = logo.isEmpty ? "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(appId)/header.jpg" : logo
                        return SteamGame(
                            appId: appId,
                            name: name,
                            playtimeMinutes: minutes,
                            customHeaderUrl: header,
                            achievements: [],
                            hasAchievementsLoaded: false
                        )
                    }.sorted { $0.playtimeMinutes > $1.playtimeMinutes }
                    
                    self.finishWithGames(webView: webView, steamId: steamId, games: games)
                    return
                }
                
                if attemptsRemaining > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.pollForGames(webView: webView, steamId: steamId, attemptsRemaining: attemptsRemaining - 1)
                    }
                } else {
                    self.finishWithGames(webView: webView, steamId: steamId, games: [])
                }
            }
        }
        
        private func finishWithGames(webView: WKWebView, steamId: String, games: [SteamGame]) {
            DispatchQueue.main.async {
                self.parent.onAuthComplete(SteamLoginResult(steamId: steamId, games: games, cookies: self.capturedCookies))
            }
        }
        
        /// Reads the API token Steam issues to this signed-in session. Tried inside the page first (it holds every
        /// cookie), then with the captured cookies.
        private func fetchWebToken(webView: WKWebView, steamId: String, cookies: [HTTPCookie]) async -> String? {
            let fromPage: String? = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    webView.callAsyncJavaScript(SteamWebSession.tokenScriptBody, arguments: [:], in: nil, in: .page) { result in
                        if case .success(let value) = result, let jwt = value as? String, !jwt.isEmpty {
                            continuation.resume(returning: jwt)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }
            if let jwt = fromPage {
                AppLog.shared.log("Sign-in: token read from the signed-in page")
                return jwt
            }
            let viaCookies = await SteamWebSession.fetchToken(cookies: cookies, expectedSteamId: steamId)?.value
            AppLog.shared.log("Sign-in: page gave no token; with \(cookies.count) cookies the token request \(viaCookies == nil ? "also failed" : "worked")")
            return viaCookies
        }
        
        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            let urlString = url.absoluteString
            
            if (urlString.contains("openid_login_complete") || urlString.contains("openid.claimed_id")) && capturedSteamId == nil {
                if let comp = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let items = comp.queryItems {
                    for item in items {
                        if item.name == "openid.claimed_id" || item.name == "openid.identity",
                           let val = item.value {
                            let extractedId = val.components(separatedBy: "/id/").last?
                                .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
                            if extractedId.allSatisfy({ $0.isNumber }) && extractedId.count >= 17 {
                                capturedSteamId = extractedId
                                decisionHandler(.cancel)
                                
                                DispatchQueue.main.async {
                                    self.parent.stageText = "Logged in! Fetching your games library..."
                                    self.parent.isLoading = true
                                }
                                
                                // Capture cookies, then ask Steam for this session's API token. With a token the app can
                                // read the whole library without the user's own API key.
                                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                                    self.capturedCookies = cookies
                                    Task { @MainActor in
                                        if let jwt = await self.fetchWebToken(webView: webView, steamId: extractedId, cookies: cookies) {
                                            self.hasCompletedExtraction = true
                                            self.parent.onAuthComplete(SteamLoginResult(steamId: extractedId, cookies: cookies, webToken: jwt))
                                            return
                                        }
                                        // Fallback: read the library from the games page of the signed-in session.
                                        if let gamesUrl = URL(string: "https://steamcommunity.com/my/games/?tab=all") {
                                            webView.load(URLRequest(url: gamesUrl))
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                                            if !self.hasCompletedExtraction {
                                                self.startExtractingGames(webView: webView, steamId: extractedId)
                                            }
                                        }
                                    }
                                }
                                return
                            }
                        }
                    }
                }
            }
            
            decisionHandler(.allow)
        }
    }
}

private struct RgGameItem: Codable {
    let appid: Int
    let name: String
    let hours_forever: String
    let logo: String
}
