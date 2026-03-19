import SwiftUI
import AppKit

// MARK: - RecapImageRenderer

@MainActor
enum RecapImageRenderer {
    /// Renders a shareable recap card at 1080×1920 (story format) into an NSImage.
    static func renderShareImage(from recap: MonthlyRecapData) -> NSImage? {
        let card = RecapShareCard(recap: recap)
            .frame(width: 1080, height: 1920)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0  // retina quality for social media
        guard let cgImage = renderer.cgImage else { return nil }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(
            width: CGFloat(cgImage.width) / renderer.scale,
            height: CGFloat(cgImage.height) / renderer.scale
        ))
        nsImage.isTemplate = false
        return nsImage
    }

    /// Saves a PNG to a user-chosen path via NSSavePanel.
    static func savePNG(from recap: MonthlyRecapData) {
        guard let image = renderShareImage(from: recap) else { return }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "ai-meter-recap.png"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    /// Copies the recap card PNG to the system clipboard.
    static func copyToClipboard(from recap: MonthlyRecapData) {
        guard let image = renderShareImage(from: recap) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

// MARK: - RecapShareCard

/// A 1080×1920 self-contained card suitable for social sharing.
private struct RecapShareCard: View {
    let recap: MonthlyRecapData

    var body: some View {
        ZStack {
            // Dark background
            Color(red: 0.06, green: 0.06, blue: 0.08)

            VStack(spacing: 28) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(ProviderTheme.claude.accentColor)
                    Text(monthTitle)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("AI Meter")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.5))
                }
                .padding(.top, 56)

                // Overview row: snapshots + active days
                shareCardBlock(title: "Overview", accentColor: .white) {
                    HStack(spacing: 0) {
                        shareStatColumn(
                            value: "\((recap.claude?.dataPointCount ?? 0) + (recap.copilot?.dataPointCount ?? 0))",
                            label: "Snapshots"
                        )
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1)
                            .padding(.vertical, 8)
                        shareStatColumn(value: activeDays, label: "Active days")
                    }
                }

                // Claude section
                if let claude = recap.claude {
                    shareCardBlock(title: "Claude", accentColor: ProviderTheme.claude.accentColor) {
                        VStack(spacing: 20) {
                            HStack(spacing: 40) {
                                shareGauge(
                                    percentage: Int(claude.avgSessionUtilization * 100),
                                    label: "Avg Session"
                                )
                                shareGauge(
                                    percentage: Int(claude.peakSessionUtilization * 100),
                                    label: "Peak Session"
                                )
                                shareGauge(
                                    percentage: Int(claude.avgWeeklyUtilization * 100),
                                    label: "Avg Weekly"
                                )
                            }
                            .frame(maxWidth: .infinity)

                            HStack(spacing: 32) {
                                if let plan = claude.planName {
                                    HStack(spacing: 8) {
                                        Text("Plan:")
                                            .font(.system(size: 24))
                                            .foregroundColor(Color.white.opacity(0.6))
                                        Text(plan)
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundColor(ProviderTheme.claude.accentColor)
                                    }
                                }
                                HStack(spacing: 8) {
                                    Text("Peak date:")
                                        .font(.system(size: 24))
                                        .foregroundColor(Color.white.opacity(0.6))
                                    Text(formatDate(claude.peakDate))
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }

                // Copilot section
                if let copilot = recap.copilot {
                    shareCardBlock(title: "Copilot", accentColor: ProviderTheme.copilot.accentColor) {
                        VStack(spacing: 16) {
                            shareProgressRow(
                                label: "Chat",
                                percentage: Int(copilot.avgChatUtilization * 100)
                            )
                            shareProgressRow(
                                label: "Completions",
                                percentage: Int(copilot.avgCompletionsUtilization * 100)
                            )
                            shareProgressRow(
                                label: "Premium",
                                percentage: Int(copilot.avgPremiumUtilization * 100)
                            )
                            if let plan = copilot.plan {
                                HStack(spacing: 8) {
                                    Text("Plan:")
                                        .font(.system(size: 24))
                                        .foregroundColor(Color.white.opacity(0.6))
                                    Text(plan)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(ProviderTheme.copilot.accentColor)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                // Highlights section
                shareCardBlock(title: "Highlights", accentColor: .yellow) {
                    VStack(alignment: .leading, spacing: 14) {
                        if let claude = recap.claude {
                            shareHighlightRow(
                                icon: "chart.line.uptrend.xyaxis",
                                text: "Peak Claude session: \(Int(claude.peakSessionUtilization * 100))% on \(formatDate(claude.peakDate))"
                            )
                            shareHighlightRow(
                                icon: "camera.viewfinder",
                                text: "\(claude.dataPointCount) Claude usage snapshots recorded"
                            )
                        }
                        if let copilot = recap.copilot {
                            shareHighlightRow(
                                icon: "star.fill",
                                text: "Copilot peak premium: \(Int(copilot.peakPremiumUtilization * 100))%"
                            )
                        }
                        // Power user badge
                        if let claude = recap.claude, claude.avgSessionUtilization > 0.70 {
                            HStack(spacing: 10) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.yellow)
                                Text("Power User — avg session above 70%!")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundColor(.yellow)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.yellow.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                // Watermark
                Text("aimeter.app")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.4))
                    .padding(.bottom, 52)
            }
            .padding(.horizontal, 56)
        }
        .frame(width: 1080, height: 1920)
    }

    // MARK: - Sub-views

    private func shareCardBlock<Content: View>(
        title: String,
        accentColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(accentColor)
            content()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private func shareStatColumn(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 24))
                .foregroundColor(Color.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func shareGauge(percentage: Int, label: String) -> some View {
        VStack(spacing: 12) {
            CircularGaugeView(percentage: percentage, lineWidth: 12, size: 160)
            Text(label)
                .font(.system(size: 24))
                .foregroundColor(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    private func shareProgressRow(label: String, percentage: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(UsageColor.forUtilization(percentage))
            }
            ProgressBarView(percentage: percentage, height: 10)
        }
    }

    private func shareHighlightRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(Color.white.opacity(0.5))
                .frame(width: 28)
            Text(text)
                .font(.system(size: 26))
                .foregroundColor(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return "\(fmt.string(from: recap.month)) Recap"
    }

    private var activeDays: String {
        let calendar = Calendar.current
        let daysInMonth = calendar.range(of: .day, in: .month, for: recap.month)?.count ?? 30
        let total = (recap.claude?.dataPointCount ?? 0) + (recap.copilot?.dataPointCount ?? 0)
        let estimated = min(total > 0 ? daysInMonth : 0, daysInMonth)
        return "\(estimated)"
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }
}
