import SwiftUI

/// A small backport of `ContentUnavailableView` for iOS 16.
struct UnavailableView<Label: View, Description: View, Actions: View>: View {
    @ViewBuilder let label: () -> Label
    @ViewBuilder let description: () -> Description
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 12) {
            label()
                .font(.title2.weight(.semibold))
            description()
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
