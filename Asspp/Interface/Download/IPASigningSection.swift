import SwiftUI

struct IPASigningSection: View {
    let info: LocalIPAInfo

    var body: some View {
        Section {
            LabeledContent("Profile Type", value: info.signing.profileType.title)
            LabeledContent("Code Signature Resources", value: info.signing.hasCodeResources ? String(localized: "Present") : String(localized: "Missing"))
            if let name = info.signing.profileName { LabeledContent("Profile Name", value: name) }
            if let team = info.signing.teamName { LabeledContent("Team", value: team) }
            if !info.signing.teamIdentifiers.isEmpty {
                CopyableRow(label: "Team ID", value: info.signing.teamIdentifiers.joined(separator: ", "), monospaced: true)
            }
            if let identifier = info.signing.applicationIdentifier {
                CopyableRow(label: "Application Identifier", value: identifier, monospaced: true)
            }
            if let expiration = info.signing.expiration {
                LabeledContent("Profile Expires", value: expiration.formatted())
                    .foregroundStyle(info.signing.expired ? Color.red : Color.primary)
            }
            if let count = info.signing.provisionedDeviceCount {
                LabeledContent("Provisioned Devices", value: "\(count)")
            }
            ForEach(Array(info.signing.certificateNames.enumerated()), id: \.offset) { _, name in
                LabeledContent("Certificate", value: name)
            }
            if info.signing.expired { Label("The provisioning profile has expired.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if !info.signing.matches(bundleID: info.bundleID) {
                Label("The profile does not match this bundle ID.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if info.signing.profileType == .adHoc || info.signing.profileType == .development {
                Text("This profile requires a registered device.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Signing Information")
        } footer: {
            Text("This reads embedded provisioning metadata. It does not verify the code signature or certificate revocation, and does not guarantee installation.")
        }
    }
}
