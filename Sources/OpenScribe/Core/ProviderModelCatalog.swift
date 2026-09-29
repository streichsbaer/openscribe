import Foundation

enum ProviderModelUsage {
    case transcription
    case polish
}

enum ProviderBackend: String {
    case whispercpp
    case openai
    case groq
    case openrouter
    case gemini
    case cerebras

    var displayName: String {
        switch self {
        case .whispercpp:
            return "Local whisper.cpp"
        case .openai:
            return "OpenAI"
        case .groq:
            return "Groq"
        case .openrouter:
            return "OpenRouter"
        case .gemini:
            return "Gemini"
        case .cerebras:
            return "Cerebras"
        }
    }

    var statusID: String { rawValue }
}

struct ProviderConnectivityStatus: Equatable {
    enum State: Equatable {
        case idle
        case verifying
        case verified
        case failed
    }

    var state: State
    var detail: String

    static let idle = ProviderConnectivityStatus(state: .idle, detail: "Not verified")
}

enum ProviderModelCatalog {
    static func fallbackModels(for providerID: String, usage: ProviderModelUsage) -> [String] {
        switch (providerID, usage) {
        case ("whispercpp", .transcription):
            return ["tiny", "base", "small", "medium", "large-v3-turbo"]
        case ("openai_whisper", .transcription):
            return ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"]
        case ("openai_realtime_transcription", .transcription):
            return ["gpt-realtime-whisper"]
        case ("groq_whisper", .transcription):
            return ["whisper-large-v3", "whisper-large-v3-turbo"]
        case ("openrouter_transcribe", .transcription):
            return ["google/gemini-2.5-flash", "openai/gpt-4o-mini"]
        case ("gemini_transcribe", .transcription):
            return ["gemini-3-flash-preview", "gemini-2.5-flash"]
        case ("openai_polish", .polish):
            return ["gpt-5-nano", "gpt-5-mini"]
        case ("groq_polish", .polish):
            return ["openai/gpt-oss-120b", "llama-3.3-70b-versatile", "mixtral-8x7b-32768"]
        case ("openrouter_polish", .polish):
            return ["openai/gpt-5-nano", "openai/gpt-5-mini", "google/gemini-2.5-flash"]
        case ("gemini_polish", .polish):
            return ["gemini-2.5-flash"]
        case ("cerebras_polish", .polish):
            return ["gpt-oss-120b"]
        case (_, .transcription):
            return ["base"]
        case (_, .polish):
            return ["gpt-5-nano"]
        }
    }

    static func prioritizeRecommendedModel(
        _ models: [String],
        providerID: String,
        usage: ProviderModelUsage
    ) -> [String] {
        guard let recommended = recommendedModel(for: providerID, usage: usage),
              models.contains(recommended) else {
            return models
        }

        return [recommended] + models.filter { $0 != recommended }
    }

    static func filterModels(
        _ models: [String],
        providerID: String,
        backend: ProviderBackend,
        usage: ProviderModelUsage
    ) -> [String] {
        switch (backend, usage) {
        case (.openai, .transcription):
            let filtered = models.filter { id in
                let value = id.lowercased()
                if providerID == "openai_realtime_transcription" {
                    return value == "gpt-realtime-whisper" ||
                        (value.hasPrefix("gpt-realtime-") && value.contains("whisper"))
                }
                return (value.contains("transcribe") || value.contains("whisper")) &&
                    !value.hasPrefix("gpt-realtime-")
            }
            return filtered.sorted()
        case (.openai, .polish):
            return models.filter { !$0.lowercased().contains("transcribe") }.sorted()
        case (.groq, .transcription):
            return models.filter { $0.lowercased().contains("whisper") }.sorted()
        case (.groq, .polish):
            return models.filter { !$0.lowercased().contains("whisper") }.sorted()
        case (.whispercpp, _), (.openrouter, _), (.gemini, _), (.cerebras, _):
            return models.sorted()
        }
    }

    private static func recommendedModel(
        for providerID: String,
        usage: ProviderModelUsage
    ) -> String? {
        switch (providerID, usage) {
        case ("groq_polish", .polish):
            return "openai/gpt-oss-120b"
        case ("cerebras_polish", .polish):
            return "gpt-oss-120b"
        default:
            return nil
        }
    }
}
