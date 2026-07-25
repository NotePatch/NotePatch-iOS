import Foundation
import UniformTypeIdentifiers
import UIKit

enum UploadPreviewKind: Equatable {
    case image
    case quickLook
    case unsupported
}

struct LocalUploadFile: Equatable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let filename: String
    let mimeType: String?

    nonisolated init(id: UUID = UUID(), url: URL, filename: String, mimeType: String?) {
        self.id = id
        self.url = url
        self.filename = filename
        self.mimeType = mimeType
    }

    nonisolated var fileSize: Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    nonisolated var isImage: Bool {
        if mimeType?.hasPrefix("image/") == true {
            return true
        }
        return ["jpg", "jpeg", "png", "webp", "heic"].contains(url.pathExtension.lowercased())
    }

    nonisolated func previewKind(canQuickLookPreview: Bool) -> UploadPreviewKind {
        if isImage {
            return .image
        }
        return canQuickLookPreview ? .quickLook : .unsupported
    }
}

enum QueuedUploadState: Equatable {
    case pending
    case uploading
    case failed(String)
}

struct QueuedUploadItem: Identifiable, Equatable {
    let id: UUID
    let file: LocalUploadFile
    let documentKind: String
    let learningMetadata: LearningMetadata
    var isSelected: Bool
    var state: QueuedUploadState

    init(
        file: LocalUploadFile,
        documentKind: String,
        learningMetadata: LearningMetadata,
        isSelected: Bool = true,
        state: QueuedUploadState = .pending
    ) {
        id = file.id
        self.file = file
        self.documentKind = documentKind
        self.learningMetadata = learningMetadata
        self.isSelected = isSelected
        self.state = state
    }
}

struct DownloadedPreview: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let mimeType: String?

    var isImage: Bool {
        mimeType?.hasPrefix("image/") == true || ["jpg", "jpeg", "png", "webp", "heic"].contains(url.pathExtension.lowercased())
    }
}

nonisolated func prepareUploadFile(_ source: LocalUploadFile, cacheDirectory: URL) throws -> LocalUploadFile {
    guard source.isImage else {
        return source
    }
    let normalizedURL = try normalizeImageOrientation(source.url, cacheDirectory: cacheDirectory)
    guard normalizedURL != source.url else {
        return source
    }
    return LocalUploadFile(
        url: normalizedURL,
        filename: replacingFilenameExtension(source.filename, with: "jpg"),
        mimeType: "image/jpeg"
    )
}

