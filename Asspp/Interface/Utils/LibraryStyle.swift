import SwiftUI

struct LibraryPageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2.weight(.semibold))
                .foregroundStyle(.blue).frame(width: 48, height: 48)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct LibraryMetric: View {
    let title: LocalizedStringKey
    let value: Int
    let symbol: String
    var tint: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).font(.title3)
            Text(value, format: .number).font(.largeTitle.bold()).monospacedDigit()
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func librarySurface() -> some View {
        self.padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06)))
    }
}
