import Foundation
import UniformTypeIdentifiers
import UIKit

enum UploadPreviewKind: Equatable {
    case image
    case quickLook
    case unsupported
}

struct LocalUploadFile: Equatable, Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
    let mimeType: String?

    var fileSize: Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    var isImage: Bool {
        if mimeType?.hasPrefix("image/") == true {
            return true
        }
        return ["jpg", "jpeg", "png", "webp", "heic"].contains(url.pathExtension.lowercased())
    }

    func previewKind(canQuickLookPreview: Bool) -> UploadPreviewKind {
        if isImage {
            return .image
        }
        return canQuickLookPreview ? .quickLook : .unsupported
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

func prepareUploadFile(_ source: LocalUploadFile, cacheDirectory: URL) throws -> LocalUploadFile {
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

func normalizeImageOrientation(_ sourceURL: URL, cacheDirectory: URL) throws -> URL {
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
        throw LearningBackendError("无法读取图片，不能校正照片方向。")
    }
    let directory = cacheDirectory.appendingPathComponent("normalized", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let targetURL = directory.appendingPathComponent("notepatch_normalized_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
    try data.write(to: targetURL, options: .atomic)
    return targetURL
}

func copyFileToUploadCache(
    sourceURL: URL,
    fallbackPrefix: String,
    cacheDirectory: URL,
    suggestedMimeType: String? = nil
) throws -> LocalUploadFile {
    let safeName = sanitizeFileName(sourceURL.lastPathComponent.isEmpty ? "\(fallbackPrefix)-\(Int(Date().timeIntervalSince1970)).bin" : sourceURL.lastPathComponent)
    let directory = cacheDirectory.appendingPathComponent("uploads", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let targetURL = directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))_\(safeName)")
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

func writeImageToUploadCache(_ image: UIImage, cacheDirectory: URL) throws -> LocalUploadFile {
    guard let data = image.jpegData(compressionQuality: 0.95) else {
        throw LearningBackendError("无法读取图片，不能校正照片方向。")
    }
    let directory = cacheDirectory.appendingPathComponent("camera", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let filename = "notepatch_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
    let targetURL = directory.appendingPathComponent(filename)
    try data.write(to: targetURL, options: .atomic)
    return LocalUploadFile(url: targetURL, filename: filename, mimeType: "image/jpeg")
}

func writePhotoDataToUploadCache(_ data: Data, suggestedFilename: String, mimeType: String?, cacheDirectory: URL) throws -> LocalUploadFile {
    let safeName = sanitizeFileName(suggestedFilename)
    let directory = cacheDirectory.appendingPathComponent("uploads", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let targetURL = directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))_\(safeName)")
    try data.write(to: targetURL, options: .atomic)
    return LocalUploadFile(url: targetURL, filename: safeName, mimeType: mimeType ?? contentTypeForFilename(safeName))
}

func sanitizeFileName(_ name: String) -> String {
    let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
    let sanitized = name.components(separatedBy: invalid).joined(separator: "_")
    return sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "upload.bin" : sanitized
}

func replacingFilenameExtension(_ filename: String, with newExtension: String) -> String {
    let nsName = filename as NSString
    let base = nsName.deletingPathExtension
    return base.isEmpty ? "\(filename).\(newExtension)" : "\(base).\(newExtension)"
}

func extensionForContentType(_ contentType: String?) -> String? {
    guard let contentType,
          let type = UTType(mimeType: contentType),
          let ext = type.preferredFilenameExtension,
          !ext.isEmpty else {
        return nil
    }
    return ext
}

func contentTypeForFilename(_ filename: String) -> String? {
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
            return "服务器地址格式不正确，请检查 API 或 tus 地址。"
        case .cannotFindHost, .dnsLookupFailed:
            return "无法解析服务器地址，请检查服务器地址或网络。"
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return "无法连接到服务器，请确认设备和服务器在同一内网。"
        case .timedOut:
            return "连接服务器超时。若设备浏览器能访问服务器，请检查系统是否允许 NotePatch 使用网络。"
        default:
            break
        }
    }
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
        return "网络或文件读写失败：\(nsError.localizedDescription)"
    }
    return error.localizedDescription
}

func activeFilterSummary(status: String, documentKind: String, fileType: String) -> String {
    let filters = [
        status.isEmpty ? nil : "状态 \(statusLabel(status))",
        documentKind.isEmpty ? nil : "类型 \(documentKindLabel(documentKind))",
        fileType.isEmpty ? nil : "文件 \(fileTypeLabel(fileType))"
    ].compactMap { $0 }
    return filters.isEmpty ? "全部文档" : filters.joined(separator: " · ")
}

func filterChoiceLabel(_ value: String) -> String {
    if value.isEmpty {
        return "全部"
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
    case "created": return "已创建"
    case "uploading": return "上传中"
    case "uploaded": return "已上传"
    case "processing": return "处理中"
    case "ready": return "就绪"
    case "failed": return "失败"
    case "deleted": return "已删除"
    case "queued": return "排队"
    case "running": return "运行中"
    case "succeeded": return "成功"
    case "completed": return "完成"
    default: return value
    }
}

func documentKindLabel(_ value: String) -> String {
    switch value {
    case "homework": return "作业"
    case "corrected_homework": return "批改作业"
    case "courseware": return "课件"
    case "note": return "笔记"
    case "exam": return "试卷"
    case "other": return "其他"
    default: return value
    }
}

func fileTypeLabel(_ value: String) -> String {
    switch value {
    case "image": return "图片"
    case "pdf": return "PDF"
    case "docx": return "DOCX"
    case "pptx": return "PPTX"
    case "audio": return "音频"
    case "video": return "视频"
    case "other": return "其他"
    default: return value
    }
}

func artifactTypeLabel(_ value: String) -> String {
    switch value {
    case "original": return "原始文件"
    case "deskewed_image": return "矫正图片"
    case "ocr_json": return "OCR JSON"
    case "ocr_markdown": return "OCR Markdown"
    case "ocr_text": return "OCR 文本"
    case "questions_json": return "题目 JSON"
    case "grading_report": return "批改报告"
    case "summary": return "摘要"
    case "flashcards": return "闪卡"
    case "other": return "其他"
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
        return "unknown size"
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
