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

struct RegionalStoreButton: View {
    let links: AppStoreLinks
    let region: String

    var body: some View {
        Link(destination: links.regionalStore) {
            LibraryActionLabel(title: "Regional Store", symbol: "arrow.up.forward.app", subtitle: AppStore.UserAccount.regionName(for: region))
        }
    }
}

struct StoreDetailsButton: View {
    let links: AppStoreLinks

    var body: some View {
        Link(destination: links.webPage) {
            LibraryActionLabel(title: "Store Details", symbol: "safari", subtitle: "apps.apple.com", tint: .purple)
        }
    }
}

struct AppStoreLinkButtons: View {
    let links: AppStoreLinks
    let region: String

    var body: some View {
        HStack(spacing: 10) {
            RegionalStoreButton(links: links, region: region)
            StoreDetailsButton(links: links)
        }
        .buttonStyle(.plain)
    }
}

extension PackageManifest {
    var appStoreLinks: AppStoreLinks? {
        guard !isLocal, let account else { return nil }
        return AppStoreLinks(appID: package.software.id, region: account.regionCode)
    }
}
