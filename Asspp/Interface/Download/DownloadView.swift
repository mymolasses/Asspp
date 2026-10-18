import SwiftUI

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
            Group {
                if vm.manifests.isEmpty {
                    UnavailableView(
                        label: { Label("No Downloads", systemImage: "arrow.down.circle") },
                        description: { Text("Search for an app, add a download, or import a local IPA.") },
                        actions: {
                            Button("Import Local IPA") { showImport = true }
                            NavigationLink("Add Download") { AddDownloadView() }
                        }
                    )
                    .padding()
                } else {
                    Form {
                        Section {
                            LibraryPageHeader(title: "Downloads", subtitle: "Manage downloads and local IPA files.", symbol: "shippingbox.fill")
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { packageMetrics }
                                VStack(spacing: 12) { packageMetrics }
                            }
                        }
                        filters
                        Section {
                            if visiblePackages.isEmpty {
                                Text("No Matching Packages").foregroundStyle(.secondary)
                                Button("Reset Filters") { resetFilters() }
                            }
                            if viewMode == "grid" {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                                    ForEach(visiblePackages) { manifest in
                                        PackageManifestRow(manifest: manifest)
                                            .buttonStyle(.plain)
                                            .librarySurface()
                                    }
                                }
                                .padding(.vertical, 8)
                            } else {
                                ForEach(visiblePackages) { PackageManifestRow(manifest: $0) }
                            }
                        } header: {
                            Text("\(visiblePackages.count) Packages")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Downloads")
            .searchable(text: $query, prompt: "Search Packages")
            .navigationDestination(for: PackageManifest.self) { PackageView(pkg: $0) }
            .toolbar {
                ToolbarItem {
                    Button { viewMode = viewMode == "list" ? "grid" : "list" } label: {
                        Label(viewMode == "list" ? String(localized: "Grid View") : String(localized: "List View"),
                              systemImage: viewMode == "list" ? "square.grid.2x2" : "list.bullet")
                    }
                }
                ToolbarItem {
                    Menu {
                        Button { showImport = true } label: { Label("Import Local IPA", systemImage: "square.and.arrow.down") }
                        NavigationLink(destination: AddDownloadView()) { Label("Add Download", systemImage: "link") }
                    } label: {
                        Label("Add Package", systemImage: "plus")
                    }
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

    @ViewBuilder
    private var packageMetrics: some View {
        LibraryMetric(title: "Packages", value: vm.manifests.count, symbol: "shippingbox", tint: .blue)
        LibraryMetric(title: "Downloading", value: vm.runningTaskCount, symbol: "arrow.down.circle", tint: .purple)
        LibraryMetric(title: "Local IPA", value: vm.manifests.filter { $0.isLocal }.count, symbol: "folder", tint: .green)
    }

    private var filters: some View {
        Section {
            DisclosureGroup("Filters and Sort") {
                Picker("Source", selection: $source) {
                    Text("All Sources").tag("all")
                    Text("App Store").tag("store")
                    Text("Local IPA").tag("local")
                }
                Picker("Status", selection: $status) {
                    Text("All Statuses").tag("all")
                    Text("Completed").tag("completed")
                    Text("Downloading").tag("downloading")
                    Text("Pending").tag("pending")
                    Text("Paused").tag("paused")
                    Text("Failed").tag("failed")
                }
                Picker("Account", selection: $accountID) {
                    Text("All Accounts").tag("all")
                    ForEach(accountIDs, id: \.self) { id in
                        Text(id).tag(id).redacted(reason: .placeholder, isEnabled: accounts.demoMode)
                    }
                }
                Picker("Region", selection: $region) {
                    Text("All Regions").tag("all")
                    ForEach(regions, id: \.self) { store in
                        Text(AppStore.UserAccount.regionName(for: store)).tag(store)
                    }
                }
                Picker("Sort", selection: $sort) {
                    Text("Newest First").tag("newest")
                    Text("Name A–Z").tag("nameAsc")
                    Text("Name Z–A").tag("nameDesc")
                }
                if hasFilters { Button("Reset Filters") { resetFilters() } }
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
    @ObservedObject private var vm = Downloads.this
    @State private var confirmDelete = false

    var body: some View {
        NavigationLink(value: manifest) {
            VStack(spacing: 8) {
                ArchivePreviewView(archive: manifest.displayPackage)
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
        .confirmationDialog("Delete this package and its file?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { vm.delete(request: manifest) }
        }
        .contextMenu {
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
