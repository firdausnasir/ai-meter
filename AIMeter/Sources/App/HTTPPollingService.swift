import Foundation

/// Common error type for API key-based polling services
enum HTTPPollingError: Equatable {
    case noKey
    case fetchFailed
    case rateLimited(retryAfter: TimeInterval)
}

/// Base class for HTTP API-key polling services (GLM, Kimi, etc.)
/// Handles: isFetching guard, HTTP status codes, rate limit detection, stale tracking, retryDate
@MainActor
class HTTPPollingService: PollingServiceBase {
    @Published var isStale: Bool = false
    @Published var error: HTTPPollingError? = nil
    @Published var retryDate: Date? = nil

    private(set) var refreshInterval: TimeInterval = 60
    private var isFetching = false
    private var consecutiveRateLimits = 0

    override func start(interval: TimeInterval = 60) {
        self.refreshInterval = interval
        loadCachedData(staleThreshold: interval * 2)
        super.start(interval: interval)
    }

    override func tick() async {
        await fetch()
    }

    func fetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        guard let apiKey = resolveAPIKey() else {
            self.error = .noKey
            return
        }

        guard let request = buildRequest(apiKey: apiKey) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 {
                    let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                        .flatMap { TimeInterval($0) } ?? 60
                    consecutiveRateLimits += 1
                    let backoff = retryAfter * pow(1.5, Double(min(consecutiveRateLimits - 1, 4)))
                    let jitter = Double.random(in: 0...5)
                    let delay = backoff + jitter
                    self.error = .rateLimited(retryAfter: delay)
                    self.retryDate = Date().addingTimeInterval(delay)
                    self.isStale = true
                    rescheduleTimer(interval: delay)
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    self.isStale = true
                    self.error = .fetchFailed
                    self.retryDate = nil
                    return
                }
            }

            try parseAndApply(data: data)

            self.isStale = false
            consecutiveRateLimits = 0  // Reset on success
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            self.retryDate = nil
        } catch {
            self.isStale = true
            self.error = .fetchFailed
            self.retryDate = nil
        }
    }

    // MARK: - Subclass overrides

    /// Return the API key (Keychain or env var)
    func resolveAPIKey() -> String? {
        fatalError("Subclasses must override resolveAPIKey()")
    }

    /// Build the URLRequest for this provider
    func buildRequest(apiKey: String) -> URLRequest? {
        fatalError("Subclasses must override buildRequest(apiKey:)")
    }

    /// Parse response data and update published properties. Throw on parse failure.
    func parseAndApply(data: Data) throws {
        fatalError("Subclasses must override parseAndApply(data:)")
    }

    /// Load cached data on startup; set isStale based on staleThreshold
    func loadCachedData(staleThreshold: TimeInterval) {
        // Subclasses override
    }
}
