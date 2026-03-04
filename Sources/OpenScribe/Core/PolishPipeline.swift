import Foundation

struct PolishPipeline {
    let providerFactory: ProviderFactory

    @MainActor
    func run(rawText: String, rulesMarkdown: String, settings: AppSettings) async throws -> PolishResult {
        let provider = try providerFactory.polishProvider(id: settings.polishProviderID)
        let instruction: String?
        if settings.polishCustomInstructionEnabled == true {
            instruction = normalizedInstruction(settings.polishInstruction)
        } else {
            instruction = nil
        }
        return try await provider.polish(
            rawText: rawText,
            rulesMarkdown: rulesMarkdown,
            model: settings.polishModel,
            instruction: instruction
        )
    }
}
