import SwiftUI

/// A shimmer effect modifier for skeleton loading states
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0)
                    ],
                    startPoint: .init(x: phase - 0.5, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}

/// A skeleton placeholder block
struct SkeletonBlock: View {
    var height: CGFloat = 12
    var width: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.08))
            .frame(width: width, height: height)
    }
}

/// Skeleton card that mimics UsageCardView layout
struct SkeletonCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SkeletonBlock(height: 14, width: 14)
                SkeletonBlock(height: 14, width: 80)
                Spacer()
                SkeletonBlock(height: 20, width: 40)
            }
            HStack {
                SkeletonBlock(height: 11, width: 100)
                Spacer()
                SkeletonBlock(height: 11, width: 70)
            }
            SkeletonBlock(height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .modifier(ShimmerModifier())
    }
}

/// Skeleton chart that mimics chart views
struct SkeletonChartView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SkeletonBlock(height: 12, width: 50)
                Spacer()
                SkeletonBlock(height: 12, width: 120)
            }
            SkeletonBlock(height: 80)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .modifier(ShimmerModifier())
    }
}
