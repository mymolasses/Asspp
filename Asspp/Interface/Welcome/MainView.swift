//
//  MainView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct MainView: View {
    var body: some View {
        #if os(macOS)
            MacSidebarMainView()
        #else
            LegacyTabMainView()
        #endif
    }
}

#if os(macOS)
    private struct MacSidebarMainView: View {
        @State private var selection: SidebarSection? = .home
        @ObservedObject private var downloads = Downloads.this

        var body: some View {
            NavigationSplitView {
                List(SidebarSection.allCases, selection: $selection) { section in
                    SidebarRow(section: section, downloads: downloads.runningTaskCount)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .navigationTitle("Asspp")
                .tint(.blue)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            } detail: {
                Group {
                    if let selection {
                        detailView(for: selection)
                    } else {
                        detailView(for: .home)
                    }
                }
                .frame(minHeight: 250)
                .navigationSplitViewColumnWidth(min: 480, ideal: 500)
            }
            // Expose the selection so menu commands (⌘F, ⌘,) can drive it.
            .focusedSceneValue(\.sidebarSelection, $selection)
            .environment(\.openLibraryTab, { tab in
                switch tab {
                case .home: selection = .home
                case .accounts: selection = .accounts
                case .search: selection = .search
                case .downloads: selection = .downloads
                case .settings: selection = .settings
                }
            })
        }

        @ViewBuilder
        private func detailView(for section: SidebarSection) -> some View {
            switch section {
            case .home:
                WelcomeView()
            case .accounts:
                AccountView()
            case .search:
                SearchView()
            case .downloads:
                DownloadView()
            case .installed:
                InstalledListView()
            case .settings:
                SettingView()
            }
        }
    }

    enum SidebarSection: Hashable, CaseIterable, Identifiable {
        case home
        case accounts
        case search
        case downloads
        case installed
        case settings

        var id: Self {
            self
        }

        var title: LocalizedStringKey {
            switch self {
            case .home:
                "Home"
            case .accounts:
                "Accounts"
            case .search:
                "Search"
            case .downloads:
                "Downloads"
            case .installed:
                "Installed"
            case .settings:
                "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .home:
                "house"
            case .accounts:
                "person"
            case .search:
                "magnifyingglass"
            case .downloads:
                "arrow.down.circle"
            case .installed:
                "square.stack.3d.up.badge.automatic.fill"
            case .settings:
                "gear"
            }
        }
    }

    private struct SidebarRow: View {
        let section: SidebarSection
        let downloads: Int

        var body: some View {
            HStack {
                Label(section.title, systemImage: section.systemImage)
                if section == .downloads, downloads > 0 {
                    Spacer()
                    Text("\(downloads)")
                        .font(.caption2.bold())
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private struct SidebarSelectionKey: FocusedValueKey {
        typealias Value = Binding<SidebarSection?>
    }

    extension FocusedValues {
        var sidebarSelection: Binding<SidebarSection?>? {
            get { self[SidebarSelectionKey.self] }
            set { self[SidebarSelectionKey.self] = newValue }
        }
    }

    /// Menu commands that jump to sidebar sections by keyboard shortcut.
    struct SidebarMenuCommands: Commands {
        @FocusedValue(\.sidebarSelection) private var selection

        var body: some Commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { selection?.wrappedValue = .settings }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(selection == nil)
            }
            CommandGroup(after: .sidebar) {
                Button("Search") {
                    selection?.wrappedValue = .search
                    SearchFieldFocus.shared.requestFocus()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(selection == nil)
            }
            CommandGroup(replacing: .help) {
                Button("Asspp Help", systemImage: "") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Lakr233/Asspp")!)
                }
            }
        }
    }
#else
    private struct LegacyTabMainView: View {
        @ObservedObject var dvm = Downloads.this
        @State private var selection: LibraryTab = .home

        var body: some View {
            TabView(selection: $selection) {
                WelcomeView()
                    .tag(LibraryTab.home)
                    .tabItem { Label("Home", systemImage: "house") }
                AccountView()
                    .tag(LibraryTab.accounts)
                    .tabItem { Label("Accounts", systemImage: "person") }
                SearchView()
                    .tag(LibraryTab.search)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                DownloadView()
                    .tag(LibraryTab.downloads)
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    .badge(dvm.runningTaskCount) // putting badge inside will not work on iOS versions before 18
                SettingView()
                    .tag(LibraryTab.settings)
                    .tabItem { Label("Settings", systemImage: "gear") }
            }
            .environment(\.openLibraryTab, { selection = $0 })
        }
    }

    @available(iOS 18.0, *)
    struct NewMainView: View {
        @ObservedObject var dvm = Downloads.this
        @State private var selection: LibraryTab = .home

        var body: some View {
            TabView(selection: $selection) {
                Tab("Home", systemImage: "house", value: LibraryTab.home) { WelcomeView() }
                Tab("Accounts", systemImage: "person", value: LibraryTab.accounts) { AccountView() }
                Tab("Search", systemImage: "magnifyingglass", value: LibraryTab.search) { SearchView() }
                Tab("Downloads", systemImage: "arrow.down.circle", value: LibraryTab.downloads) { DownloadView() }
                    .badge(dvm.runningTaskCount)
                Tab("Settings", systemImage: "gear", value: LibraryTab.settings) { SettingView() }
            }
            .environment(\.openLibraryTab, { selection = $0 })
            .neverMinimizeTab()
            .sidebarAdaptableTabView()
        }
    }
#endif
