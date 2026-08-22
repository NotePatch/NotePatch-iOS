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
        existingUploadURL: String? = nil,
        onUploadCreated: ((String) async -> Void)? = nil,
        onProgress: @escaping (Int64, Int64) async -> Void
    ) async throws -> TusUploadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LearningBackendError(localizedKey: "error.upload.file_missing")
        }
        let sizeBytes = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
        let uploadURL: String
        if let existingUploadURL, !existingUploadURL.isEmpty {
            uploadURL = existingUploadURL
        } else {
            uploadURL = try await createUpload(endpoint: endpoint, sizeBytes: sizeBytes, metadataHeader: metadataHeader)
            await onUploadCreated?(uploadURL)
        }
        let initialOffset = try await uploadOffset(uploadURL: uploadURL, expectedLength: sizeBytes)
        await onProgress(initialOffset, sizeBytes)
        let uploadedOffset = try await uploadChunks(
            fileURL: fileURL,
            uploadURL: uploadURL,
            totalBytes: sizeBytes,
            initialOffset: initialOffset,
            onProgress: onProgress
        )
        let verifiedOffset = try await uploadOffset(uploadURL: uploadURL, expectedLength: sizeBytes)
        guard uploadedOffset == sizeBytes, verifiedOffset == sizeBytes else {
            throw LearningBackendError(
                localizedKey: "error.tus.incomplete",
                arguments: [String(verifiedOffset), String(sizeBytes)]
            )
        }
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
        initialOffset: Int64,
        onProgress: @escaping (Int64, Int64) async -> Void
    ) async throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var offset = initialOffset
        while offset < totalBytes {
            try handle.seek(toOffset: UInt64(offset))
            let remaining = totalBytes - offset
            let size = min(Self.chunkSize, Int(remaining))
            guard let chunk = try handle.read(upToCount: size), !chunk.isEmpty else {
                throw LearningBackendError(localizedKey: "error.tus.file_read_incomplete")
            }
            offset = try await patchWithRetry(
                uploadURL: uploadURL,
                offset: offset,
                chunk: chunk,
                totalBytes: totalBytes
            )
            await onProgress(offset, totalBytes)
        }
        return offset
    }

    private func patchWithRetry(uploadURL: String, offset: Int64, chunk: Data, totalBytes: Int64) async throws -> Int64 {
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
                if let serverOffset = try? await uploadOffset(uploadURL: uploadURL, expectedLength: totalBytes) {
                    if serverOffset == offset + Int64(chunk.count) {
                        return serverOffset
                    }
                    if serverOffset != offset {
                        throw LearningBackendError(
                            localizedKey: "error.tus.offset_mismatch",
                            arguments: [String(serverOffset), String(offset)]
                        )
                    }
                }
            }
        }
        throw LearningBackendError(
            localizedKey: "error.tus.chunk_failed",
            arguments: [lastError.map(friendlyError) ?? localized("common.unknown")],
            cause: lastError
        )
    }

    private func uploadOffset(uploadURL: String, expectedLength: Int64) async throws -> Int64 {
        guard let url = URL(string: uploadURL) else {
            throw LearningBackendError(localizedKey: "error.server.invalid_address")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30
        request.setValue(Self.resumableVersion, forHTTPHeaderField: "Tus-Resumable")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        guard let http = response as? HTTPURLResponse,
              let offsetText = http.value(forHTTPHeaderField: "Upload-Offset"),
              let offset = Int64(offsetText),
              offset >= 0,
              offset <= expectedLength else {
            throw LearningBackendError(localizedKey: "error.tus.offset_missing")
        }
        if let lengthText = http.value(forHTTPHeaderField: "Upload-Length"),
           let length = Int64(lengthText),
           length != expectedLength {
            throw LearningBackendError(
                localizedKey: "error.tus.length_mismatch",
                arguments: [String(length), String(expectedLength)]
            )
        }
        return offset
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
        let server = serverEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let components = URLComponents(string: server),
           let scheme = components.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           components.host != nil {
            return normalizeTUSBaseURL(server)
        }
        let configured = configuredEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return normalizeTUSBaseURL(configured)
        }
        return normalizeTUSBaseURL(server)
    }

    static func resolveUploadURL(endpoint: String, location: String) throws -> String {
        guard let endpointURL = URL(string: endpoint) else {
            throw LearningBackendError(localizedKey: "error.tus.location_invalid")
        }
        if location.hasPrefix("http://") || location.hasPrefix("https://") {
            guard URL(string: location) != nil else {
                throw LearningBackendError(localizedKey: "error.tus.location_invalid")
            }
            return location
        }
        guard let resolved = URL(string: location, relativeTo: endpointURL)?.absoluteURL else {
            throw LearningBackendError(localizedKey: "error.tus.location_invalid")
        }
        return resolved.absoluteString
    }

    static func extractTusUploadId(_ uploadURL: String) -> String? {
        guard let url = URL(string: uploadURL) else { return nil }
        let value = url.lastPathComponent
        return value.isEmpty ? nil : value
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
