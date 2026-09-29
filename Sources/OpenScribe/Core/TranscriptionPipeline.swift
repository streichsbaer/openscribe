import Foundation

struct TranscriptionPipeline {
    let providerFactory: ProviderFactory

    @MainActor
    func run(audioFileURL: URL, settings: AppSettings) async throws -> TranscriptResult {
        let provider = try providerFactory.transcriptionProvider(id: settings.transcriptionProviderID, settings: settings)

        let language: String?
        if settings.languageMode.lowercased() == "auto" {
            language = nil
        } else {
            language = settings.languageMode
        }

        let instruction: String?
        if settings.transcriptionCustomInstructionEnabled == true {
            instruction = normalizedInstruction(settings.transcriptionInstruction)
        } else {
            instruction = nil
        }

        let model = settings.transcriptionModel
        return try await provider.transcribe(
            audioFileURL: audioFileURL,
            language: language,
            model: model,
            instruction: instruction
        )
    }
}
