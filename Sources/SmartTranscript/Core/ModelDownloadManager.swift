import CryptoKit
import Foundation

final class ModelDownloadManager: ObservableObject {
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
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=true")!,
                expectedSizeBytes: 77_691_713,
                sha256: nil
            ),
            ModelAsset(
                id: "base",
                displayName: "base",
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true")!,
                expectedSizeBytes: 147_951_465,
                sha256: nil
            ),
            ModelAsset(
                id: "small",
                displayName: "small",
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=true")!,
                expectedSizeBytes: 487_601_967,
                sha256: nil
            ),
            ModelAsset(
                id: "medium",
                displayName: "medium",
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin?download=true")!,
                expectedSizeBytes: 1_533_763_059,
                sha256: nil
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

        let request = URLRequest(url: asset.downloadURL, timeoutInterval: 600)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let contentLength = response.expectedContentLength > 0 ? response.expectedContentLength : nil else {
            return try await writeWithoutProgress(stream: bytes, destination: destination, asset: asset)
        }

        let temp = destination.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).download")
        fileManager.createFile(atPath: temp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temp)

        var received: Int64 = 0
        for try await chunk in bytes {
            try handle.write(contentsOf: Data([chunk]))
            received += 1
            progress = min(1, Double(received) / Double(contentLength))
        }

        try handle.close()

        try validate(asset: asset, file: temp)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temp, to: destination)
        return destination
    }

    @MainActor
    private func writeWithoutProgress(stream: URLSession.AsyncBytes, destination: URL, asset: ModelAsset) async throws -> URL {
        let temp = destination.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).download")
        fileManager.createFile(atPath: temp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temp)
        for try await byte in stream {
            try handle.write(contentsOf: Data([byte]))
        }
        try handle.close()

        try validate(asset: asset, file: temp)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.moveItem(at: temp, to: destination)
        return destination
    }

    private func validate(asset: ModelAsset, file: URL) throws {
        let values = try file.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize {
            let expected = Int(asset.expectedSizeBytes)
            if expected > 0 && abs(size - expected) > 4_096 {
                throw ProviderError.processFailed("Downloaded model size mismatch for \(asset.id).")
            }
        }

        if let expectedHash = asset.sha256 {
            let data = try Data(contentsOf: file)
            let digest = SHA256.hash(data: data)
            let hash = digest.compactMap { String(format: "%02x", $0) }.joined()
            if hash.lowercased() != expectedHash.lowercased() {
                throw ProviderError.processFailed("Downloaded model hash mismatch for \(asset.id).")
            }
        }
    }
}
