import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#endif

enum ImportDocumentTypes {
    static let accountBackup = UTType(importedAs: "wiki.qaq.asspp.encrypted-backup", conformingTo: .data)
    static let ipa = UTType(importedAs: "wiki.qaq.asspp.ipa", conformingTo: .zip)

    static var backups: [UTType] { acceptedTypes(for: "enc", declared: accountBackup) }
    static var packages: [UTType] { acceptedTypes(for: "ipa", declared: ipa) }

    private static func acceptedTypes(for fileExtension: String, declared: UTType) -> [UTType] {
        // Include every registered interpretation of the extension. A Files
        // provider may advertise a different UTI than the one we declare.
        let types = [declared, UTType.item, .data] + UTType.types(tag: fileExtension, tagClass: .filenameExtension, conformingTo: nil)
        var identifiers = Set<String>()
        return types.filter { identifiers.insert($0.identifier).inserted }
    }
}

extension View {
    func importDocument(isPresented: Binding<Bool>, types: [UTType], completion: @escaping (Result<URL, Error>) -> Void) -> some View {
        modifier(DocumentImportModifier(isPresented: isPresented, types: types, completion: completion))
    }
}

private struct DocumentImportModifier: ViewModifier {
    @Binding var isPresented: Bool
    let types: [UTType]
    let completion: (Result<URL, Error>) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(isPresented: $isPresented) {
            NativeDocumentImportPicker(types: types, isPresented: $isPresented, completion: completion)
                .ignoresSafeArea()
        }
        #else
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: types, allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { completion(.success(url)) }
            case let .failure(error): completion(.failure(error))
            }
        }
        #endif
    }
}

#if os(iOS)
private struct NativeDocumentImportPicker: UIViewControllerRepresentable {
    let types: [UTType]
    @Binding var isPresented: Bool
    let completion: (Result<URL, Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Import a local copy instead of keeping an external document open.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NativeDocumentImportPicker
        init(parent: NativeDocumentImportPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            if let url = urls.first { parent.completion(.success(url)) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
#endif
