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
            throw LearningBackendError("Upload file does not exist.")
        }
        let sizeBytes = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
        let uploadURL = try await createUpload(endpoint: endpoint, sizeBytes: sizeBytes, metadataHeader: metadataHeader)
        try await uploadChunks(fileURL: fileURL, uploadURL: uploadURL, totalBytes: sizeBytes, onProgress: onProgress)
        return TusUploadResult(uploadURL: uploadURL, uploadId: Self.extractTusUploadId(uploadURL))
    }

    private func createUpload(endpoint: String, sizeBytes: Int64, metadataHeader: String) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw LearningBackendError("Server address format is invalid. Please check the API or TUS address.")
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
            throw LearningBackendError("TUSD did not return a Location header.")
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
            "TUS chunk upload failed: \(lastError?.localizedDescription ?? "Unknown error")",
            cause: lastError
        )
    }

    private func patchChunk(uploadURL: String, offset: Int64, chunk: Data) async throws -> Int64 {
        guard let url = URL(string: uploadURL) else {
            throw LearningBackendError("Server address format is invalid. Please check the API or TUS address.")
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
            throw LearningBackendError("Server address format is invalid. Please check the API or TUS address.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let tusVersion = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Tus-Resumable") ?? ""
        if tusVersion.isEmpty {
            throw LearningBackendError("TUSD did not return Tus-Resumable header.")
        }
    }

    static func resolveUploadURL(endpoint: String, location: String) throws -> String {
        guard let endpointURL = URL(string: endpoint),
              let resolved = URL(string: location, relativeTo: endpointURL)?.absoluteURL else {
            throw LearningBackendError("TUSD returned an invalid Location.")
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
            throw LearningBackendError("Server response is invalid.")
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
