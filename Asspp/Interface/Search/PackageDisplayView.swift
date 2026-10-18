//
//  PackageDisplayView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

struct PackageDisplayView: View {
    let archive: AppStore.AppPackage
    @State var style: DisplayStyle = .compact

    enum DisplayStyle {
        case compact
        case detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArchivePreviewView(archive: archive, preferredIconSize: 64, lineLimit: nil)
            if !archive.software.description.isEmpty {
                Text(archive.software.description)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(style == .compact ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                Button(style == .compact ? String(localized: "More") : String(localized: "Less")) {
                    style = style == .compact ? .detail : .compact
                }
                .font(.caption.weight(.semibold)).buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
