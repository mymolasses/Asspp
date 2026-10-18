//
//  ArchivePreviewView.swift
//  Asspp
//
//  Created by 秋星桥 on 2024/7/11.
//

import ApplePackage
import Kingfisher
import SwiftUI

struct ArchivePreviewView: View {
    let archive: AppStore.AppPackage
    var preferredIconSize: CGFloat?
    var lineLimit: Int? = 1

    private var iconSize: CGFloat { preferredIconSize ?? 50 }

    private var screenScale: CGFloat {
        #if canImport(UIKit)
            UIScreen.main.scale
        #else
            NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KFImage(URL(string: archive.software.artworkUrl))
                .placeholder {
                    Image(systemName: "shippingbox.fill")
                        .resizable().scaledToFit().padding(10)
                        .foregroundStyle(.secondary)
                }
                // Downsample the 512x512 artwork to the cell size instead of
                // decoding it at full resolution for a ~50pt icon.
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: iconSize, height: iconSize)))
                .scaleFactor(screenScale)
                .cacheOriginalImage()
                .antialiased(true)
                .resizable()
                .clipShape(.rect(cornerRadius: 0.2184466 * iconSize))
                .frame(width: iconSize, height: iconSize, alignment: .center)
                .shadow(radius: 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(archive.software.name)
                    .font(preferredIconSize == nil ? .headline : .title3.weight(.semibold))
                    .lineLimit(lineLimit).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !archive.software.sellerName.isEmpty {
                    Text(archive.software.sellerName).font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(lineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(archive.software.version).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
