import ButtonKit
import SwiftUI

/// The same installation behavior is available on a package card and detail page.
struct PackageInstallButton: View {
    @ObservedObject var package: PackageManifest
    var compact = false
    @State private var failure = ""
    @State private var showFailure = false
    #if os(iOS)
    @State private var installer: Installer?
    #else
    @State private var showDevices = false
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            AsyncButton {
                do {
                    installer = try await Installer(archive: package.displayPackage, path: package.targetLocation, bundleVersion: package.installationBundleVersion)
                } catch {
                    failure = error.localizedDescription
                    showFailure = true
                    throw error
                }
            } label: { label }
            .disabledWhenLoading()
            .sheet(item: $installer, onDismiss: {
                installer?.destroy()
                installer = nil
            }) { InstallerView(installer: $0) }
            #else
            Button { showDevices = true } label: { label }
                .sheet(isPresented: $showDevices) {
                    NavigationStack {
                        Form { DeviceCTLInstallSection(package: package) }
                            .formStyle(.grouped).navigationTitle("Install")
                            .toolbar { Button("Done") { showDevices = false } }
                    }
                    .frame(minWidth: 480, minHeight: 320)
                }
            #endif
        }
        .buttonStyle(.plain).disabled(!package.completed)
        .alert("Install", isPresented: $showFailure) { Button("Done", role: .cancel) {} } message: { Text(failure) }
    }

    private var label: some View {
        LibraryActionLabel(title: "Install", symbol: "arrow.down.app", compact: compact)
    }
}
