import Combine
import ImageIO
import QuickLook
import QuickLookThumbnailing
import SwiftUI
import UIKit

enum UploadThumbnailKind: Equatable {
    case image
    case quickLook
    case unsupported
}

func uploadThumbnailKind(for file: LocalUploadFile, canQuickLookPreview: Bool) -> UploadThumbnailKind {
    if file.isImage {
        return .image
    }
    return canQuickLookPreview ? .quickLook : .unsupported
}

func uploadThumbnailCacheKey(for file: LocalUploadFile) -> String {
    let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path)
    let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
    let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(file.url.standardizedFileURL.path)|\(size)|\(modified)"
}

func downsampleUploadImage(at url: URL, maxPixelSize: Int) -> UIImage? {
    guard maxPixelSize > 0,
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
          ) else {
        return nil
    }
    return UIImage(cgImage: image)
}

@MainActor
final class UploadThumbnailCache {
    static let shared = UploadThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func remove(file: LocalUploadFile) {
        cache.removeObject(forKey: uploadThumbnailCacheKey(for: file) as NSString)
    }
}

@MainActor
final class UploadThumbnailLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var kind: UploadThumbnailKind = .unsupported

    private var representedKey: String?
    private var generation = UUID()

    func load(file: LocalUploadFile, size: CGSize, scale: CGFloat) {
        let key = uploadThumbnailCacheKey(for: file)
        representedKey = key
        generation = UUID()
        let currentGeneration = generation
        kind = uploadThumbnailKind(
            for: file,
            canQuickLookPreview: QLPreviewController.canPreview(file.url as NSURL)
        )

        if let cached = UploadThumbnailCache.shared.image(forKey: key) {
            image = cached
            return
        }

        image = nil
        switch kind {
        case .image:
            let maxPixelSize = max(1, Int(max(size.width, size.height) * max(scale, 1)))
            DispatchQueue.global(qos: .userInitiated).async {
                let thumbnail = downsampleUploadImage(at: file.url, maxPixelSize: maxPixelSize)
                DispatchQueue.main.async { [weak self] in
                    self?.accept(thumbnail, key: key, generation: currentGeneration)
                }
            }
        case .quickLook:
            let request = QLThumbnailGenerator.Request(
                fileAt: file.url,
                size: size,
                scale: scale,
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                DispatchQueue.main.async {
                    self?.accept(representation?.uiImage, key: key, generation: currentGeneration)
                }
            }
        case .unsupported:
            break
        }
    }

    func cancel() {
        representedKey = nil
        generation = UUID()
    }

    private func accept(_ thumbnail: UIImage?, key: String, generation: UUID) {
        guard representedKey == key, self.generation == generation, let thumbnail else {
            return
        }
        UploadThumbnailCache.shared.insert(thumbnail, forKey: key)
        image = thumbnail
    }
}

struct UploadThumbnailView: View {
    let file: LocalUploadFile
    let onPreview: () -> Void

    @StateObject private var loader = UploadThumbnailLoader()
    @Environment(\.displayScale) private var displayScale

    private let size = CGSize(width: 56, height: 64)

    var body: some View {
        Button(action: onPreview) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))

                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: file.isImage ? .fill : .fit)
                        .padding(file.isImage ? 0 : 3)
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("预览 \(file.filename)")
        .accessibilityIdentifier("uploadQueueThumbnail")
        .onAppear {
            loader.load(file: file, size: size, scale: displayScale)
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var fallbackIcon: String {
        if file.isImage { return "photo" }
        switch file.url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "mp4", "mov", "m4v": return "video"
        default: return "doc"
        }
    }
}
