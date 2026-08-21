import Combine
import Foundation
import SwiftUI
import UIKit

nonisolated func documentSupportsImageThumbnail(_ document: LearningDocumentItem) -> Bool {
    if document.fileType.lowercased() == "image" {
        return true
    }
    if document.mimeType?.lowercased().hasPrefix("image/") == true {
        return true
    }
    switch (document.originalFilename as NSString).pathExtension.lowercased() {
    case "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp":
        return true
    default:
        return false
    }
}

nonisolated func documentThumbnailCacheKey(
    baseURL: String,
    userId: String,
    workspaceId: String,
    document: LearningDocumentItem
) -> String {
    [baseURL, userId, workspaceId, document.id, document.updatedAt, document.originalFilename]
        .joined(separator: "|")
}

nonisolated func documentThumbnailCacheURL(
    cacheDirectory: URL,
    baseURL: String,
    userId: String,
    workspaceId: String,
    document: LearningDocumentItem
) -> URL {
    let server = Data(baseURL.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "=", with: "")
    let version = sanitizeFileName(document.updatedAt.isEmpty ? "current" : document.updatedAt)
    return cacheDirectory
        .appendingPathComponent("document-thumbnails", isDirectory: true)
        .appendingPathComponent(server, isDirectory: true)
        .appendingPathComponent(sanitizeFileName(userId), isDirectory: true)
        .appendingPathComponent(sanitizeFileName(workspaceId), isDirectory: true)
        .appendingPathComponent(sanitizeFileName(document.id), isDirectory: true)
        .appendingPathComponent("\(version).png")
}

actor DocumentThumbnailLimiter {
    static let shared = DocumentThumbnailLimiter(limit: 3)

    private let limit: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if activeCount < limit {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            activeCount = max(0, activeCount - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
final class DocumentThumbnailPipeline {
    static let shared = DocumentThumbnailPipeline()

    private struct Flight {
        let task: Task<UIImage?, Never>
        var consumers: Set<UUID>
    }

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Flight] = [:]

    private init() {
        cache.countLimit = 120
        cache.totalCostLimit = 20 * 1024 * 1024
    }

    func image(
        forKey key: String,
        loader: @escaping () async -> UIImage?
    ) async -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        let consumer = UUID()
        let task: Task<UIImage?, Never>
        if var existing = inFlight[key] {
            existing.consumers.insert(consumer)
            inFlight[key] = existing
            task = existing.task
        } else {
            task = Task<UIImage?, Never> {
                await DocumentThumbnailLimiter.shared.acquire()
                if Task.isCancelled {
                    await DocumentThumbnailLimiter.shared.release()
                    return nil
                }
                let image = await loader()
                await DocumentThumbnailLimiter.shared.release()
                return image
            }
            inFlight[key] = Flight(task: task, consumers: [consumer])
        }

        return await withTaskCancellationHandler {
            let result = await task.value
            guard !Task.isCancelled else {
                finishConsumer(consumer, forKey: key, result: nil)
                return nil
            }
            finishConsumer(consumer, forKey: key, result: result)
            return result
        } onCancel: {
            Task { @MainActor in
                DocumentThumbnailPipeline.shared.cancelConsumer(consumer, forKey: key)
            }
        }
    }

    func cachedImage(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func removeAll() {
        inFlight.values.forEach { $0.task.cancel() }
        inFlight.removeAll()
        cache.removeAllObjects()
    }

    private func finishConsumer(_ consumer: UUID, forKey key: String, result: UIImage?) {
        guard var flight = inFlight[key], flight.consumers.remove(consumer) != nil else { return }
        if let result {
            let cost = Int(result.size.width * result.size.height * result.scale * result.scale * 4)
            cache.setObject(result, forKey: key as NSString, cost: cost)
        }
        if flight.consumers.isEmpty {
            inFlight[key] = nil
        } else {
            inFlight[key] = flight
        }
    }

    private func cancelConsumer(_ consumer: UUID, forKey key: String) {
        guard var flight = inFlight[key], flight.consumers.remove(consumer) != nil else { return }
        if flight.consumers.isEmpty {
            flight.task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = flight
        }
    }
}

@MainActor
final class DocumentThumbnailLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private var representedKey: String?
    private var task: Task<Void, Never>?

    func load(key: String, operation: @escaping () async -> UIImage?) {
        guard representedKey != key else { return }
        task?.cancel()
        representedKey = key
        image = DocumentThumbnailPipeline.shared.cachedImage(forKey: key)
        guard image == nil else { return }

        task = Task { [weak self] in
            let loaded = await DocumentThumbnailPipeline.shared.image(forKey: key, loader: operation)
            guard !Task.isCancelled, self?.representedKey == key else { return }
            self?.image = loaded
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        representedKey = nil
    }
}

struct DocumentThumbnailView: View {
    let document: LearningDocumentItem
    let cacheKey: String
    let size: CGSize
    let load: () async -> UIImage?

    @StateObject private var loader = DocumentThumbnailLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NPColors.brandLight)
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: fallbackIcon)
                    .font(.system(size: min(size.width, size.height) * 0.42, weight: .medium))
                    .foregroundStyle(NPColors.brandDark)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .onAppear {
            guard documentSupportsImageThumbnail(document) else { return }
            loader.load(key: cacheKey, operation: load)
        }
        .onDisappear {
            loader.cancel()
        }
        .accessibilityHidden(true)
    }

    private var fallbackIcon: String {
        switch document.fileType.lowercased() {
        case "image": return "photo"
        case "pdf": return "doc.richtext"
        case "docx": return "doc.text"
        case "pptx": return "rectangle.stack"
        case "audio": return "waveform"
        case "video": return "play.rectangle"
        default: return "doc"
        }
    }
}
