import SwiftUI

/// Shared cell for commands and store destinations in an action grid.
struct LibraryActionLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    var subtitle: String? = nil
    var tint: Color = .blue
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 9) {
            Image(systemName: symbol).font(compact ? .subheadline : .title3.weight(.medium))
                .frame(width: compact ? 18 : 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                if let subtitle {
                    Text(subtitle).font(.caption2).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(tint).padding(.horizontal, compact ? 8 : 10)
        .frame(maxWidth: .infinity, minHeight: compact ? 40 : 62, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.12)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
