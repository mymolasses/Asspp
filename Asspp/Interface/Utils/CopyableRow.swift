import SwiftUI

/// Keep short values inline; move long values below the label rather than
/// compressing both columns into several narrow, uneven lines.
struct DetailValueRow: View {
    let title: LocalizedStringKey
    let value: String
    var monospaced = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(title).fixedSize()
                Spacer(minLength: 12)
                valueText.fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                valueText.fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    private var valueText: some View {
        Text(value).font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
            .foregroundStyle(.secondary).textSelection(.enabled)
    }
}

struct CopyableRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        DetailValueRow(title: LocalizedStringKey(label), value: value, monospaced: monospaced)
    }
}
