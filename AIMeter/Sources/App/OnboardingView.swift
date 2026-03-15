import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            switch currentStep {
            case 0:
                welcomeStep
            case 1:
                providersStep
            default:
                readyStep
            }
        }
        .padding(24)
        .frame(width: 360)
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Welcome to AI Meter")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text("Monitor your AI usage quotas in real time from the menu bar.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            onboardingButton("Get Started") {
                currentStep = 1
            }
        }
        .transition(.push(from: .trailing))
    }

    // MARK: - Providers

    private var providersStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Providers")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)

            providerRow(
                name: "Claude",
                color: ProviderTheme.claude.accentColor,
                icon: "claude",
                isAsset: true,
                detail: "Sign in via Settings to track session & weekly usage"
            )
            providerRow(
                name: "GitHub Copilot",
                color: ProviderTheme.copilot.accentColor,
                icon: "copilot",
                isAsset: true,
                detail: "Auto-detected from gh CLI — run gh auth login first"
            )
            providerRow(
                name: "GLM (Z.ai)",
                color: ProviderTheme.glm.accentColor,
                icon: "z.square",
                isAsset: false,
                detail: "Add your API key in Settings to track token quota"
            )
            providerRow(
                name: "Kimi (Moonshot)",
                color: ProviderTheme.kimi.accentColor,
                icon: "k.square",
                isAsset: false,
                detail: "Add your API key in Settings to track balance"
            )

            onboardingButton("Continue") {
                currentStep = 2
            }
        }
        .transition(.push(from: .trailing))
    }

    // MARK: - Ready

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                tipRow(icon: "command", text: "⌘R to refresh all providers")
                tipRow(icon: "arrow.left.arrow.right", text: "Arrow keys to switch tabs")
                tipRow(icon: "bell", text: "Set up notifications in Settings")
                tipRow(icon: "square.and.arrow.up", text: "Export history from Settings")
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))

            onboardingButton("Start Using AI Meter") {
                hasCompletedOnboarding = true
            }
        }
        .transition(.push(from: .trailing))
    }

    // MARK: - Components

    private func providerRow(name: String, color: Color, icon: String, isAsset: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            if isAsset {
                Image(icon)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundColor(color)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func onboardingButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [ProviderTheme.claude.accentColor, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
