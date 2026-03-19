import SwiftUI

// MARK: - RecapView

struct RecapView: View {
    let recap: MonthlyRecapData

    @State private var appeared = false

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                overviewCard
                if let claude = recap.claude { claudeCard(claude) }
                if let copilot = recap.copilot { copilotCard(copilot) }
                highlightsCard
                footerCard
            }
            .padding(20)
        }
        .frame(width: 480)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeIn(duration: 0.4)) { appeared = true }
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(ProviderTheme.claude.accentColor)
            Text(monthTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("AI Meter")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    // MARK: - Overview Card

    private var overviewCard: some View {
        let totalPoints = (recap.claude?.dataPointCount ?? 0) + (recap.copilot?.dataPointCount ?? 0)
        return recapCard(title: "Overview", accentColor: .white) {
            HStack(spacing: 0) {
                statColumn(value: "\(totalPoints)", label: "Snapshots")
                Divider().background(Color.white.opacity(0.1)).frame(width: 1)
                statColumn(value: activeDays, label: "Active days")
            }
        }
    }

    // MARK: - Claude Card

    private func claudeCard(_ stats: ClaudeRecapStats) -> some View {
        recapCard(title: "Claude", accentColor: ProviderTheme.claude.accentColor) {
            VStack(spacing: 14) {
                HStack(spacing: 24) {
                    gaugeWithLabel(
                        percentage: Int(stats.avgSessionUtilization * 100),
                        label: "Avg Session"
                    )
                    gaugeWithLabel(
                        percentage: Int(stats.peakSessionUtilization * 100),
                        label: "Peak Session"
                    )
                    gaugeWithLabel(
                        percentage: Int(stats.avgWeeklyUtilization * 100),
                        label: "Avg Weekly"
                    )
                }
                .frame(maxWidth: .infinity)

                if let plan = stats.planName {
                    HStack {
                        Text("Plan:")
                            .font(.system(size: AppTypeScale.footnote))
                            .foregroundColor(.secondary)
                        Text(plan)
                            .font(.system(size: AppTypeScale.footnote, weight: .semibold))
                            .foregroundColor(ProviderTheme.claude.accentColor)
                    }
                }

                HStack {
                    Text("Peak date:")
                        .font(.system(size: AppTypeScale.footnote))
                        .foregroundColor(.secondary)
                    Text(formatDate(stats.peakDate))
                        .font(.system(size: AppTypeScale.footnote, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Copilot Card

    private func copilotCard(_ stats: CopilotRecapStats) -> some View {
        recapCard(title: "Copilot", accentColor: ProviderTheme.copilot.accentColor) {
            VStack(spacing: 10) {
                progressRow(label: "Chat", percentage: Int(stats.avgChatUtilization * 100))
                progressRow(label: "Completions", percentage: Int(stats.avgCompletionsUtilization * 100))
                progressRow(label: "Premium", percentage: Int(stats.avgPremiumUtilization * 100))

                if let plan = stats.plan {
                    HStack {
                        Text("Plan:")
                            .font(.system(size: AppTypeScale.footnote))
                            .foregroundColor(.secondary)
                        Text(plan)
                            .font(.system(size: AppTypeScale.footnote, weight: .semibold))
                            .foregroundColor(ProviderTheme.copilot.accentColor)
                    }
                }
            }
        }
    }

    // MARK: - Highlights Card

    private var highlightsCard: some View {
        let claudeStats = recap.claude
        let avgUtil = claudeStats.map { Int($0.avgSessionUtilization * 100) } ?? 0
        let isPowerUser = avgUtil > 70

        return recapCard(title: "Highlights", accentColor: .yellow) {
            VStack(alignment: .leading, spacing: 8) {
                if let stats = claudeStats {
                    highlightRow(
                        icon: "chart.line.uptrend.xyaxis",
                        text: "Peak Claude session: \(Int(stats.peakSessionUtilization * 100))% on \(formatDate(stats.peakDate))"
                    )
                    highlightRow(
                        icon: "camera.viewfinder",
                        text: "\(stats.dataPointCount) usage snapshots recorded"
                    )
                }
                if let copilot = recap.copilot {
                    highlightRow(
                        icon: "star.fill",
                        text: "Copilot peak premium: \(Int(copilot.peakPremiumUtilization * 100))%"
                    )
                }
                if isPowerUser {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                        Text("Power User — avg session above 70%!")
                            .font(.system(size: AppTypeScale.footnote, weight: .semibold))
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Footer Card

    private var footerCard: some View {
        VStack(spacing: 12) {
            ShareButton(recap: recap)
            Text("AI Meter · aimeter.app")
                .font(.system(size: AppTypeScale.caption))
                .foregroundColor(Color.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    // MARK: - Reusable sub-views

    private func recapCard<Content: View>(title: String, accentColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: AppTypeScale.callout, weight: .semibold))
                .foregroundColor(accentColor)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card)
                .stroke(accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private func gaugeWithLabel(percentage: Int, label: String) -> some View {
        VStack(spacing: 6) {
            CircularGaugeView(percentage: percentage, lineWidth: 6, size: 70)
            Text(label)
                .font(.system(size: AppTypeScale.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func progressRow(label: String, percentage: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: AppTypeScale.footnote, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: AppTypeScale.footnote, weight: .bold, design: .rounded))
                    .foregroundColor(UsageColor.forUtilization(percentage))
            }
            ProgressBarView(percentage: percentage, height: 6)
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: AppTypeScale.caption))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func highlightRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.system(size: AppTypeScale.footnote))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return "\(fmt.string(from: recap.month)) Recap"
    }

    private var activeDays: String {
        // Estimate active days from data points — 1 point per minute max, so > 0 unique days
        let calendar = Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: recap.month)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            return "—"
        }
        let range = start..<end
        let daysInMonth = calendar.range(of: .day, in: .month, for: recap.month)?.count ?? 30
        // Use data point count as a rough proxy: 1 point per polling interval (~60s default)
        let total = (recap.claude?.dataPointCount ?? 0) + (recap.copilot?.dataPointCount ?? 0)
        // Can't be more than the days in the month
        let estimated = min(total > 0 ? daysInMonth : 0, daysInMonth)
        let _ = range // suppress unused warning
        return "\(estimated)"
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }
}

// MARK: - ShareButton

// Extracted to allow @MainActor usage cleanly
private struct ShareButton: View {
    let recap: MonthlyRecapData

    var body: some View {
        Button {
            share()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
                Text("Share Recap")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(ProviderTheme.claude.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func share() {
        guard let image = RecapImageRenderer.renderShareImage(from: recap) else { return }
        let picker = NSSharingServicePicker(items: [image])
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
}
