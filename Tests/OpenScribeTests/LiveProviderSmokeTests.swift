import Foundation
import XCTest
@testable import OpenScribe

@MainActor
final class LiveProviderSmokeTests: XCTestCase {
    func testLiveProviderPipelineWithTTSAudio() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RUN_LIVE_PROVIDER_SMOKE"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_PROVIDER_SMOKE=1 to run live provider smoke tests.")
        }

        let audioURL = try resolveAudioURL(from: env)
        let language = env["LIVE_SMOKE_LANGUAGE"] ?? "auto"

        let sttProviderID = try requiredEnv("LIVE_SMOKE_STT_PROVIDER", in: env)
        let sttModel = try requiredEnv("LIVE_SMOKE_STT_MODEL", in: env)
        let sttProvider = try transcriptionProvider(id: sttProviderID, env: env)

        let transcript = try await sttProvider.transcribe(
            audioFileURL: audioURL,
            language: language,
            model: sttModel,
            instruction: nil
        )

        let rawText = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(rawText.isEmpty, "Transcription should return non-empty text.")
        print("[live-smoke] stt provider=\(transcript.providerId) model=\(transcript.model) latencyMs=\(transcript.latencyMs)")
        print("[live-smoke] raw=\(preview(rawText))")

        let runPolish = env["LIVE_SMOKE_RUN_POLISH"] != "0"
        guard runPolish else {
            return
        }

        let polishProviderID = try requiredEnv("LIVE_SMOKE_POLISH_PROVIDER", in: env)
        let polishModel = try requiredEnv("LIVE_SMOKE_POLISH_MODEL", in: env)
        let polishProvider = try polishProvider(id: polishProviderID, env: env)

        let polished = try await polishProvider.polish(
            rawText: rawText,
            rulesMarkdown: RulesStore.defaultTemplate,
            model: polishModel,
            instruction: nil
        )

        let polishedText = polished.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(polishedText.isEmpty, "Polish should return non-empty text.")
        print("[live-smoke] polish provider=\(polished.providerId) model=\(polished.model) latencyMs=\(polished.latencyMs)")
        print("[live-smoke] polished=\(preview(polishedText))")
    }

    private func resolveAudioURL(from env: [String: String]) throws -> URL {
        if let path = env["LIVE_SMOKE_AUDIO_PATH"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ProviderError.processFailed("LIVE_SMOKE_AUDIO_PATH does not exist: \(path)")
            }
            return url
        }

        throw ProviderError.processFailed("LIVE_SMOKE_AUDIO_PATH is required.")
    }

    private func requiredEnv(_ key: String, in env: [String: String]) throws -> String {
        guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw ProviderError.processFailed("Missing required env var: \(key)")
        }
        return value
    }

    private func transcriptionProvider(id: String, env: [String: String]) throws -> any TranscriptionProvider {
        switch id {
        case "openai_whisper":
            return OpenAIWhisperProvider(apiKey: try apiKey(for: .openAI, env: env))
        case "groq_whisper":
            return GroqWhisperProvider(apiKey: try apiKey(for: .groq, env: env))
        case "openrouter_transcribe":
            return OpenRouterTranscriptionProvider(apiKey: try apiKey(for: .openRouter, env: env))
        case "gemini_transcribe":
            return GeminiTranscriptionProvider(apiKey: try apiKey(for: .gemini, env: env))
        default:
            throw ProviderError.unsupported("Unsupported live smoke transcription provider: \(id)")
        }
    }

    private func polishProvider(id: String, env: [String: String]) throws -> any PolishProvider {
        switch id {
        case "openai_polish":
            return OpenAIPolishProvider(apiKey: try apiKey(for: .openAI, env: env))
        case "groq_polish":
            return GroqPolishProvider(apiKey: try apiKey(for: .groq, env: env))
        case "openrouter_polish":
            return OpenRouterPolishProvider(apiKey: try apiKey(for: .openRouter, env: env))
        case "gemini_polish":
            return GeminiPolishProvider(apiKey: try apiKey(for: .gemini, env: env))
        default:
            throw ProviderError.unsupported("Unsupported live smoke polish provider: \(id)")
        }
    }

    private func apiKey(for entry: KeychainEntry, env: [String: String]) throws -> String {
        for keyName in entry.environmentVariableNames {
            if let value = env[keyName]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        throw ProviderError.missingAPIKey(entry.providerDisplayName)
    }

    private func preview(_ value: String) -> String {
        let collapsed = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.count <= 180 {
            return collapsed
        }
        return String(collapsed.prefix(180)) + "..."
    }
}
