import SwiftUI

struct WelcomeView: View {
    @ObservedObject private var accounts = AppStore.this
    @ObservedObject private var downloads = Downloads.this
    @State private var openInstruction = false
    @Environment(\.openLibraryTab) private var openTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10), count: 3), spacing: 10) {
                        LibraryMetric(title: "Accounts", value: accounts.accounts.count, symbol: "person.2.fill")
                        LibraryMetric(title: "Downloading", value: downloads.runningTaskCount, symbol: "arrow.down.circle.fill", tint: .purple)
                        LibraryMetric(title: "Packages", value: downloads.manifests.filter { $0.completed }.count, symbol: "shippingbox.fill", tint: .green)
                    }
                    Text("Quick Actions").font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                        Button { openTab?(.accounts) } label: {
                            action("Accounts", subtitle: "Manage Apple IDs and encrypted backups.", symbol: "person.2", tint: .blue)
                        }
                        Button { openTab?(.search) } label: {
                            action("Search", subtitle: "Find apps across App Store regions.", symbol: "magnifyingglass", tint: .purple)
                        }
                        Button { openTab?(.downloads) } label: {
                            action("Downloads", subtitle: "Manage downloads and local IPA files.", symbol: "shippingbox", tint: .green)
                        }
                    }
                    .buttonStyle(.plain)
                    Label("The App Store API can be unstable. Retry if an error occurs.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Text(version).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Help", systemImage: "questionmark.circle") { openInstruction = true }.font(.caption)
                    }
                }
                .frame(maxWidth: 1040).padding(24).frame(maxWidth: .infinity)
            }
            .background(Color.blue.opacity(0.035))
            .navigationTitle("Home")
            .sheet(isPresented: $openInstruction) { SimpleInstruction().padding(32) }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("App Store", systemImage: "square.stack.3d.up")
                .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.16), in: Capsule())
            Text("Welcome to Asspp").font(.largeTitle.bold())
            Text("Your apps, accounts and IPA library in one place.")
                .foregroundStyle(.white.opacity(0.85))
            Button {
                openTab?(accounts.accounts.isEmpty ? .accounts : .search)
            } label: {
                HStack {
                    Text(accounts.accounts.isEmpty ? String(localized: "Add Account") : String(localized: "Search Apps"))
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.bold()).foregroundStyle(.blue)
                .padding(.horizontal, 18).padding(.vertical, 12).background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(28)
        .background(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
    }

    private func action(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint).frame(width: 42, height: 42)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading).librarySurface()
    }
}
