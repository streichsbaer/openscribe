import AVFoundation
import Foundation

final class WhisperCppProvider: TranscriptionProvider, @unchecked Sendable {
    let id = "whispercpp"
    let displayName = "Local whisper.cpp"

    /// Whisper can loop on long recordings when given a prompt, so the vocabulary prompt only
    /// applies up to this length (measured with Scripts/stt-bench, run 2026-09-29-devterms-v1).
    static let vocabularyPromptMaxSeconds: Double = 120

    private let binaryURL: URL
    private let modelManager: ModelDownloadManager
    private let vocabulary: [VocabularyEntry]

    init(binaryURL: URL, modelManager: ModelDownloadManager, vocabulary: [VocabularyEntry]) {
        self.binaryURL = binaryURL
        self.modelManager = modelManager
        self.vocabulary = vocabulary
    }

    func transcribe(audioFileURL: URL, language: String?, model: String, instruction: String?) async throws -> TranscriptResult {
        let start = Date()
        // whisper.cpp CLI path has no instruction parameter; text shaping occurs in polish stage.
        _ = instruction

        if !modelManager.isInstalled(modelID: model) {
            throw ProviderError.missingModel(model)
        }
        let modelURL = modelManager.localPath(for: model)
        let preparedInputURL = try prepareInputWAV(for: audioFileURL)

        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-\(UUID().uuidString)")

        let args = Self.arguments(
            modelPath: modelURL.path,
            inputPath: preparedInputURL.path,
            outputBasePath: outputBase.path,
            language: language,
            prompt: Self.vocabularyPrompt(vocabulary, audioDurationSeconds: Self.durationSeconds(of: preparedInputURL))
        )

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
        return TranscriptResult(
            text: text,
            providerId: id,
            model: model,
            latencyMs: latency,
            inputTokens: nil,
            outputTokens: nil
        )
    }

    static func arguments(
        modelPath: String,
        inputPath: String,
        outputBasePath: String,
        language: String?,
        prompt: String? = nil,
        usesGPU: Bool = defaultUsesGPU
    ) -> [String] {
        var args = [
            "-m", modelPath,
            "-f", inputPath,
            "-otxt",
            "-of", outputBasePath,
            "-nt"
        ]

        if !usesGPU {
            args.append("-ng")
        }

        if let prompt {
            args.append(contentsOf: ["--prompt", prompt])
        }

        if let language, !language.isEmpty {
            args.append(contentsOf: ["-l", language.lowercased() == "auto" ? "auto" : language])
        } else {
            args.append(contentsOf: ["-l", "auto"])
        }
        return args
    }

    static func vocabularyPrompt(_ vocabulary: [VocabularyEntry], audioDurationSeconds: Double?) -> String? {
        guard let audioDurationSeconds, audioDurationSeconds <= vocabularyPromptMaxSeconds else {
            return nil
        }
        return VocabularyPrompt.whisperGlossary(vocabulary)
    }

    private static func durationSeconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else {
            return nil
        }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    // Apple Silicon runs whisper.cpp on Metal. Intel builds stay on the CPU.
    #if arch(arm64)
    static let defaultUsesGPU = true
    #else
    static let defaultUsesGPU = false
    #endif

    private func prepareInputWAV(for audioFileURL: URL) throws -> URL {
        if audioFileURL.pathExtension.lowercased() == "wav" {
            return audioFileURL
        }

        let siblingWAV = audioFileURL.deletingPathExtension().appendingPathExtension("wav")
        if FileManager.default.fileExists(atPath: siblingWAV.path) {
            return siblingWAV
        }

        try AudioTranscoder.transcodeToWAV(sourceURL: audioFileURL, destinationURL: siblingWAV)
        return siblingWAV
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
