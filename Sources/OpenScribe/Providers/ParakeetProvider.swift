import CoreML
import FluidAudio
import Foundation

/// Keeps one Parakeet model loaded between dictations.
/// Loading takes a few seconds; transcribing a 30 second dictation takes under 150 ms on Apple Silicon.
actor ParakeetEngine {
    struct Configuration: Equatable, Sendable {
        let modelDirectory: URL
        let usesNeuralEngine: Bool
    }

    private var loaded: (configuration: Configuration, manager: AsrManager, decoderLayers: Int)?

    func transcribe(audioFileURL: URL, configuration: Configuration, language: String?) async throws -> String {
        let (manager, decoderLayers) = try await load(configuration)
        let samples = try AudioConverter().resampleAudioFile(audioFileURL)
        var state = TdtDecoderState.make(decoderLayers: decoderLayers)
        let result = try await manager.transcribe(
            samples,
            decoderState: &state,
            language: Self.languageHint(for: language)
        )
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prepare(configuration: Configuration) async throws {
        _ = try await load(configuration)
    }

    func unload() {
        loaded = nil
    }

    private func load(_ configuration: Configuration) async throws -> (AsrManager, Int) {
        if let loaded, loaded.configuration == configuration {
            return (loaded.manager, loaded.decoderLayers)
        }
        loaded = nil
        let models = try AsrModels.loadLocal(
            from: configuration.modelDirectory,
            version: .ultra,
            encoderComputeUnits: configuration.usesNeuralEngine ? .cpuAndNeuralEngine : .cpuAndGPU
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        let decoderLayers = await manager.decoderLayerCount
        // The first inference compiles GPU or Neural Engine kernels; pay that cost here, not on a dictation.
        var warmupState = TdtDecoderState.make(decoderLayers: decoderLayers)
        _ = try await manager.transcribe([Float](repeating: 0, count: 16_000), decoderState: &warmupState)
        loaded = (configuration, manager, decoderLayers)
        return (manager, decoderLayers)
    }

    /// Parakeet detects the language itself. A known language code narrows its output script.
    static func languageHint(for languageMode: String?) -> Language? {
        guard let languageMode else {
            return nil
        }
        return Language(rawValue: languageMode.lowercased())
    }
}

final class ParakeetProvider: TranscriptionProvider, @unchecked Sendable {
    let id = "parakeet"
    let displayName = "Local Parakeet"

    private let engine: ParakeetEngine
    private let modelManager: ModelDownloadManager
    private let usesNeuralEngine: Bool

    init(engine: ParakeetEngine, modelManager: ModelDownloadManager, usesNeuralEngine: Bool) {
        self.engine = engine
        self.modelManager = modelManager
        self.usesNeuralEngine = usesNeuralEngine
    }

    func transcribe(audioFileURL: URL, language: String?, model: String, instruction: String?) async throws -> TranscriptResult {
        let start = Date()
        // Parakeet has no prompt input; text shaping occurs in the polish stage.
        _ = instruction

        guard modelManager.isInstalled(modelID: model) else {
            throw ProviderError.missingModel(model)
        }
        let text = try await engine.transcribe(
            audioFileURL: audioFileURL,
            configuration: .init(modelDirectory: modelManager.localPath(for: model), usesNeuralEngine: usesNeuralEngine),
            language: language
        )
        guard !text.isEmpty else {
            throw ProviderError.invalidResponse
        }

        return TranscriptResult(
            text: text,
            providerId: id,
            model: model,
            latencyMs: Int(Date().timeIntervalSince(start) * 1_000),
            inputTokens: nil,
            outputTokens: nil
        )
    }
}
