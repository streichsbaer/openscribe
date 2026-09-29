import CryptoKit
import Foundation

final class ModelDownloadManager: ObservableObject {
    nonisolated static let modelRepositoryRevision = "5359861c739e955e79d9a303bcbc70fb988958b1"
    static let parakeetUltraModelID = "parakeet-ultra"
    static let parakeetVocabularyModelID = "parakeet-vocabulary"

    @Published var activeDownloadModelID: String?
    @Published var progress: Double = 0

    let catalog: [ModelAsset]

    private let whisperDirectory: URL
    private let parakeetDirectory: URL
    private let fileManager: FileManager

    init(layout: DirectoryLayout, fileManager: FileManager = .default) {
        self.whisperDirectory = layout.whisperModels
        self.parakeetDirectory = layout.parakeetModels
        self.fileManager = fileManager
        self.catalog = [
            Self.parakeetAsset(
                id: Self.parakeetUltraModelID,
                kind: .parakeet,
                displayName: "Parakeet Ultra",
                detail: "Fast, accurate local transcription in 25 European languages.",
                repository: ParakeetModelFiles.ultraRepository,
                revision: ParakeetModelFiles.ultraRevision,
                files: ParakeetModelFiles.ultraFiles
            ),
            Self.parakeetAsset(
                id: Self.parakeetVocabularyModelID,
                kind: .parakeetVocabulary,
                displayName: "Parakeet vocabulary",
                detail: "Small model that lets Parakeet spell your vocabulary terms.",
                repository: ParakeetModelFiles.vocabularyBoostRepository,
                revision: ParakeetModelFiles.vocabularyBoostRevision,
                files: ParakeetModelFiles.vocabularyBoostFiles
            ),
            Self.whisperAsset(
                id: "tiny",
                detail: "Smallest Whisper download, lowest accuracy.",
                sizeBytes: 77_691_713,
                sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
            ),
            Self.whisperAsset(
                id: "base",
                detail: "Small Whisper download, lower accuracy.",
                sizeBytes: 147_951_465,
                sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
            ),
            Self.whisperAsset(
                id: "small",
                detail: "Balanced Whisper size and accuracy.",
                sizeBytes: 487_601_967,
                sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
            ),
            Self.whisperAsset(
                id: "medium",
                detail: "Larger download. Slower and less accurate than large-v3-turbo.",
                sizeBytes: 1_533_763_059,
                sha256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208"
            ),
            Self.whisperAsset(
                id: "large-v3-turbo",
                detail: "Best Whisper accuracy, the same model Groq runs.",
                sizeBytes: 1_624_555_275,
                sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
            )
        ]
    }

    func asset(for modelID: String) -> ModelAsset? {
        catalog.first { $0.id == modelID }
    }

    func transcriptionModels(providerID: String) -> [ModelAsset] {
        catalog.filter { $0.isTranscriptionModel && $0.kind.providerID == providerID }
    }

    /// The ggml file for a whisper model, or the Core ML folder for a Parakeet model.
    func localPath(for modelID: String) -> URL {
        if let asset = asset(for: modelID), asset.kind != .whisper {
            return parakeetDirectory.appendingPathComponent(modelID, isDirectory: true)
        }
        return whisperDirectory.appendingPathComponent("ggml-\(modelID).bin")
    }

    func isInstalled(modelID: String) -> Bool {
        fileManager.fileExists(atPath: localPath(for: modelID).path)
    }

    func installedModels() -> [String] {
        catalog.map(\.id).filter(isInstalled(modelID:)).sorted()
    }

    func remove(modelID: String) throws {
        let url = localPath(for: modelID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func installedSizeBytes(modelID: String) -> Int64 {
        let url = localPath(for: modelID)
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    func totalInstalledSizeBytes() -> Int64 {
        installedModels().reduce(0) { partial, modelID in
            partial + installedSizeBytes(modelID: modelID)
        }
    }

    /// Downloads every file into a staging folder, verifies size and SHA256, then moves the
    /// finished model into place. A model path only exists once it is complete.
    @MainActor
    func ensureInstalled(modelID: String) async throws -> URL {
        let destination = localPath(for: modelID)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        guard let asset = asset(for: modelID) else {
            throw ProviderError.missingModel(modelID)
        }

        activeDownloadModelID = modelID
        progress = 0
        defer {
            activeDownloadModelID = nil
            progress = 0
        }

        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(modelID)-\(UUID().uuidString).download", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 3_600
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let totalBytes = max(Double(asset.expectedSizeBytes), 1)
        var completedBytes: Int64 = 0
        for file in asset.files {
            let target = staging.appendingPathComponent(file.path)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

            let completed = completedBytes
            let progressDelegate = DownloadProgressDelegate { [weak self] value in
                Task { @MainActor [weak self] in
                    self?.progress = (Double(completed) + value * Double(file.sizeBytes)) / totalBytes
                }
            }
            let request = URLRequest(
                url: asset.downloadURL(for: file),
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 600
            )
            let (downloadedURL, _) = try await session.download(for: request, delegate: progressDelegate)
            try fileManager.moveItem(at: downloadedURL, to: target)
            try await Self.validateOffMain(file: file, modelID: modelID, at: target)
            completedBytes += file.sizeBytes
            progress = Double(completedBytes) / totalBytes
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let finished = asset.kind == .whisper ? staging.appendingPathComponent(asset.files[0].path) : staging
        try fileManager.moveItem(at: finished, to: destination)
        return destination
    }

    private static func whisperAsset(id: String, detail: String, sizeBytes: Int64, sha256: String) -> ModelAsset {
        ModelAsset(
            id: id,
            kind: .whisper,
            displayName: "Whisper \(id)",
            detail: detail,
            repositoryURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(modelRepositoryRevision)/")!,
            files: [ModelAssetFile(path: "ggml-\(id).bin", sizeBytes: sizeBytes, sha256: sha256)]
        )
    }

    private static func parakeetAsset(
        id: String,
        kind: ModelAssetKind,
        displayName: String,
        detail: String,
        repository: String,
        revision: String,
        files: [ModelAssetFile]
    ) -> ModelAsset {
        ModelAsset(
            id: id,
            kind: kind,
            displayName: displayName,
            detail: detail,
            repositoryURL: URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/")!,
            files: files
        )
    }

    private nonisolated static func validateOffMain(file: ModelAssetFile, modelID: String, at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result {
                    try validate(file: file, modelID: modelID, at: url)
                })
            }
        }
    }

    nonisolated static func validate(file: ModelAssetFile, modelID: String, at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, abs(Int64(size) - file.sizeBytes) > 4_096 {
            throw ProviderError.processFailed("Downloaded model size mismatch for \(modelID) (\(file.path)).")
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let hash = hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        if hash.lowercased() != file.sha256.lowercased() {
            throw ProviderError.processFailed("Downloaded model hash mismatch for \(modelID) (\(file.path)).")
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
