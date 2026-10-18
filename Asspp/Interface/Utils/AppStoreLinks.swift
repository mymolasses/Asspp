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
        Link(destination: links.regionalStore) {
            Label("Open Regional App Store", systemImage: "arrow.up.forward.app")
        }
        LabeledContent("Region", value: AppStore.UserAccount.regionName(for: region))
        Link(destination: links.webPage) {
            Label("App Store Details", systemImage: "safari")
        }
    }
}

extension PackageManifest {
    var appStoreLinks: AppStoreLinks? {
        guard !isLocal, let account else { return nil }
        return AppStoreLinks(appID: package.software.id, region: account.regionCode)
    }
}
