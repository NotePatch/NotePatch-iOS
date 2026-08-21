import Foundation
import UIKit

struct FileImportOutcome: Sendable {
    let file: LocalUploadFile?
    let errorDisplayText: AppDisplayText?
}

final class FileImportService {
    static let shared = FileImportService()

    private init() {}

    func importFiles(
        _ sourceURLs: [URL],
        fallbackPrefix: String,
        cacheDirectory: URL
    ) async -> [FileImportOutcome] {
        let trace = NPPerformanceTrace.begin("FileImport")
        let imported = await Task.detached(priority: .userInitiated) {
            sourceURLs.map { sourceURL in
                let didAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
                }
                do {
                    let file = try copyFileToUploadCache(
                        sourceURL: sourceURL,
                        fallbackPrefix: fallbackPrefix,
                        cacheDirectory: cacheDirectory,
                        suggestedMimeType: contentTypeForFilename(sourceURL.lastPathComponent)
                    )
                    return Result<LocalUploadFile, Error>.success(file)
                } catch {
                    return Result<LocalUploadFile, Error>.failure(error)
                }
            }
        }.value
        NPPerformanceTrace.end("FileImport", id: trace)
        return imported.map(Self.outcome)
    }

    func writePhotos(
        _ selections: [(data: Data, suggestedFilename: String, mimeType: String?)],
        cacheDirectory: URL
    ) async -> [FileImportOutcome] {
        let trace = NPPerformanceTrace.begin("PhotoImport")
        let imported = await Task.detached(priority: .userInitiated) {
            selections.map { selection in
                do {
                    let file = try writePhotoDataToUploadCache(
                        selection.data,
                        suggestedFilename: selection.suggestedFilename,
                        mimeType: selection.mimeType,
                        cacheDirectory: cacheDirectory
                    )
                    return Result<LocalUploadFile, Error>.success(file)
                } catch {
                    return Result<LocalUploadFile, Error>.failure(error)
                }
            }
        }.value
        NPPerformanceTrace.end("PhotoImport", id: trace)
        return imported.map(Self.outcome)
    }

    func writeCameraImage(_ image: UIImage, cacheDirectory: URL) async throws -> LocalUploadFile {
        try await Task.detached(priority: .userInitiated) {
            try writeImageToUploadCache(image, cacheDirectory: cacheDirectory)
        }.value
    }

    func prepareForUpload(_ file: LocalUploadFile, cacheDirectory: URL) async throws -> LocalUploadFile {
        try await Task.detached(priority: .userInitiated) {
            try prepareUploadFile(file, cacheDirectory: cacheDirectory)
        }.value
    }

    func readUTF8File(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let value = String(data: try Data(contentsOf: url), encoding: .utf8) else {
                throw LearningBackendError(localizedKey: "error.note.invalid_encoding")
            }
            return value
        }.value
    }

    private static func outcome(_ result: Result<LocalUploadFile, Error>) -> FileImportOutcome {
        switch result {
        case .success(let file):
            return FileImportOutcome(file: file, errorDisplayText: nil)
        case .failure(let error):
            return FileImportOutcome(file: nil, errorDisplayText: friendlyDisplayText(error))
        }
    }
}
