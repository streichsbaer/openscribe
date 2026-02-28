import Foundation

final class WhisperCppProvider: TranscriptionProvider {
    let id = "whispercpp"
    let displayName = "Local whisper.cpp"

    private let binaryURL: URL
    private let modelManager: ModelDownloadManager

    init(binaryURL: URL, modelManager: ModelDownloadManager) {
        self.binaryURL = binaryURL
        self.modelManager = modelManager
    }

    func transcribe(audioFileURL: URL, language: String?, model: String) async throws -> TranscriptResult {
        let start = Date()

        if !modelManager.isInstalled(modelID: model) {
            throw ProviderError.missingModel(model)
        }
        let modelURL = modelManager.localPath(for: model)

        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-\(UUID().uuidString)")

        var args = [
            "-m", modelURL.path,
            "-f", audioFileURL.path,
            "-otxt",
            "-of", outputBase.path,
            "-nt",
            "-ng"
        ]

        if let language, !language.isEmpty {
            args.append(contentsOf: ["-l", language.lowercased() == "auto" ? "auto" : language])
        } else {
            args.append(contentsOf: ["-l", "auto"])
        }

        let processResult = try await runWhisperProcess(arguments: args)
        let outputFile = outputBase.appendingPathExtension("txt")

        guard processResult.terminationStatus == 0 else {
            throw ProviderError.processFailed(processResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let text = try? String(contentsOf: outputFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            if !processResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ProviderError.processFailed(processResult.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            throw ProviderError.invalidResponse
        }

        try? FileManager.default.removeItem(at: outputFile)

        let latency = Int(Date().timeIntervalSince(start) * 1_000)
        return TranscriptResult(text: text, providerId: id, model: model, latencyMs: latency)
    }

    private func runWhisperProcess(arguments: [String]) async throws -> WhisperProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [binaryURL] in
                do {
                    let process = Process()
                    process.executableURL = binaryURL
                    process.arguments = arguments

                    let stderrPipe = Pipe()
                    process.standardError = stderrPipe
                    process.standardOutput = Pipe()

                    try process.run()
                    process.waitUntilExit()

                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: WhisperProcessResult(
                        terminationStatus: process.terminationStatus,
                        standardError: stderr
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct WhisperProcessResult {
    let terminationStatus: Int32
    let standardError: String
}
