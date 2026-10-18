//
//  SearchView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

/// Lets menu commands ask the search field to take focus. SearchView consumes
/// the request on its next appearance, or immediately if already visible, and
/// clears it — so the one-shot survives the view being recreated when the user
/// switches sidebar sections.
@MainActor
final class SearchFieldFocus: ObservableObject {
    static let shared = SearchFieldFocus()
    @Published var pending = false
    func requestFocus() { pending = true }
}

struct SearchView: View {
    @AppStorage("searchKey") var searchKey = ""
    @AppStorage("searchRegion") var searchRegion = "US"
    @FocusState var searchKeyFocused
    @ObservedObject private var searchFocus = SearchFieldFocus.shared
    @State private var searchType = EntityType.iPhone

    @State private var searching = false
    let regionKeys = Array(ApplePackage.Configuration.storeFrontValues.keys.sorted())

    @State private var searchError: String?
    #if DEBUG
        @AppStorage("searchResults") // reduce API calls
        var searchResult: [AppStore.AppPackage] = []
    #else
        @State private var searchResult: [AppStore.AppPackage] = []
    #endif

    @State private var navigationPath = NavigationPath()
    @ObservedObject private var vm = AppStore.this
    var possibleRegion: Set<String> {
        vm.possibleRegions
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle("Search")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }

    var searchTypePicker: some View {
        Picker(selection: $searchType) {
            ForEach(EntityType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        } label: {
            Label("Type", systemImage: searchType.iconName)
        }
        .onChange(of: searchType) { _ in
            searchResult = []
        }
    }

    var possibleRegionKeys: [String] {
        regionKeys.filter { possibleRegion.contains($0) }
    }

    func searchRegionView() -> some View {
        Menu {
            if !possibleRegionKeys.isEmpty {
                buildPickView(
                    for: possibleRegionKeys,
                ) {
                    Label("Available Regions", systemImage: "checkmark.seal")
                }
                .pickerStyle(.inline)

                buildPickView(
                    for: regionKeys.filter { !possibleRegion.contains($0) },
                ) {
                    Label("All Regions", systemImage: "globe")
                }
                .pickerStyle(.menu)
            } else {
                buildPickView(
                    for: regionKeys,
                ) {
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label(AppStore.UserAccount.regionName(for: searchRegion), systemImage: "globe")
        }
        .onChange(of: searchRegion) { _ in
            searchResult = []
        }
    }

    var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Keyword", text: $searchKey)
                                .textFieldStyle(.plain).focused($searchKeyFocused)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .submitLabel(.search).onSubmit { search() }
                            if !searchKey.isEmpty {
                                Button { searchKey = ""; searchKeyFocused = true } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain).accessibilityLabel("Clear Search")
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        Button(action: search) {
                            Group {
                                if searching { ProgressView().tint(.white) }
                                else { Image(systemName: "arrow.right").font(.headline) }
                            }
                            .frame(width: 44, height: 44)
                            .foregroundStyle(.white)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Search Apps")
                        .disabled(searching || searchKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        searchTypePicker.pickerStyle(.menu)
                        Spacer(minLength: 8)
                        searchRegionView()
                    }
                    .font(.subheadline).disabled(searching)
                }
                .librarySurface()
                if let searchError {
                    Label(searchError, systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(.red).librarySurface()
                }
                if !searching && searchResult.isEmpty && searchError == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.blue.opacity(0.6))
                        Text("Search by app name or bundle ID.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 48)
                }
                if !searchResult.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResult) { item in
                            NavigationLink(value: ProductDestination(archive: item, region: searchRegion)) {
                                HStack(spacing: 12) {
                                    ArchivePreviewView(archive: item)
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.blue)
                                }
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if item.id != searchResult.last?.id { Divider().padding(.leading, 16) }
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06)))
                }
            }
            .frame(maxWidth: 1040).padding(16).frame(maxWidth: .infinity)
        }
        .background(Color.blue.opacity(0.035))
        .navigationDestination(for: ProductDestination.self) { dest in
            ProductView(archive: dest.archive, region: dest.region, navigationPath: $navigationPath)
        }
        .navigationDestination(for: PackageManifest.self) { PackageView(pkg: $0) }
        .navigationDestination(for: HistoryDestination.self) { destination in
            ProductHistoryView(accountID: destination.accountID, region: destination.region, package: destination.package)
        }
        .onAppear { consumePendingFocus() }
        .onChange(of: searchFocus.pending) { isPending in
            if isPending { consumePendingFocus() }
        }
    }

    /// Focuses the search field if a focus request is pending (e.g. after the
    /// ⌘F menu command on macOS), then clears the request.
    private func consumePendingFocus() {
        guard searchFocus.pending else { return }
        searchFocus.pending = false
        // Defer so the search field exists when focus is assigned, whether the
        // view was already visible or is appearing for the first time.
        DispatchQueue.main.async { searchKeyFocused = true }
    }

    func buildPickView(for keys: [String], @ViewBuilder label: () -> some View) -> some View {
        Picker(selection: $searchRegion) {
            ForEach(keys, id: \.self) { key in
                Text("\(AppStore.UserAccount.regionName(for: key)) · \(key)")
                    .tag(key)
            }
        } label: {
            label()
        }
    }

    func search() {
        let term = searchKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !searching else { return }
        let region = searchRegion
        let entity = searchType
        searchKeyFocused = false
        searching = true
        searchError = nil
        logger.info("search: term=\(searchKey) region=\(searchRegion) type=\(searchType.rawValue)")
        Task {
            do {
                var result = try await ApplePackage.Searcher.search(
                    term: term,
                    countryCode: region,
                    limit: 32,
                    entityType: entity,
                )
                if let app = try? await ApplePackage.Lookup.lookup(
                    bundleID: term,
                    countryCode: region,
                ) {
                    result.removeAll { $0.bundleID == app.bundleID }
                    result.insert(app, at: 0)
                }
                logger.info("search completed: \(result.count) results for term=\(searchKey)")
                await MainActor.run {
                    searching = false
                    searchResult = result.map { AppStore.AppPackage(software: $0) }
                    searchError = nil
                }
            } catch {
                logger.error("search failed: term=\(searchKey) error=\(error.localizedDescription)")
                await MainActor.run {
                    searching = false
                    searchResult = []
                    searchError = error.localizedDescription
                }
            }
        }
    }
}

struct ProductDestination: Hashable {
    let archive: AppStore.AppPackage
    let region: String
}

/// Navigation identity must not depend on mutable account or package metadata.
struct HistoryDestination: Hashable {
    private let id = UUID()
    let accountID: String
    let region: String
    let package: AppStore.AppPackage

    init(accountID: String, region: String, package: AppStore.AppPackage) {
        self.accountID = accountID
        self.region = region
        self.package = package
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#if DEBUG
    private typealias AppPackages = [AppStore.AppPackage]
    extension AppPackages: @retroactive RawRepresentable {
        public init?(rawValue: String) {
            guard
                let data = rawValue.data(using: .utf8),
                let decoded = try? JSONDecoder().decode([AppStore.AppPackage].self, from: data)
            else { return nil }

            self = decoded
        }

        public var rawValue: String {
            guard let data = try? JSONEncoder().encode(self),
                  let rawValue = String(data: data, encoding: .utf8)
            else { return "" }

            return rawValue
        }
    }
#endif

extension ApplePackage.EntityType {
    var iconName: String {
        switch self {
        case .iPhone:
            "iphone"
        case .iPad:
            "ipad"
        case .appleTV:
            "appletv"
        }
    }
}
