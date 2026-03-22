import Foundation

enum UsagePace {
    enum Stage: String {
        case onTrack = "On track"
        case slightlyAhead = "Slightly ahead"
        case ahead = "Ahead"
        case farAhead = "Far ahead"
        case slightlyBehind = "Slightly behind"
        case behind = "Behind"
        case farBehind = "Far behind"
    }

    struct Result {
        let stage: Stage
        let deltaPercent: Double    // actual - expected (positive = ahead, negative = behind)
        let expectedPercent: Double // where you should be by now
        let actualPercent: Double   // where you actually are
        let etaDescription: String? // "Runs out in 2h 15m" or nil
    }

    /// Calculate pace given current usage and window timing.
    /// - Parameters:
    ///   - usagePercent: Current utilization (0-100 scale, Int)
    ///   - resetsAt: When the window resets
    ///   - windowDurationHours: Total window duration in hours (e.g., 5.0 for Claude session)
    ///   - now: Current time (injectable for testing)
    /// - Returns: Pace result, or nil if data is insufficient
    static func calculate(
        usagePercent: Int,
        resetsAt: Date?,
        windowDurationHours: Double,
        now: Date = Date()
    ) -> Result? {
        guard let resetsAt, resetsAt > now else { return nil }

        let windowDuration = windowDurationHours * 3600
        let windowStart = resetsAt.addingTimeInterval(-windowDuration)
        let elapsed = now.timeIntervalSince(windowStart)

        guard elapsed > 0, windowDuration > 0 else { return nil }

        let elapsedFraction = min(elapsed / windowDuration, 1.0)
        let expectedPercent = elapsedFraction * 100.0
        let actualPercent = Double(usagePercent)
        let delta = actualPercent - expectedPercent

        let stage: Stage
        switch delta {
        case ..<(-20): stage = .farBehind    // way under — lots of quota left
        case -20 ..< -10: stage = .behind
        case -10 ..< -5: stage = .slightlyBehind
        case -5 ..< 5: stage = .onTrack
        case 5 ..< 10: stage = .slightlyAhead
        case 10 ..< 20: stage = .ahead
        default: stage = .farAhead           // burning too fast
        }

        // ETA: if current rate continues, when does quota run out?
        var etaDescription: String? = nil
        if actualPercent > 0, elapsed > 0 {
            let rate = actualPercent / elapsed  // percent per second
            let remaining = 100.0 - actualPercent
            if remaining > 0, rate > 0 {
                let secondsUntilDepleted = remaining / rate
                let timeUntilReset = resetsAt.timeIntervalSince(now)
                if secondsUntilDepleted < timeUntilReset {
                    // Will run out before reset
                    etaDescription = formatDuration(secondsUntilDepleted)
                }
                // If secondsUntilDepleted >= timeUntilReset, quota lasts until reset — no warning needed
            }
        }

        return Result(
            stage: stage,
            deltaPercent: delta,
            expectedPercent: expectedPercent,
            actualPercent: actualPercent,
            etaDescription: etaDescription
        )
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "Runs out in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "Runs out in \(minutes)m"
        } else {
            return "Runs out soon"
        }
    }
}
