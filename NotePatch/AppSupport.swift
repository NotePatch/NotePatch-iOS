import Foundation
import UniformTypeIdentifiers
import UIKit

enum UploadPreviewKind: Equatable {
    case image
    case quickLook
    case unsupported
}

enum DownloadPreviewKind: Equatable {
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
        inferredUploadFileType(filename: filename, mimeType: mimeType) == "image"
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
    case uploaded
    case failed(AppDisplayText)
}

struct QueuedUploadRemoteState: Equatable {
    var uploadSessionId: String
    var tusEndpoint: String
    var tusMetadataHeader: String
    var tusUploadURL: String?
    var tusUploadId: String?
    var workflowRunId: String?
    var documentId: String?
}

struct QueuedUploadItem: Identifiable, Equatable {
    let id: UUID
    let file: LocalUploadFile
    var documentKind: String
    var learningMetadata: LearningMetadata
    var saveToDocuments: Bool
    var remark: String?
    var isSelected: Bool
    var state: QueuedUploadState
    var remoteState: QueuedUploadRemoteState?

    init(
        file: LocalUploadFile,
        documentKind: String,
        learningMetadata: LearningMetadata,
        saveToDocuments: Bool = true,
        remark: String? = nil,
        isSelected: Bool = true,
        state: QueuedUploadState = .pending,
        remoteState: QueuedUploadRemoteState? = nil
    ) {
        id = file.id
        self.file = file
        self.documentKind = documentKind
        self.learningMetadata = learningMetadata
        self.saveToDocuments = saveToDocuments
        self.remark = remark
        self.isSelected = isSelected
        self.state = state
        self.remoteState = remoteState
    }
}

struct DownloadedPreview: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let mimeType: String?
    let filename: String
    let fileSize: Int64?

    init(url: URL, mimeType: String?, filename: String? = nil, fileSize: Int64? = nil) {
        self.url = url
        self.mimeType = mimeType
        let trimmedFilename = filename?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.filename = trimmedFilename.isEmpty ? url.lastPathComponent : trimmedFilename
        self.fileSize = fileSize
    }

    var isImage: Bool {
        mimeType?.hasPrefix("image/") == true || ["jpg", "jpeg", "png", "webp", "heic"].contains(url.pathExtension.lowercased())
    }

    func previewKind(canQuickLookPreview: Bool) -> DownloadPreviewKind {
        if isImage {
            return .image
        }
        return canQuickLookPreview ? .quickLook : .unsupported
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
        throw LearningBackendError(localizedKey: "error.image.orientation")
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
        throw LearningBackendError(localizedKey: "error.image.orientation")
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
    let ext = (filename as NSString).pathExtension.lowercased()
    if let type = UTType(filenameExtension: ext), let mimeType = type.preferredMIMEType {
        return mimeType
    }
    switch ext {
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
    case "doc": return "application/msword"
    case "odt": return "application/vnd.oasis.opendocument.text"
    case "rtf": return "application/rtf"
    case "ppt": return "application/vnd.ms-powerpoint"
    case "odp": return "application/vnd.oasis.opendocument.presentation"
    case "xls": return "application/vnd.ms-excel"
    case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case "ods": return "application/vnd.oasis.opendocument.spreadsheet"
    case "md": return "text/markdown"
    case "csv": return "text/csv"
    case "tsv": return "text/tab-separated-values"
    case "json": return "application/json"
    case "jsonl": return "application/x-ndjson"
    case "yaml", "yml": return "application/yaml"
    case "xml": return "application/xml"
    case "html", "htm": return "text/html"
    case "epub": return "application/epub+zip"
    case "eml": return "message/rfc822"
    case "msg": return "application/vnd.ms-outlook"
    case "ipynb": return "application/x-ipynb+json"
    case "7z": return "application/x-7z-compressed"
    case "rar": return "application/vnd.rar"
    case "tar": return "application/x-tar"
    case "tgz": return "application/gzip"
    case "bz2": return "application/x-bzip2"
    case "xz": return "application/x-xz"
    case "zst": return "application/zstd"
    default:
        return nil
    }
}

