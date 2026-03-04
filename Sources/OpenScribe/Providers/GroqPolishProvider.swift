import Foundation

final class GroqPolishProvider: PolishProvider {
    let id = "groq_polish"
    let displayName = "Groq Polish"

    private let apiKey: String
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func polish(rawText: String, rulesMarkdown: String, model: String, instruction: String?) async throws -> PolishResult {
        let start = Date()
        let response = try await performChatRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            model: model,
            systemPrompt: instruction,
            userPrompt: makePolishUserPrompt(rawText: rawText, rulesMarkdown: rulesMarkdown)
        )
        let polished = sanitizePolishedOutput(unwrapCodeBlockIfNeeded(response.text), rawText: rawText)

        return PolishResult(
            markdown: polished,
            providerId: id,
            model: model,
            latencyMs: Int(Date().timeIntervalSince(start) * 1_000),
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens
        )
    }
}
