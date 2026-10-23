import Foundation

/// Shared HTTP layer: real status-code handling, Retry-After aware backoff for
/// rate limits (429) and server errors (5xx), and clean cancellation.
enum HTTPClient {
    /// One session for all Steam traffic. `URLSession.shared` allows only 6 connections per host, which caps a library
    /// sync no matter how many requests the app runs in parallel; this one allows 24, has real timeouts (a stalled
    /// request can no longer hang a sync) and keeps no URL cache (the app has its own, and responses are small).
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 24
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 120
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        config.httpShouldUsePipelining = true
        return URLSession(configuration: config)
    }()

    static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    /// Returns the body and response for any non-retryable status. Callers decide what
    /// 400/401/403/404 mean for their endpoint. 429 and 5xx are retried, then thrown.
    static func data(
        for request: URLRequest,
        session: URLSession = HTTPClient.session,
        maxAttempts: Int = 4
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                let transient: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed]
                if transient.contains(error.code) && attempt < maxAttempts {
                    try await backoff(attempt: attempt, retryAfter: nil)
                    continue
                }
                throw SteamAPIError.networkError(error.localizedDescription)
            }

            guard let http = response as? HTTPURLResponse else {
                throw SteamAPIError.invalidResponse
            }

            if http.statusCode == 429 || (500...599).contains(http.statusCode) {
                if attempt < maxAttempts {
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
                    try await backoff(attempt: attempt, retryAfter: retryAfter)
                    continue
                }
                throw http.statusCode == 429 ? SteamAPIError.rateLimited : SteamAPIError.httpStatus(http.statusCode)
            }

            return (data, http)
        }
    }

    static func data(from url: URL, session: URLSession = HTTPClient.session) async throws -> (Data, HTTPURLResponse) {
        try await data(for: URLRequest(url: url), session: session)
    }

    private static func backoff(attempt: Int, retryAfter: TimeInterval?) async throws {
        let seconds = min(retryAfter ?? pow(2.0, Double(attempt)), 30.0)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
