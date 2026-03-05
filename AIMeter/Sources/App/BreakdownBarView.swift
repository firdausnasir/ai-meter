import SwiftUI

struct BreakdownBarView: View {
    let segments: [(label: String, value: Int, color: Color)]
    let height: CGFloat

    var body: some View {
        let total = max(segments.map(\.value).reduce(0, +), 1)

        VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        let fraction = CGFloat(segment.value) / CGFloat(total)
                        RoundedRectangle(cornerRadius: height / 2)
                            .fill(segment.color)
                            .frame(width: max(geo.size.width * fraction, fraction > 0 ? 2 : 0))
                    }
                }
            }
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.white.opacity(0.1))
            )

            HStack(spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 6, height: 6)
                        Text("\(segment.label) \(segment.value)%")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
    }
}
