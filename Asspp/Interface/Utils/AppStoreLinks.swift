import ApplePackage
import SwiftUI

/// Keep country and app ID in both the redirect and its nested destination.
/// Imported IPAs have no verified App Store identity and do not expose links.
struct AppStoreLinks {
    let webPage: URL
    let regionalStore: URL

    init?(appID: Int64, region: String) {
        let country = region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard appID > 0, let storefront = ApplePackage.Configuration.storeId(for: country),
              let webPage = URL(string: "https://apps.apple.com/\(country.lowercased())/app/id\(appID)") else { return nil }
        var redirect = URLComponents(string: "https://itunes.apple.com/WebObjects/MZStore.woa/wa/resetAndRedirect")
        redirect?.queryItems = [
            URLQueryItem(name: "dsf", value: storefront),
            URLQueryItem(name: "mt", value: "8"),
            URLQueryItem(name: "cc", value: country.lowercased()),
            URLQueryItem(name: "url", value: "/WebObjects/MZStore.woa/wa/viewSoftware?mt=8&id=\(appID)&cc=\(country.lowercased())"),
        ]
        guard let regionalStore = redirect?.url else { return nil }
        self.webPage = webPage
        self.regionalStore = regionalStore
    }
}

struct AppStoreLinkButtons: View {
    let links: AppStoreLinks
    let region: String

    var body: some View {
        HStack(spacing: 10) {
            Link(destination: links.regionalStore) {
                tile("Regional Store", subtitle: AppStore.UserAccount.regionName(for: region), symbol: "arrow.up.forward.app", tint: .blue)
            }
            Link(destination: links.webPage) {
                tile("Store Details", subtitle: "apps.apple.com", symbol: "safari", tint: .purple)
            }
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: LocalizedStringKey, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.title3.weight(.medium))
                .frame(width: 28, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle).font(.caption2).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(tint).padding(.horizontal, 10).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.12)))
    }

}

extension PackageManifest {
    var appStoreLinks: AppStoreLinks? {
        guard !isLocal, let account else { return nil }
        return AppStoreLinks(appID: package.software.id, region: account.regionCode)
    }
}
