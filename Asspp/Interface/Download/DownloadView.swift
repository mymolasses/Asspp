import SwiftUI
import Kingfisher

struct DownloadView: View {
    @ObservedObject private var vm = Downloads.this
    @ObservedObject private var accounts = AppStore.this
    @State private var path = NavigationPath()
    @State private var showImport = false
    @State private var importedPackage: PackageManifest?
    @State private var query = ""
    @State private var source = "all"
    @State private var status = "all"
    @State private var accountID = "all"
    @State private var region = "all"
    @AppStorage("DownloadsSortOrder") private var sort = "newest"
    @AppStorage("DownloadsViewMode") private var viewMode = "grid"

    private var hasFilters: Bool {
        !query.isEmpty || source != "all" || status != "all" || accountID != "all" || region != "all"
    }

    private var regions: [String] {
        Array(Set(vm.manifests.compactMap { $0.account?.regionCode })).sorted()
    }

    private var accountIDs: [String] {
        Array(Set(vm.manifests.compactMap { $0.account?.id })).sorted()
    }

    private var visiblePackages: [PackageManifest] {
        vm.manifests.filter { manifest in
            let matchesText = query.isEmpty || [manifest.displayPackage.software.name, manifest.package.software.bundleID,
                manifest.account?.id ?? "", manifest.localIPA?.originalFileName ?? ""]
                .contains { $0.localizedStandardContains(query) }
            return matchesText && (source == "all" || (source == "local" ? manifest.isLocal : !manifest.isLocal))
                && (status == "all" || manifest.state.status.rawValue == status)
                && (accountID == "all" || manifest.account?.id == accountID)
                && (region == "all" || manifest.account?.regionCode == region)
        }.sorted {
            switch sort {
            case "nameAsc": $0.displayPackage.software.name.localizedStandardCompare($1.displayPackage.software.name) == .orderedAscending
            case "nameDesc": $0.displayPackage.software.name.localizedStandardCompare($1.displayPackage.software.name) == .orderedDescending
            default: $0.creation > $1.creation
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filters
                    if vm.manifests.isEmpty {
                        UnavailableView(
                            label: { Label("No Downloads", systemImage: "arrow.down.circle") },
                            description: { Text("Search for an app, add a download, or import a local IPA.") },
                            actions: {
                                Button("Import Local IPA") { showImport = true }
                                NavigationLink("Add Download") { AddDownloadView() }
                            }
                        ).frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else if visiblePackages.isEmpty {
                        Text("No Matching Packages").foregroundStyle(.secondary)
                        Button("Reset Filters") { resetFilters() }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .top), count: viewMode == "grid" ? 3 : 1), alignment: .leading, spacing: 12) {
                            ForEach(visiblePackages) { manifest in
                                PackageManifestRow(manifest: manifest, compact: viewMode == "grid")
                                    .buttonStyle(.plain)
                                    .padding(viewMode == "grid" ? 8 : 16)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color.blue.opacity(0.035))
            .navigationTitle("Downloads")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: "Search Packages")
            .navigationDestination(for: PackageManifest.self) { PackageView(pkg: $0) }
            .toolbar {
                ToolbarItem {
                    Button { viewMode = viewMode == "grid" ? "list" : "grid" } label: {
                        Label(viewMode == "grid" ? String(localized: "One Per Row") : String(localized: "Three Per Row"),
                              systemImage: viewMode == "grid" ? "rectangle.grid.1x2" : "square.grid.3x1")
                    }
                    .help(viewMode == "grid" ? String(localized: "One Per Row") : String(localized: "Three Per Row"))
                }
                ToolbarItem {
                    Menu {
                        Button { showImport = true } label: { Label("Import Local IPA", systemImage: "square.and.arrow.down") }
                        NavigationLink(destination: AddDownloadView()) { Label("Add Download", systemImage: "link") }
                    } label: { Label("Add Package", systemImage: "plus") }
                }
            }
        }
        .sheet(isPresented: $showImport, onDismiss: {
            if let importedPackage {
                resetFilters()
                path.append(importedPackage)
                self.importedPackage = nil
            }
        }) {
            ImportIPAView { manifest in
                importedPackage = manifest
                showImport = false
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterRow("Source", selection: $source, options: [
                ("all", String(localized: "All Sources")), ("store", "App Store"), ("local", String(localized: "Local IPA")),
            ])
            filterRow("Status", selection: $status, options: [
                ("all", String(localized: "All Statuses")), ("completed", String(localized: "Completed")),
                ("downloading", String(localized: "Downloading")), ("pending", String(localized: "Pending")),
                ("paused", String(localized: "Paused")), ("failed", String(localized: "Failed")),
            ])
            filterRow("Account", selection: $accountID,
                      options: [("all", String(localized: "All Accounts"))] + accountIDs.map { ($0, $0) }, privateValues: true)
            filterRow("Region", selection: $region,
                      options: [("all", String(localized: "All Regions"))] + regions.map { ($0, AppStore.UserAccount.regionName(for: $0)) })
            filterRow("Sort", selection: $sort, options: [
                ("newest", String(localized: "Newest First")), ("nameAsc", String(localized: "Name A–Z")), ("nameDesc", String(localized: "Name Z–A")),
            ])
            if hasFilters { Button("Reset Filters") { resetFilters() }.font(.caption) }
        }
        .librarySurface()
    }

    private func filterRow(_ title: LocalizedStringKey, selection: Binding<String>, options: [(String, String)], privateValues: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.0) { option in
                        Button { selection.wrappedValue = option.0 } label: {
                            Text(option.1)
                                .redacted(reason: .placeholder, isEnabled: privateValues && option.0 != "all" && accounts.demoMode)
                                .font(.subheadline.weight(.medium)).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .foregroundStyle(selection.wrappedValue == option.0 ? Color.white : Color.primary)
                                .background(selection.wrappedValue == option.0 ? Color.blue : Color.secondary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection.wrappedValue == option.0 ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func resetFilters() {
        query = ""
        source = "all"
        status = "all"
        accountID = "all"
        region = "all"
    }
}

private struct PackageManifestRow: View {
    @ObservedObject var manifest: PackageManifest
    var compact = false
    @ObservedObject private var vm = Downloads.this
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: manifest) {
                VStack(spacing: 8) {
                    if compact {
                        compactPreview
                    } else {
                        ArchivePreviewView(archive: manifest.displayPackage)
                    }
                    if !compact {
                        VStack(alignment: .leading, spacing: 4) {
                            if let account = manifest.account {
                                Text("下载账号：\(account.account.email)")
                                    .lineLimit(1).truncationMode(.middle)
                                    .redacted(reason: .placeholder, isEnabled: AppStore.this.demoMode)
                                Text("地区：\(account.regionName)")
                            } else {
                                Label("Local IPA", systemImage: "folder")
                                if let info = manifest.localIPA {
                                    Text(ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file))
                                }
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        SimpleProgress(progress: manifest.state.percent)
                            .animation(.interactiveSpring, value: manifest.state.percent)
                        HStack {
                            Text(manifest.hint)
                            Spacer()
                            Text(manifest.creation.formatted())
                        }
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if !compact, let links = manifest.appStoreLinks {
                HStack {
                    Link(destination: links.regionalStore) {
                        Label("Open Regional App Store", systemImage: "arrow.up.forward.app")
                    }
                    Spacer(minLength: 8)
                    Link(destination: links.webPage) {
                        Label("App Store Details", systemImage: "safari")
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .confirmationDialog("Delete this package and its file?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { vm.delete(request: manifest) }
        }
        .contextMenu {
            if let links = manifest.appStoreLinks {
                Link(destination: links.regionalStore) {
                    Label("Open Regional App Store", systemImage: "arrow.up.forward.app")
                }
                Link(destination: links.webPage) {
                    Label("App Store Details", systemImage: "safari")
                }
            }
            if manifest.completed {
                ShareLink(item: manifest.targetLocation) { Label("Share IPA", systemImage: "square.and.arrow.up") }
            }
            let actions = vm.getAvailableActions(for: manifest)
            ForEach(actions, id: \.self) { action in
                let label = vm.getActionLabel(for: action)
                Button(role: label.isDestructive ? .destructive : .none) {
                    if action == .delete { confirmDelete = true }
                    else { vm.performDownloadAction(for: manifest, action: action) }
                } label: {
                    Label(label.title, systemImage: label.systemImage)
                }
            }
        }
    }

    private var compactPreview: some View {
        VStack(spacing: 8) {
            KFImage(URL(string: manifest.package.software.artworkUrl))
                .placeholder {
                    Image(systemName: "shippingbox.fill").resizable().scaledToFit().padding(12).foregroundStyle(.secondary)
                }
                .resizable().scaledToFit().frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(manifest.displayPackage.software.name)
                .font(.caption.weight(.semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
            Text(manifest.package.software.version).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            SimpleProgress(progress: manifest.state.percent)
            Text(manifest.hint).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

extension PackageManifest {
    var hint: String {
        if let error = state.error {
            return error
        }
        return switch state.status {
        case .pending:
            String(localized: "Pending...")
        case .downloading:
            [
                String(Int(state.percent * 100)) + "%",
                state.speed.isEmpty ? "" : state.speed + "/s",
            ]
            .compactMap(\.self)
            .joined(separator: " ")
        case .paused:
            String(localized: "Paused")
        case .completed:
            String(localized: "Completed")
        case .failed:
            String(localized: "Failed")
        }
    }
}
