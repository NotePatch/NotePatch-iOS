import Foundation

struct TusUploadResult: Equatable {
    let uploadURL: String
    let uploadId: String?
}

final class TusUploader {
    private static let resumableVersion = "1.0.0"
    private static let chunkSize = 1024 * 1024
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func upload(
        fileURL: URL,
        endpoint: String,
        metadataHeader: String,
        onProgress: @escaping (Int64, Int64) async -> Void
    ) async throws -> TusUploadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LearningBackendError(localizedKey: "error.upload.file_missing")
        }
        let sizeBytes = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
        let uploadURL = try await createUpload(endpoint: endpoint, sizeBytes: sizeBytes, metadataHeader: metadataHeader)
        try await uploadChunks(fileURL: fileURL, uploadURL: uploadURL, totalBytes: sizeBytes, onProgress: onProgress)
        return TusUploadResult(uploadURL: uploadURL, uploadId: Self.extractTusUploadId(uploadURL))
    }

    private func createUpload(endpoint: String, sizeBytes: Int64, metadataHeader: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw LearningBackendError(localizedKey: "error.server.invalid_address")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(Self.resumableVersion, forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(sizeBytes), forHTTPHeaderField: "Upload-Length")
        if !metadataHeader.isEmpty {
            request.setValue(metadataHeader, forHTTPHeaderField: "Upload-Metadata")
        }

        let (data, response) = try await session.upload(for: request, from: Data())
        try validate(response: response, data: data)
        guard let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location") else {
            throw LearningBackendError(localizedKey: "error.tus.location_missing")
        }
        return try Self.resolveUploadURL(endpoint: endpoint, location: location)
    }

    private func uploadChunks(
        fileURL: URL,
        uploadURL: String,
        totalBytes: Int64,
        onProgress: @escaping (Int64, Int64) async -> Void
    ) async throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var offset: Int64 = 0
        while offset < totalBytes {
            try handle.seek(toOffset: UInt64(offset))
            let remaining = totalBytes - offset
            let size = min(Self.chunkSize, Int(remaining))
            guard let chunk = try handle.read(upToCount: size), !chunk.isEmpty else {
                break
            }
            offset = try await patchWithRetry(uploadURL: uploadURL, offset: offset, chunk: chunk)
            await onProgress(offset, totalBytes)
        }
    }

    private func patchWithRetry(uploadURL: String, offset: Int64, chunk: Data) async throws -> Int64 {
        let retryDelays: [UInt64] = [0, 1_000_000_000, 3_000_000_000, 5_000_000_000]
        var lastError: Error?
        for delay in retryDelays {
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }
            do {
                return try await patchChunk(uploadURL: uploadURL, offset: offset, chunk: chunk)
            } catch {
                lastError = error
            }
        }
        throw LearningBackendError(
            localizedKey: "error.tus.chunk_failed",
            arguments: [lastError.map(friendlyError) ?? localized("common.unknown")],
            cause: lastError
        )
    }

    private func patchChunk(uploadURL: String, offset: Int64, chunk: Data) async throws -> Int64 {
        guard let url = URL(string: uploadURL) else {
            throw LearningBackendError(localizedKey: "error.server.invalid_address")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 30
        request.setValue(Self.resumableVersion, forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, from: chunk)
        try validate(response: response, data: data)
        let nextOffset = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Upload-Offset")
            .flatMap(Int64.init)
        return nextOffset ?? offset + Int64(chunk.count)
    }

    static func checkEndpoint(_ endpoint: String, session: URLSession = .shared) async throws {
        guard let url = URL(string: endpoint) else {
            throw LearningBackendError(localizedKey: "error.server.invalid_address")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let tusVersion = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Tus-Resumable") ?? ""
        if tusVersion.isEmpty {
            throw LearningBackendError(localizedKey: "error.tus.version_missing")
        }
    }

    static func preferredEndpoint(configuredEndpoint: String, serverEndpoint: String?) -> String {
        let configured = configuredEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return normalizeTUSBaseURL(configured)
        }
        return normalizeTUSBaseURL(serverEndpoint ?? "")
    }

    static func resolveUploadURL(endpoint: String, location: String) throws -> String {
        guard let endpointURL = URL(string: endpoint) else {
            throw LearningBackendError(localizedKey: "error.tus.location_invalid")
        }
        if location.hasPrefix("http://") || location.hasPrefix("https://") {
            guard let absolute = URL(string: location) else {
                throw LearningBackendError(localizedKey: "error.tus.location_invalid")
            }
            return absolute.absoluteString
        }
        if location.hasPrefix("/") {
            guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false),
                  let locationComponents = URLComponents(string: location) else {
                throw LearningBackendError(localizedKey: "error.tus.location_invalid")
            }
            let endpointPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let locationPath = locationComponents.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let endpointSegments = endpointPath.split(separator: "/").map(String.init)
            let locationSegments = locationPath.split(separator: "/").map(String.init)

            if locationSegments.starts(with: endpointSegments) {
                components.path = "/\(locationPath)"
            } else if let filesIndex = endpointSegments.lastIndex(of: "files"),
                      locationSegments.first == "files" {
                let proxyPrefix = endpointSegments[..<filesIndex]
                components.path = "/\((Array(proxyPrefix) + locationSegments).joined(separator: "/"))"
            } else {
                components.path = "/\(locationPath)"
            }
            components.query = locationComponents.query
            components.fragment = locationComponents.fragment
            guard let resolved = components.url else {
                throw LearningBackendError(localizedKey: "error.tus.location_invalid")
            }
            return resolved.absoluteString
        }
        guard let resolved = URL(string: location, relativeTo: endpointURL)?.absoluteURL else {
            throw LearningBackendError(localizedKey: "error.tus.location_invalid")
        }
        return resolved.absoluteString
    }

    static func extractTusUploadId(_ uploadURL: String) -> String? {
        uploadURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .last
            .map(String.init)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LearningBackendError(localizedKey: "error.server.invalid_response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LearningBackendError(
                LearningBackendClient.parseErrorMessage(String(data: data, encoding: .utf8) ?? "", status: httpResponse.statusCode),
                statusCode: httpResponse.statusCode
            )
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        try Self.validate(response: response, data: data)
    }
}