let extendedUploadExtensions: Set<String> = [
    "jpg", "jpeg", "png", "webp", "tif", "tiff", "gif", "bmp", "heic",
    "pdf", "doc", "docx", "odt", "rtf", "ppt", "pptx", "odp",
    "xls", "xlsx", "ods", "txt", "md", "csv", "tsv", "json", "jsonl",
    "yaml", "yml", "xml", "html", "htm", "epub", "eml", "msg", "ipynb",
    "mp3", "wav", "m4a", "aac", "ogg", "flac", "mp4", "mov", "mkv",
    "avi", "webm", "zip", "7z", "rar", "tar", "tgz", "gz", "bz2", "xz", "zst"
]

let learningDocumentKinds: Set<String> = [
    "homework", "corrected_homework", "courseware", "note", "exam", "answer_key", "rubric"
]

let learningPipelineFileTypes: Set<String> = ["image", "pdf", "docx", "pptx"]

nonisolated func inferredUploadFileType(filename: String, mimeType: String?) -> String {
    let ext = (filename as NSString).pathExtension.lowercased()
    let normalizedMIME = mimeType?.lowercased() ?? ""
    if normalizedMIME.hasPrefix("image/")
        || ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "heic"].contains(ext) {
        return "image"
    }
    if normalizedMIME == "application/pdf" || ext == "pdf" { return "pdf" }
    if ext == "docx" || normalizedMIME.hasSuffix("wordprocessingml.document") { return "docx" }
    if ext == "pptx" || normalizedMIME.hasSuffix("presentationml.presentation") { return "pptx" }
    if normalizedMIME.hasPrefix("audio/") || ["mp3", "wav", "m4a", "aac", "ogg"].contains(ext) {
        return "audio"
    }
    if normalizedMIME.hasPrefix("video/") || ["mp4", "mov", "mkv", "avi", "webm"].contains(ext) {
        return "video"
    }
    return "other"
}

func isSupportedLearningUpload(filename: String, mimeType: String?) -> Bool {
    learningPipelineFileTypes.contains(inferredUploadFileType(filename: filename, mimeType: mimeType))
}

@MainActor
func friendlyDisplayText(_ error: Error) -> AppDisplayText {
    if let backendError = error as? LearningBackendError {
        if let key = backendError.localizationKey {
            return .localized(key, backendError.localizationArguments)
        }
        return .raw(backendError.message)
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .badURL, .unsupportedURL:
            return .localized("error.network.invalid_address")
        case .cannotFindHost, .dnsLookupFailed:
            return .localized("error.network.dns")
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return .localized("error.network.unreachable")
        case .timedOut:
            return .localized("error.network.timeout")
        default:
            break
        }
    }
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
        return .localized("error.network.io", [nsError.localizedDescription])
    }
    return .raw(error.localizedDescription)
}

@MainActor
func friendlyError(_ error: Error) -> String {
    friendlyDisplayText(error).resolved()
}

func activeFilterSummary(status: String, documentKind: String, fileType: String) -> String {
    let filters = [
        status.isEmpty ? nil : AppLocalization.shared.string("filter.summary.status", statusLabel(status)),
        documentKind.isEmpty ? nil : AppLocalization.shared.string("filter.summary.type", documentKindLabel(documentKind)),
        fileType.isEmpty ? nil : AppLocalization.shared.string("filter.summary.file", fileTypeLabel(fileType))
    ].compactMap { $0 }
    return filters.isEmpty ? localized("filter.all_documents") : filters.joined(separator: " · ")
}

func filterChoiceLabel(_ value: String) -> String {
    if value.isEmpty {
        return localized("filter.all")
    }
    if [
        "created", "uploading", "scanning", "uploaded", "processing", "ready", "failed",
        "deleted", "queued", "running", "succeeded", "cancelled", "completed", "draft",
        "pending", "rebuilding", "infected"
    ].contains(value) {
        return statusLabel(value)
    }
    if [
        "homework", "corrected_homework", "courseware", "note", "exam", "answer_key", "rubric", "other"
    ].contains(value) {
        return documentKindLabel(value)
    }
    return fileTypeLabel(value)
}

