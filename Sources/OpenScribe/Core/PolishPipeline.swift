import Foundation

struct PolishPipeline {
    let providerFactory: ProviderFactory

    @MainActor
    func run(
        rawText: String,
        rulesMarkdown: String,
        settings: AppSettings,
        vocabulary: [VocabularyEntry]
    ) async throws -> PolishResult {
        let provider = try providerFactory.polishProvider(id: settings.polishProviderID)
        let instruction: String?
        if settings.polishCustomInstructionEnabled == true {
            instruction = normalizedInstruction(settings.polishInstruction)
        } else {
            instruction = nil
        }
        let model = settings.polishModel
        return try await provider.polish(
            rawText: rawText,
            rulesMarkdown: VocabularyPrompt.polishRules(rulesMarkdown, entries: vocabulary),
            model: model,
            instruction: instruction
        )
    }
}
