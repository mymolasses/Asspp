//
//  StoreDownloadEndpoint.swift
//  ApplePackage
//
//  Created on 2026/6/12.
//

import Foundation

/// Product download endpoints. A bag-validated ent/download with local kbsync
/// is preferred; volumeStore, redownload and updateProduct provide recovery.
enum StoreDownloadEndpoint {
    case volumeStore
    case redownload
    case updateProduct(URL)
    case ent(URL)
    case redownloadAt(URL)

    /// The failureType returned by `volumeStore` that signals callers to retry
    /// with the `redownload` endpoint.
    static let retryableFailureType = "5002"

    /// The two endpoints name the external version ID differently in the payload.
    var externalVersionIDKey: String {
        switch self {
        case .volumeStore, .ent:
            return "externalVersionId"
        case .redownload, .redownloadAt, .updateProduct:
            return "appExtVrsId"
        }
    }

    func url(pod: String?, deviceIdentifier: String?) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        switch self {
        case .volumeStore:
            comps.host = Configuration.storeAPIHost(pod: pod)
            comps.path = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
        case .redownload:
            comps.host = "downloaddispatch.itunes.apple.com"
            comps.path = "/r/redownload"
        case let .updateProduct(endpoint), let .ent(endpoint), let .redownloadAt(endpoint):
            guard var updateComponents = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                try ensureFailed(Strings.invalidResponse)
            }
            if let deviceIdentifier {
                var items = updateComponents.queryItems ?? []
                items.removeAll { $0.name == "guid" }
                items.append(URLQueryItem(name: "guid", value: deviceIdentifier))
                updateComponents.queryItems = items
            }
            return try updateComponents.url.get()
        }
        if let deviceIdentifier {
            comps.queryItems = [URLQueryItem(name: "guid", value: deviceIdentifier)]
        }
        return try comps.url.get()
    }
}