nonisolated func normalizeImageOrientation(_ sourceURL: URL, cacheDirectory: URL) throws -> URL {
    guard let image = UIImage(contentsOfFile: sourceURL.path), image.imageOrientation != .up else {
        return sourceURL
    }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = image.scale
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    let rendered = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    guard let data = rendered.jpegData(compressionQuality: 0.95) else {
        throw LearningBackendError("Unable to read image; cannot correct photo orientation.")
    }
    let directory = cacheDirectory.appendingPathComponent("normalized", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let targetURL = directory.appendingPathComponent("notepatch_normalized_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
    try data.write(to: targetURL, options: .atomic)
    return targetURL
}

nonisolated func copyFileToUploadCache(
    sourceURL: URL,
    fallbackPrefix: String,
    cacheDirectory: URL,
    suggestedMimeType: String? = nil,
    suggestedFilename: String? = nil
) throws -> LocalUploadFile {
    let sourceName = suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
    let preferredName = sourceName?.isEmpty == false ? sourceName! : sourceURL.lastPathComponent
    let safeName = sanitizeFileName(preferredName.isEmpty ? "\(fallbackPrefix)-\(Int(Date().timeIntervalSince1970)).bin" : preferredName)
    let directory = cacheDirectory.appendingPathComponent("uploads", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let targetURL = directory.appendingPathComponent("\(UUID().uuidString)_\(safeName)")
    if FileManager.default.fileExists(atPath: targetURL.path) {
        try FileManager.default.removeItem(at: targetURL)
    }
    try FileManager.default.copyItem(at: sourceURL, to: targetURL)
    return LocalUploadFile(
        url: targetURL,
        filename: safeName,
        mimeType: suggestedMimeType ?? contentTypeForFilename(safeName)
    )
}

nonisolated func writeImageToUploadCache(_ image: UIImage, cacheDirectory: URL) throws -> LocalUploadFile {
    guard let data = image.jpegData(compressionQuality: 0.95) else {
        throw LearningBackendError("Unable to read image; cannot correct photo orientation.")
    }
    let directory = cacheDirectory.appendingPathComponent("camera", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let filename = "notepatch_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
    let targetURL = directory.appendingPathComponent(filename)
    try data.write(to: targetURL, options: .atomic)
    return LocalUploadFile(url: targetURL, filename: filename, mimeType: "image/jpeg")
}

nonisolated func writePhotoDataToUploadCache(_ data: Data, suggestedFilename: String, mimeType: String?, cacheDirectory: URL) throws -> LocalUploadFile {
    let safeName = sanitizeFileName(suggestedFilename)
    let directory = cacheDirectory.appendingPathComponent("uploads", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let targetURL = directory.appendingPathComponent("\(UUID().uuidString)_\(safeName)")
    try data.write(to: targetURL, options: .atomic)
    return LocalUploadFile(url: targetURL, filename: safeName, mimeType: mimeType ?? contentTypeForFilename(safeName))
}

nonisolated func sanitizeFileName(_ name: String) -> String {
    let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
    let sanitized = name.components(separatedBy: invalid).joined(separator: "_")
    return sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "upload.bin" : sanitized
}

nonisolated func replacingFilenameExtension(_ filename: String, with newExtension: String) -> String {
    let nsName = filename as NSString
    let base = nsName.deletingPathExtension
    return base.isEmpty ? "\(filename).\(newExtension)" : "\(base).\(newExtension)"
}

nonisolated func extensionForContentType(_ contentType: String?) -> String? {
    guard let contentType,
          let type = UTType(mimeType: contentType),
          let ext = type.preferredFilenameExtension,
          !ext.isEmpty else {
        return nil
    }
    return ext
}

nonisolated func contentTypeForFilename(_ filename: String) -> String? {
    switch (filename as NSString).pathExtension.lowercased() {
    case "jpg", "jpeg":
        return "image/jpeg"
    case "png":
        return "image/png"
    case "webp":
        return "image/webp"
    case "heic":
        return "image/heic"
    case "pdf":
        return "application/pdf"
    case "txt":
        return "text/plain"
    case "docx":
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    case "pptx":
        return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    default:
        return nil
    }
}

func friendlyError(_ error: Error) -> String {
    if let backendError = error as? LearningBackendError {
        return backendError.message
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .badURL, .unsupportedURL:
            return "The server address format is incorrect. Please check the API or TUS URL."
        case .cannotFindHost, .dnsLookupFailed:
            return "Could not resolve the server address. Please check the server address or network."
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return "Could not connect to the server. Please make sure the device and server are on the same local network."
        case .timedOut:
            return "Connection timed out. If the server is reachable from a browser, please check whether the system allows NotePatch to access the network."
        default:
            break
        }
    }
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
        return AppLocalization.shared.string("Network or file I/O error: %@", nsError.localizedDescription)
    }
    return error.localizedDescription
}

func activeFilterSummary(status: String, documentKind: String, fileType: String) -> String {
    let filters = [
        status.isEmpty ? nil : AppLocalization.shared.string("Status %@", statusLabel(status)),
        documentKind.isEmpty ? nil : AppLocalization.shared.string("Type %@", documentKindLabel(documentKind)),
        fileType.isEmpty ? nil : AppLocalization.shared.string("File %@", fileTypeLabel(fileType))
    ].compactMap { $0 }
    return filters.isEmpty ? localized("filter.all_documents") : filters.joined(separator: " · ")
}

func filterChoiceLabel(_ value: String) -> String {
    if value.isEmpty {
        return localized("filter.all")
    }
    let status = statusLabel(value)
    if status != value {
        return status
    }
    let kind = documentKindLabel(value)
    if kind != value {
        return kind
    }
    return fileTypeLabel(value)
}

func statusLabel(_ value: String) -> String {
    switch value {
    case "created": return localized("status.created")
    case "uploading": return localized("status.uploading")
    case "uploaded": return localized("status.uploaded")
    case "processing": return localized("status.processing")
    case "ready": return localized("status.ready")
    case "failed": return localized("status.failed")
    case "deleted": return localized("status.deleted")
    case "queued": return localized("status.queued")
    case "running": return localized("status.running")
    case "succeeded": return localized("status.succeeded")
    case "cancelled": return localized("status.cancelled")
    case "completed": return localized("status.completed")
    case "draft": return localized("status.draft")
    default: return value
    }
}

func canProcessDocument(status: String) -> Bool {
    ["uploaded", "ready", "failed"].contains(status)
}

func documentKindLabel(_ value: String) -> String {
    switch value {
    case "homework": return localized("document_kind.homework")
    case "corrected_homework": return localized("document_kind.corrected_homework")
    case "courseware": return localized("document_kind.courseware")
    case "note": return localized("document_kind.note")
    case "exam": return localized("document_kind.exam")
    case "answer_key": return localized("document_kind.answer_key")
    case "rubric": return localized("document_kind.rubric")
    case "other": return localized("common.other")
    default: return value
    }
}

func fileTypeLabel(_ value: String) -> String {
    switch value {
    case "image": return localized("file_type.image")
    case "pdf": return "PDF"
    case "docx": return "DOCX"
    case "pptx": return "PPTX"
    case "audio": return localized("file_type.audio")
    case "video": return localized("file_type.video")
    case "other": return localized("common.other")
    default: return value
    }
}

func artifactTypeLabel(_ value: String) -> String {
    switch value {
    case "original": return localized("artifact.original")
    case "deskewed_image": return localized("artifact.deskewed_image")
    case "ocr_json": return localized("artifact.ocr_json")
    case "ocr_markdown": return localized("artifact.ocr_markdown")
    case "ocr_text": return localized("artifact.ocr_text")
    case "questions_json": return localized("artifact.questions_json")
    case "grading_report": return localized("artifact.grading_report")
    case "summary": return localized("artifact.summary")
    case "flashcards": return localized("artifact.flashcards")
    case "other": return localized("common.other")
    default: return value
    }
}

func compactDateTime(_ value: String) -> String {
    let compact = value.replacingOccurrences(of: "T", with: " ")
        .replacingOccurrences(of: "Z", with: "")
        .components(separatedBy: ".")
        .first ?? value
    return String(compact.prefix(16))
}

func formatBytes(_ sizeBytes: Int64?) -> String {
    guard let sizeBytes else {
        return "\u{2014}"
    }
    if sizeBytes < 1024 {
        return "\(sizeBytes) B"
    }
    let kb = Double(sizeBytes) / 1024.0
    if kb < 1024 {
        return String(format: "%.1f KB", kb)
    }
    return String(format: "%.1f MB", kb / 1024.0)
}
