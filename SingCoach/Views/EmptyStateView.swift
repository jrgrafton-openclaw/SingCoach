import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 64, weight: .light))
                .foregroundColor(SingCoachTheme.textSecondary.opacity(0.5))
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(SingCoachTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundColor(SingCoachTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
