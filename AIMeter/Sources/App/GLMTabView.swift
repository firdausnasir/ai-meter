import SwiftUI

struct GLMTabView: View {
    @ObservedObject var glmService: GLMService
    @ObservedObject var historyService: GLMHistoryService
    var onKeySaved: (() -> Void)? = nil

    var body: some View {
        if glmService.error == .noKey {
            APIKeyInputView(
                providerName: "GLM",
                placeholder: "GLM_API_KEY…",
                accentColor: ProviderTheme.glm.accentColor
            ) { key in
                APIKeyKeychainHelper.glm.saveAPIKey(key)
                onKeySaved?()
            }
        } else {
            VStack(spacing: 8) {
                    if case .fetchFailed = glmService.error {
                        ErrorBannerView(message: "Failed to fetch GLM data") {
                            Task { await glmService.fetch() }
                        }
                    }
                    if case .rateLimited = glmService.error {
                        ErrorBannerView(message: "Rate limited — retrying", retryDate: glmService.retryDate)
                    }
                    UsageCardView(
                        icon: "z.square",
                        title: "5hr Token Quota",
                        subtitle: "5h sliding window",
                        percentage: glmService.glmData.tokensPercent,
                        resetText: nil,
                        accentColor: ProviderTheme.glm.accentColor
                    )
                    if !glmService.glmData.tier.isEmpty {
                        HStack {
                            Text("Account")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(glmService.glmData.tier.capitalized)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    }
                    UsageHistoryChartView(
                        title: "Token % History",
                        dataPoints: historyService.history.dataPoints.map {
                            (date: $0.timestamp, value: Double($0.tokensPercent), label: shortDateLabel($0.timestamp))
                        },
                        valueFormatter: { "\(Int($0))%" },
                        accentColor: ProviderTheme.glm.accentColor
                    )
                }
        }
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }


}