func statusLabel(_ value: String) -> String {
    switch value {
    case "created": return localized("status.created")
    case "uploading": return localized("status.uploading")
    case "scanning": return localized("status.preparing")
    case "pending": return localized("status.pending")
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
    case "rebuilding": return localized("status.rebuilding")
    case "infected": return localized("status.unavailable")
    default: return localized("status.unknown")
    }
}

func mergeStatusLabel(_ value: String) -> String {
    switch value {
    case "merging": return localized("merge.status.merging")
    case "rebuilding": return localized("merge.status.rebuilding")
    case "completed": return localized("merge.status.completed")
    case "failed": return localized("merge.status.failed")
    default: return localized("merge.status.unknown")
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
    case "chat_attachment": return localized("document_kind.chat_attachment")
    default: return localized("document_kind.unknown")
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
    default: return localized("file_type.unknown")
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
    case "converted_pdf": return localized("artifact.converted_pdf")
    case "other": return localized("common.other")
    default: return localized("artifact.unknown")
    }
}

private let supportedFlashcardHintKeys: Set<String> = [
    "flashcards.hints.recently_improving",
    "flashcards.hints.just_missed",
    "flashcards.hints.frequent_recent_errors",
    "flashcards.hints.recently_correct",
    "flashcards.hints.from_notes",
    "flashcards.hints.historical_review",
    "flashcards.hints.general_review",
    "flashcards.badges.correct_streak",
    "flashcards.badges.recent_errors",
    "flashcards.badges.historical_errors",
    "flashcards.badges.latest_outcome"
]

func flashcardHintText(_ item: FlashcardHintItem) -> String {
    let key = supportedFlashcardHintKeys.contains(item.messageKey)
        ? item.messageKey
        : "flashcards.hints.general_review"
    var value = localized(key)
    for (name, parameter) in item.params {
        let replacement: String
        if name == "outcome" {
            switch parameter.displayString {
            case "correct": replacement = localized("flashcards.outcome.correct")
            case "partial": replacement = localized("flashcards.outcome.partial")
            case "incorrect": replacement = localized("flashcards.outcome.incorrect")
            default: replacement = parameter.displayString
            }
        } else {
            replacement = parameter.displayString
        }
        value = value.replacingOccurrences(of: "{\(name)}", with: replacement)
    }
    return value
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

func keyboardAvoidanceOffset(contentFrame: CGRect, keyboardFrame: CGRect) -> CGFloat {
    guard !contentFrame.isNull,
          !keyboardFrame.isNull,
          keyboardFrame.width > 0,
          keyboardFrame.height > 0,
          keyboardFrame.maxX > contentFrame.minX,
          keyboardFrame.minX < contentFrame.maxX,
          keyboardFrame.maxY > contentFrame.minY,
          keyboardFrame.minY < contentFrame.maxY else {
        return 0
    }
    return max(0, contentFrame.maxY - keyboardFrame.minY)
}

func workbenchBottomObstruction(
    containerHeight: CGFloat,
    bottomBarFrame: CGRect,
    isVisible: Bool
) -> CGFloat {
    guard isVisible,
          containerHeight > 0,
          !bottomBarFrame.isNull,
          !bottomBarFrame.isInfinite,
          bottomBarFrame.height > 0 else {
        return 0
    }
    return max(0, containerHeight - bottomBarFrame.minY)
}

func workbenchBottomBarAdditionalPadding(safeAreaBottom: CGFloat) -> CGFloat {
    safeAreaBottom > 0.5 ? 0 : 8
}

func resolvedTopSafeAreaInset(
    reportedSafeAreaTop: CGFloat,
    windowSafeAreaTop: CGFloat,
    statusBarHeight: CGFloat
) -> CGFloat {
    max(0, max(reportedSafeAreaTop, max(windowSafeAreaTop, statusBarHeight)))
}

@MainActor
func currentAppWindowSafeAreaInsets() -> UIEdgeInsets {
    let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
    return windows.first(where: \.isKeyWindow)?.safeAreaInsets
        ?? windows.first?.safeAreaInsets
        ?? .zero
}

@MainActor
func currentAppStatusBarHeight() -> CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first(where: { $0.activationState == .foregroundActive })?
        .statusBarManager?
        .statusBarFrame.height
        ?? 0
}
