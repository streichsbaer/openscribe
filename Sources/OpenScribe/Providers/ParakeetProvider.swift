import CoreML
import FluidAudio
import Foundation

/// Keeps one Parakeet model, and the vocabulary booster when used, loaded between dictations.
/// Loading takes a few seconds; transcribing a 30 second dictation takes under 150 ms on Apple Silicon.
actor ParakeetEngine {
    struct Configuration: Equatable, Sendable {
        let modelDirectory: URL
        let usesNeuralEngine: Bool
    }

    struct Vocabulary: Equatable, Sendable {
        let entries: [VocabularyEntry]
        let modelDirectory: URL
    }

    struct Transcript: Equatable, Sendable {
        let text: String
        let vocabularyFixes: [VocabularyFix]
    }

    private var loaded: (configuration: Configuration, manager: AsrManager, decoderLayers: Int)?
    private var booster: (vocabulary: Vocabulary, booster: ParakeetVocabularyBooster)?

    func transcribe(
        audioFileURL: URL,
        configuration: Configuration,
        vocabulary: Vocabulary?,
        language: String?
    ) async throws -> Transcript {
        let (manager, decoderLayers) = try await load(configuration)
        let samples = try AudioConverter().resampleAudioFile(audioFileURL)
        var state = TdtDecoderState.make(decoderLayers: decoderLayers)
        let result = try await manager.transcribe(
            samples,
            decoderState: &state,
            language: Self.languageHint(for: language)
        )
        var text = result.text
        var fixes: [VocabularyFix] = []
        if let vocabulary, let tokenTimings = result.tokenTimings {
            let rescore = try await loadBooster(vocabulary).rescore(text: text, tokenTimings: tokenTimings, samples: samples)
            text = rescore.text
            fixes = rescore.fixes
        }
        return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines), vocabularyFixes: fixes)
    }

    func prepare(configuration: Configuration, vocabulary: Vocabulary?) async throws {
        _ = try await load(configuration)
        if let vocabulary {
            _ = try await loadBooster(vocabulary)
        }
    }

    func unload() {
        loaded = nil
        booster = nil
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

    private func loadBooster(_ vocabulary: Vocabulary) async throws -> ParakeetVocabularyBooster {
        if let booster, booster.vocabulary == vocabulary {
            return booster.booster
        }
        booster = nil
        let loadedBooster = try await ParakeetVocabularyBooster(
            entries: vocabulary.entries,
            modelDirectory: vocabulary.modelDirectory
        )
        booster = (vocabulary, loadedBooster)
        return loadedBooster
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
    private let vocabulary: [VocabularyEntry]

    init(engine: ParakeetEngine, modelManager: ModelDownloadManager, usesNeuralEngine: Bool, vocabulary: [VocabularyEntry]) {
        self.engine = engine
        self.modelManager = modelManager
        self.usesNeuralEngine = usesNeuralEngine
        self.vocabulary = vocabulary
    }

    func transcribe(audioFileURL: URL, language: String?, model: String, instruction: String?) async throws -> TranscriptResult {
        let start = Date()
        // Parakeet has no prompt input; vocabulary boosting and polish shape the text.
        _ = instruction

        guard modelManager.isInstalled(modelID: model) else {
            throw ProviderError.missingModel(model)
        }
        let transcript = try await engine.transcribe(
            audioFileURL: audioFileURL,
            configuration: .init(modelDirectory: modelManager.localPath(for: model), usesNeuralEngine: usesNeuralEngine),
            vocabulary: Self.boostVocabulary(vocabulary, modelManager: modelManager),
            language: language
        )
        guard !transcript.text.isEmpty else {
            throw ProviderError.invalidResponse
        }

        return TranscriptResult(
            text: transcript.text,
            providerId: id,
            model: model,
            latencyMs: Int(Date().timeIntervalSince(start) * 1_000),
            inputTokens: nil,
            outputTokens: nil,
            vocabularyFixes: transcript.vocabularyFixes
        )
    }

    /// Boosting runs once the vocabulary model is installed; until then Parakeet transcribes without it.
    static func boostVocabulary(_ entries: [VocabularyEntry], modelManager: ModelDownloadManager) -> ParakeetEngine.Vocabulary? {
        let modelID = ModelDownloadManager.parakeetVocabularyModelID
        guard !entries.isEmpty, modelManager.isInstalled(modelID: modelID) else {
            return nil
        }
        return .init(entries: entries, modelDirectory: modelManager.localPath(for: modelID))
    }
}
