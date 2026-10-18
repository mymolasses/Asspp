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
    @State private var activeFilter = "source"
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
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        NavigationLink { AddDownloadView() } label: {
                            Label("Add Download", systemImage: "link").frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        Button { showImport = true } label: {
                            Label("Import Local IPA", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .foregroundStyle(.white).background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .font(.caption.weight(.semibold)).buttonStyle(.plain)
                    filters
                    if vm.manifests.isEmpty {
                        UnavailableView(label: { Label("No Downloads", systemImage: "arrow.down.circle") },
                            description: { Text("Search for an app, add a download, or import a local IPA.") },
                            actions: { Button("Import Local IPA") { showImport = true } })
                            .frame(maxWidth: .infinity).padding(.vertical, 32)
                    } else if visiblePackages.isEmpty {
                        Text("No Matching Packages").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
                        Button("Reset Filters") { resetFilters() }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .top), count: viewMode == "grid" ? 3 : 1), alignment: .leading, spacing: 12) {
                            ForEach(visiblePackages) { manifest in
                                PackageManifestRow(manifest: manifest, compact: viewMode == "grid")
                            }
                        }
                    }
                }
                .frame(maxWidth: 1040).padding(16).frame(maxWidth: .infinity)
            }
            .background(Color.blue.opacity(0.035))
            .navigationTitle("Downloads")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: PackageManifest.self) { PackageView(pkg: $0) }
        }
        .sheet(isPresented: $showImport, onDismiss: {
            if let importedPackage {
                resetFilters()
                path.append(importedPackage)
                self.importedPackage = nil
            }
        }) {
            ImportIPAView { manifest in importedPackage = manifest; showImport = false }
        }
    }

    private var filters: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Packages", text: $query).textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if hasFilters {
                    Button("Reset Filters") { resetFilters() }.font(.caption)
                }
            }
            .padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            LazyVGrid(columns: [GridItem(.flexible(minimum: 0)), GridItem(.flexible(minimum: 0))], spacing: 8) {
                filterField("Account", key: "account", value: accountOptions.first { $0.0 == accountID }?.1 ?? accountID, privateValue: accountID != "all")
                filterField("Region", key: "region", value: regionOptions.first { $0.0 == region }?.1 ?? region)
                filterField("Source", key: "source", value: sourceOptions.first { $0.0 == source }?.1 ?? source)
                filterField("Status", key: "status", value: statusOptions.first { $0.0 == status }?.1 ?? status)
                filterField("Sort", key: "sort", value: sortOptions.first { $0.0 == sort }?.1 ?? sort)
                Picker("Layout", selection: $viewMode) {
                    Text("Compact").tag("grid")
                    Text("Detailed").tag("list")
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activeOptions, id: \.0) { option in
                        Button { activeSelection.wrappedValue = option.0 } label: {
                            Text(option.1).lineLimit(1)
                                .redacted(reason: .placeholder, isEnabled: activeFilter == "account" && option.0 != "all" && accounts.demoMode)
                                .font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 9)
                                .foregroundStyle(activeSelection.wrappedValue == option.0 ? Color.white : Color.primary)
                                .background(activeSelection.wrappedValue == option.0 ? Color.blue : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(activeSelection.wrappedValue == option.0 ? .isSelected : [])
                    }
                }
            }
        }
        .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func filterField(_ title: LocalizedStringKey, key: String, value: String, privateValue: Bool = false) -> some View {
        Button { activeFilter = key } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text(value).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                        .redacted(reason: .placeholder, isEnabled: privateValue && accounts.demoMode)
                    Spacer(minLength: 2)
                    Image(systemName: activeFilter == key ? "chevron.up" : "chevron.down").font(.caption2)
                }
            }
            .foregroundStyle(activeFilter == key ? Color.blue : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(activeFilter == key ? Color.blue.opacity(0.4) : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var sourceOptions: [(String, String)] { [("all", String(localized: "All Sources")), ("store", "App Store"), ("local", String(localized: "Local IPA"))] }
    private var statusOptions: [(String, String)] {
        [("all", String(localized: "All Statuses")), ("completed", String(localized: "Completed")), ("downloading", String(localized: "Downloading")),
         ("pending", String(localized: "Pending")), ("paused", String(localized: "Paused")), ("failed", String(localized: "Failed"))]
    }
    private var accountOptions: [(String, String)] { [("all", String(localized: "All Accounts"))] + accountIDs.map { ($0, $0) } }
    private var regionOptions: [(String, String)] { [("all", String(localized: "All Regions"))] + regions.map { ($0, AppStore.UserAccount.regionName(for: $0)) } }
    private var sortOptions: [(String, String)] { [("newest", String(localized: "Newest First")), ("nameAsc", String(localized: "Name A–Z")), ("nameDesc", String(localized: "Name Z–A"))] }
    private var activeOptions: [(String, String)] {
        switch activeFilter {
        case "account": accountOptions
        case "region": regionOptions
        case "status": statusOptions
        case "sort": sortOptions
        default: sourceOptions
        }
    }
    private var activeSelection: Binding<String> {
        switch activeFilter {
        case "account": $accountID
        case "region": $region
        case "status": $status
        case "sort": $sort
        default: $source
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
        Group {
            if compact {
                NavigationLink(value: manifest) {
                    VStack(spacing: 8) {
                        icon(size: 54)
                        Text(manifest.displayPackage.software.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text("\(manifest.package.software.version) · \(manifest.account?.regionCode ?? String(localized: "Local IPA"))")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(12).contentShape(Rectangle())
                }
            } else {
                detailedCard.padding(16)
            }
        }
        .buttonStyle(.plain)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
        .confirmationDialog("Delete this package and its file?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { vm.delete(request: manifest) }
        }
        .contextMenu {
            if let links = manifest.appStoreLinks {
                Link("Open Regional App Store", destination: links.regionalStore)
                Link("App Store Details", destination: links.webPage)
            }
            if manifest.completed { ShareLink(item: manifest.targetLocation) { Label("Share IPA", systemImage: "square.and.arrow.up") } }
            ForEach(vm.getAvailableActions(for: manifest), id: \.self) { action in
                let label = vm.getActionLabel(for: action)
                Button(role: label.isDestructive ? .destructive : .none) {
                    if action == .delete { confirmDelete = true }
                    else { vm.performDownloadAction(for: manifest, action: action) }
                } label: { Label(label.title, systemImage: label.systemImage) }
            }
        }
    }

    private var detailedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: manifest) {
                HStack(alignment: .top, spacing: 12) {
                    icon(size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manifest.displayPackage.software.name).font(.subheadline.bold()).lineLimit(1)
                        Text(manifest.package.software.sellerName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(manifest.package.software.bundleID).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(manifest.completed ? String(localized: "Completed") : manifest.hint)
                        .font(.caption2.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .foregroundStyle(manifest.completed ? Color.green : Color.blue)
                        .background((manifest.completed ? Color.green : Color.blue).opacity(0.08), in: Capsule())
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                summary("Version", value: manifest.package.software.version)
                summary("File Size", value: fileSize)
                summary("Compatibility", value: "\(manifest.package.software.minimumOsVersion)+")
                summary("Region", value: manifest.account?.regionName ?? String(localized: "Local IPA"))
            }
            if let account = manifest.account {
                Text(account.id).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .redacted(reason: .placeholder, isEnabled: AppStore.this.demoMode)
            }
            if !manifest.completed {
                SimpleProgress(progress: manifest.state.percent)
                Text(manifest.hint).font(.caption).foregroundStyle(manifest.state.error == nil ? Color.secondary : Color.red)
            }
            if let links = manifest.appStoreLinks, let account = manifest.account {
                AppStoreLinkButtons(links: links, region: account.regionCode)
            }
            HStack(spacing: 10) {
                NavigationLink(value: manifest) { Text("View Details").frame(maxWidth: .infinity, minHeight: 40) }
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                if let action = vm.getAvailableActions(for: manifest).first(where: { $0 != .delete }) {
                    let label = vm.getActionLabel(for: action)
                    Button { vm.performDownloadAction(for: manifest, action: action) } label: {
                        Text(label.title).frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .foregroundStyle(.blue).background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text("Delete").frame(maxWidth: .infinity, minHeight: 40)
                }
                .foregroundStyle(.red).background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            .font(.caption.weight(.medium))
        }
    }

    private var fileSize: String {
        let bytes = manifest.localIPA?.fileSize ?? Int64(manifest.package.software.fileSizeBytes ?? "") ?? 0
        return bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "—"
    }

    private func icon(size: CGFloat) -> some View {
        KFImage(URL(string: manifest.package.software.artworkUrl))
            .placeholder { Image(systemName: "shippingbox.fill").resizable().scaledToFit().padding(10).foregroundStyle(.secondary) }
            .setProcessor(DownsamplingImageProcessor(size: CGSize(width: size * 3, height: size * 3)))
            .resizable().scaledToFit().frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }

    private func summary(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
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
