import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let message: String
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.secondary.opacity(0.4))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .accessibilityElement(children: .combine)
    }
}
