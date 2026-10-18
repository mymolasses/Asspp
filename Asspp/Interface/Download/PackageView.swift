//
//  PackageView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import ButtonKit
import Kingfisher
import SwiftUI

#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
#endif

struct PackageView: View {
    @ObservedObject var pkg: PackageManifest

    var archive: AppStore.AppPackage {
        pkg.displayPackage
    }

    var url: URL {
        pkg.targetLocation
    }

    @Environment(\.dismiss) var dismiss
    #if os(iOS)
        @State private var installer: Installer?
    #endif
    #if os(macOS)
        @State private var showDeviceInstall = false
    #endif

    @State private var error = ""
    @State private var displayName = ""
    @State private var confirmDelete = false
    @State private var signingHint = ""

    @ObservedObject private var vm = AppStore.this
    @ObservedObject private var downloads = Downloads.this

    var body: some View {
        Form {
            Section {
                ArchivePreviewView(archive: archive, preferredIconSize: 64, lineLimit: nil)
            } header: {
                Text("Package")
            }

            Section {
                packageActions
            }
            #if os(macOS)
            if showDeviceInstall && pkg.completed { DeviceCTLInstallSection(package: pkg) }
            #endif

            Section {
                CopyableRow(label: "Bundle ID", value: archive.software.bundleID, monospaced: true)
                DetailValueRow(title: "Version", value: archive.software.version)
                DetailValueRow(title: "Developer", value: archive.software.sellerName)
                if !archive.software.primaryGenreName.isEmpty {
                    DetailValueRow(title: "Category", value: archive.software.primaryGenreName)
                }
                DetailValueRow(title: "Compatibility", value: "\(archive.software.minimumOsVersion)+")
                if archive.software.userRatingCount > 0 {
                    DetailValueRow(title: "Rating", value: "\(String(format: "%.1f", archive.software.averageUserRating)) (\(archive.software.userRatingCount))")
                }
            } header: {
                Text("Details")
            }

            if let links = pkg.appStoreLinks, let account = pkg.account {
                Section("App Store") {
                    AppStoreLinkButtons(links: links, region: account.regionCode)
                }
            }

            if let info = pkg.localIPA {
                Section {
                    TextField("Display Name (Optional)", text: $displayName)
                        .onSubmit { downloads.renameLocalIPA(pkg, to: displayName) }
                        .onChange(of: displayName) { name in
                            if name.count > 120 { displayName = String(name.prefix(120)) }
                        }
                    Button("Save Display Name") { downloads.renameLocalIPA(pkg, to: displayName) }
                    CopyableRow(label: "Original App Name", value: info.name)
                    CopyableRow(label: "Original File", value: info.originalFileName)
                    LabeledContent("Build Version", value: info.buildVersion)
                    LabeledContent("File Size", value: ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file))
                    AsyncButton {
                        error = ""
                        signingHint = ""
                        do {
                            try await downloads.refreshLocalIPAInfo(pkg)
                            signingHint = String(localized: "Signing information updated.")
                        } catch {
                            self.error = error.localizedDescription
                            throw error
                        }
                    } label: { Text("Check Signing Information") }
                    .disabledWhenLoading()
                    if !signingHint.isEmpty { Text(signingHint).foregroundStyle(.green) }
                } header: { Text("Local IPA") }
                IPASigningSection(info: info)
            }

            if !pkg.completed {
                Section {
                    let actions = downloads.getAvailableActions(for: pkg)
                    ForEach(actions.filter { $0 != .delete }, id: \.self) { action in
                        let label = downloads.getActionLabel(for: action)
                        Button(label.title) {
                            downloads.performDownloadAction(for: pkg, action: action)
                        }
                        .foregroundStyle(label.isDestructive ? .red : .primary)
                    }
                } header: {
                    Text("Incomplete Package")
                } footer: {
                    switch pkg.state.status {
                    case .pending:
                        Text("\(Int(pkg.state.percent * 100))%...")
                    case .downloading:
                        VStack(alignment: .leading, spacing: 8) {
                            SimpleProgress(progress: pkg.state.percent)
                            HStack {
                                Text("\(Int(pkg.state.percent * 100))%")
                                Spacer()
                                Text(pkg.state.speed.isEmpty ? "正在计算下载速度…" : "\(pkg.state.speed)/s")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    case .paused:
                        Text("Paused at \(Int(pkg.state.percent * 100))%")
                    case .completed:
                        Group {}
                    case .failed:
                        Text("Download failed.")
                    }
                }
            }

            if let account = pkg.account {
                Section {
                    Text(account.account.email)
                        .redacted(reason: .placeholder, isEnabled: vm.demoMode)
                    Text(account.regionName)
                } header: {
                    Text("Account")
                } footer: {
                    Text("This account is used to download this package. If you choose to AirDrop, your target device must sign in or previously signed in to this account and have at least one app installed.")
                }

            } else {
                Section {
                    Label("Imported from Files", systemImage: "folder")
                } header: { Text("Source") }
            }

            if let failure = pkg.state.error {
                Section { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            }
            if !error.isEmpty {
                Section { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }

        }
        .formStyle(.grouped)
        .navigationTitle(pkg.displayPackage.software.name)
        .onAppear { displayName = pkg.displayName }
        #if os(iOS)
        .sheet(item: $installer, onDismiss: {
            installer?.destroy()
            installer = nil
        }) { InstallerView(installer: $0) }
        #endif
        .confirmationDialog("Delete this package and its file?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                downloads.delete(request: pkg)
                dismiss()
            }
        }
    }

    private var packageActions: some View {
        HStack(spacing: 6) {
            #if os(iOS)
            AsyncButton {
                error = ""
                do {
                    installer = try await Installer(archive: archive, path: url, bundleVersion: pkg.installationBundleVersion)
                } catch {
                    self.error = error.localizedDescription
                    throw error
                }
            } label: { actionLabel("Install", symbol: "arrow.down.app", tint: .blue) }
            .disabledWhenLoading().disabled(!pkg.completed)
            #else
            Button { showDeviceInstall.toggle() } label: {
                actionLabel("Install", symbol: "arrow.down.app", tint: .blue)
            }
            .disabled(!pkg.completed)
            #endif
            ShareLink(item: url) {
                actionLabel("Share", symbol: "square.and.arrow.up", tint: .blue)
            }
            .disabled(!pkg.completed)
            NavigationLink { FileListView(packageURL: pkg.targetLocation) } label: {
                actionLabel("View Files", symbol: "folder", tint: .blue)
            }
            .disabled(!pkg.completed)
            #if os(macOS)
            .contextMenu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Copy File Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
            #endif
            Button { confirmDelete = true } label: {
                actionLabel("Delete", symbol: "trash", tint: .red)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private func actionLabel(_ title: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.body.weight(.medium))
            Text(title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint).frame(maxWidth: .infinity, minHeight: 58)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
