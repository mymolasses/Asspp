import SwiftUI
import UniformTypeIdentifiers

struct ImportIPAView: View {
    let onImport: (PackageManifest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var file: URL?
    @State private var displayName = ""
    @State private var importing = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showPicker = true } label: {
                        Label(file?.lastPathComponent ?? String(localized: "Choose IPA File"), systemImage: "shippingbox")
                            .lineLimit(2)
                    }
                    TextField("Display Name (Optional)", text: $displayName)
                        .onChange(of: displayName) { name in
                            if name.count > 120 { displayName = String(name.prefix(120)) }
                        }
                } footer: {
                    Text("Import an IPA from Files. A copy is saved in your package library. The display name does not change the app or its signature.")
                }
                .disabled(importing)
                Section {
                    Button {
                        Task { await importFile() }
                    } label: {
                        HStack {
                            if importing { ProgressView().controlSize(.small) }
                            Text(importing ? String(localized: "Importing IPA…") : String(localized: "Import IPA"))
                        }
                    }
                    .disabled(file == nil || importing)
                } footer: {
                    Text("Import preserves the original IPA. Installation depends on its signing, provisioning profile, and device eligibility.")
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import Local IPA")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(importing)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 380)
        #endif
        .interactiveDismissDisabled(importing)
        .importDocument(isPresented: $showPicker, types: ImportDocumentTypes.packages) { result in
            do {
                let url = try result.get()
                guard url.pathExtension.lowercased() == "ipa" else { throw LocalIPAReader.Failure.invalidIPA }
                file = url
                error = ""
            } catch { self.error = error.localizedDescription }
        }
    }

    @MainActor
    private func importFile() async {
        guard let file, !importing else { return }
        importing = true
        error = ""
        defer { importing = false }
        do {
            let manifest = try await Downloads.this.importLocalIPA(from: file, displayName: displayName)
            onImport(manifest)
        } catch { self.error = error.localizedDescription }
    }
}
