//
//  RoastTargetPhotoHelper.swift
//  thebitbinder
//
//  Shared image downscaling utilities for roast target photo handling.
//  Centralises the downscale logic used by AddRoastTargetView and
//  RoastTargetDetailView so both views cap stored + displayed images
//  at consistent resolutions without duplicating code.
//

import UIKit
import SwiftUI

enum RoastTargetPhotoHelper {

    /// Scales `image` so its longest edge is at most `maxLongEdge` pixels.
    /// Returns the original image unchanged if it is already small enough.
    /// The returned image always has a fresh backing store (never COW-shares
    /// with the source), so the source can be released immediately after.
    static func downscale(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }

        let scale    = maxLongEdge / longEdge
        let newSize  = CGSize(width:  (size.width  * scale).rounded(),
                              height: (size.height * scale).rounded())

        let format        = UIGraphicsImageRendererFormat()
        format.scale      = 1       // pixel-exact size — no Retina multiplier
        format.opaque     = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Async Avatar View
//
// Decodes photoData into a circle avatar on a background thread.
// Replaces every inline `UIImage(data: photoData)` pattern used for
// 32–80 px circles so the main thread is never blocked by image decode.

struct AsyncAvatarView: View {
    let photoData: Data?
    let size: CGFloat
    let fallbackInitial: String
    var accentColor: Color = .blue

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: size, height: size)
                    if thumbnail == nil && photoData != nil {
                        // Loading spinner while decoding
                        ProgressView()
                            .scaleEffect(size < 36 ? 0.6 : 0.8)
                            .tint(accentColor)
                    } else {
                        Text(fallbackInitial)
                            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                            .foregroundColor(accentColor)
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .task(id: photoData.map { $0.hashValue }) {
            await decode()
        }
    }

    private func decode() async {
        guard let data = photoData else {
            thumbnail = nil
            return
        }
        let px = size * 2   // 2× for retina — still tiny vs the source
        let decoded: UIImage? = await Task.detached(priority: .utility) {
            autoreleasepool {
                guard let full = UIImage(data: data) else { return nil }
                return RoastTargetPhotoHelper.downscale(full, maxLongEdge: px)
            }
        }.value
        thumbnail = decoded
    }
}

// MARK: - Async Thumbnail View
//
// Decodes imageData into a fixed-size thumbnail on a background thread.
// Used by NotebookTrashView grid (mirrors NotebookThumbnailCell behavior).

struct AsyncThumbnailView: View {
    let imageData: Data?
    let size: CGFloat
    var opacity: Double = 1.0

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
                    .overlay(
                        Group {
                            if imageData != nil {
                                ProgressView().tint(.secondary)
                            } else {
                                Image(systemName: "photo")
                                    .foregroundColor(.white)
                            }
                        }
                    )
            }
        }
        .frame(minWidth: size, minHeight: size)
        .clipped()
        .opacity(opacity)
        .task(id: imageData.map { $0.hashValue }) {
            await decode()
        }
    }

    private func decode() async {
        guard let data = imageData else { thumbnail = nil; return }
        let px = size * 2
        let decoded: UIImage? = await Task.detached(priority: .utility) {
            autoreleasepool {
                guard let full = UIImage(data: data) else { return nil }
                return RoastTargetPhotoHelper.downscale(full, maxLongEdge: px)
            }
        }.value
        thumbnail = decoded
    }
}
