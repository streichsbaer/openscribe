import CryptoKit
import Foundation

final class ModelDownloadManager: ObservableObject {
    nonisolated static let modelRepositoryRevision = "5359861c739e955e79d9a303bcbc70fb988958b1"

    @Published var activeDownloadModelID: String?
    @Published var progress: Double = 0

    let catalog: [ModelAsset]

    private let modelsDirectory: URL
    private let fileManager: FileManager

    init(layout: DirectoryLayout, fileManager: FileManager = .default) {
        self.modelsDirectory = layout.models
        self.fileManager = fileManager
        self.catalog = [
            ModelAsset(
                id: "tiny",
                displayName: "tiny",
                downloadURL: Self.downloadURL(for: "tiny"),
                expectedSizeBytes: 77_691_713,
                sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
            ),
            ModelAsset(
                id: "base",
                displayName: "base",
                downloadURL: Self.downloadURL(for: "base"),
                expectedSizeBytes: 147_951_465,
                sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
            ),
            ModelAsset(
                id: "small",
                displayName: "small",
                downloadURL: Self.downloadURL(for: "small"),
                expectedSizeBytes: 487_601_967,
                sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
            ),
            ModelAsset(
                id: "medium",
                displayName: "medium",
                downloadURL: Self.downloadURL(for: "medium"),
                expectedSizeBytes: 1_533_763_059,
                sha256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208"
            ),
            ModelAsset(
                id: "large-v3-turbo",
                displayName: "large-v3-turbo",
                downloadURL: Self.downloadURL(for: "large-v3-turbo"),
                expectedSizeBytes: 1_624_555_275,
                sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
            )
        ]
    }

    func localPath(for modelID: String) -> URL {
        modelsDirectory.appendingPathComponent("ggml-\(modelID).bin")
    }

    func isInstalled(modelID: String) -> Bool {
        fileManager.fileExists(atPath: localPath(for: modelID).path)
    }

    func installedModels() -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return contents
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }
            .map { $0.replacingOccurrences(of: "ggml-", with: "").replacingOccurrences(of: ".bin", with: "") }
            .sorted()
    }

    func remove(modelID: String) throws {
        let url = localPath(for: modelID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func installedSizeBytes(modelID: String) -> Int64 {
        let url = localPath(for: modelID)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return 0
        }
        return Int64(size)
    }

    func totalInstalledSizeBytes() -> Int64 {
        installedModels().reduce(0) { partial, modelID in
            partial + installedSizeBytes(modelID: modelID)
        }
    }

    @MainActor
    func ensureInstalled(modelID: String) async throws -> URL {
        let destination = localPath(for: modelID)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        guard let asset = catalog.first(where: { $0.id == modelID }) else {
            throw ProviderError.missingModel(modelID)
        }

        activeDownloadModelID = modelID
        progress = 0
        defer {
            activeDownloadModelID = nil
            progress = 0
        }

        let temp = destination.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).download")
        let request = URLRequest(
            url: asset.downloadURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 600
        )

        let progressDelegate = DownloadProgressDelegate { [weak self] value in
            Task { @MainActor [weak self] in
                self?.progress = value
            }
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 3_600
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (downloadedURL, _) = try await session.download(for: request, delegate: progressDelegate)
        if fileManager.fileExists(atPath: temp.path) {
            try fileManager.removeItem(at: temp)
        }
        try fileManager.moveItem(at: downloadedURL, to: temp)
        progress = 1

        do {
            try await Self.validateOffMain(asset: asset, file: temp)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temp, to: destination)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
        return destination
    }

    private nonisolated static func downloadURL(for modelID: String) -> URL {
        URL(
            string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(modelRepositoryRevision)/ggml-\(modelID).bin"
        )!
    }

    private nonisolated static func validateOffMain(asset: ModelAsset, file: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    try validate(asset: asset, file: file)
                })
            }
        }
    }

    private nonisolated static func validate(asset: ModelAsset, file: URL) throws {
        let values = try file.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize {
            let expected = Int(asset.expectedSizeBytes)
            if expected > 0 && abs(size - expected) > 4_096 {
                throw ProviderError.processFailed("Downloaded model size mismatch for \(asset.id).")
            }
        }

        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let hash = hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        if hash.lowercased() != asset.sha256.lowercased() {
            throw ProviderError.processFailed("Downloaded model hash mismatch for \(asset.id).")
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }
        let value = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        onProgress(value)
    }
}
