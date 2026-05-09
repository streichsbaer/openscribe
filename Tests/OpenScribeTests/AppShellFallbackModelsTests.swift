import XCTest
@testable import OpenScribe

final class AppShellFallbackModelsTests: XCTestCase {
    func testGroqPolishFallbackModelsPreferPreferredModel() {
        let models = AppShell.fallbackModels(for: "groq_polish", usage: .polish)

        XCTAssertEqual(models.first, "openai/gpt-oss-120b")
        XCTAssertTrue(models.contains("llama-3.3-70b-versatile"))
        XCTAssertTrue(models.contains("mixtral-8x7b-32768"))
    }

    func testGroqPolishFetchedCatalogStillPrefersPreferredModel() {
        let models = [
            "allam-2-7b",
            "groq/compound",
            "llama-3.3-70b-versatile",
            "openai/gpt-oss-120b"
        ]

        let ordered = AppShell.prioritizeRecommendedModel(
            models,
            providerID: "groq_polish",
            usage: .polish
        )

        XCTAssertEqual(ordered.first, "openai/gpt-oss-120b")
        XCTAssertEqual(
            Array(ordered.dropFirst()),
            ["allam-2-7b", "groq/compound", "llama-3.3-70b-versatile"]
        )
    }

    func testCerebrasPolishFallbackModelsPreferRecommendedModel() {
        let models = AppShell.fallbackModels(for: "cerebras_polish", usage: .polish)

        XCTAssertEqual(models, ["gpt-oss-120b"])
    }

    func testCerebrasPolishFetchedCatalogStillPrefersRecommendedModel() {
        let models = [
            "llama3.1-8b",
            "gpt-oss-120b",
            "qwen-3-32b"
        ]

        let ordered = AppShell.prioritizeRecommendedModel(
            models,
            providerID: "cerebras_polish",
            usage: .polish
        )

        XCTAssertEqual(ordered.first, "gpt-oss-120b")
        XCTAssertEqual(Array(ordered.dropFirst()), ["llama3.1-8b", "qwen-3-32b"])
    }

    func testOpenAIRealtimeFallbackUsesRealtimeWhisper() {
        let models = AppShell.fallbackModels(for: "openai_realtime_transcription", usage: .transcription)

        XCTAssertEqual(models, ["gpt-realtime-whisper"])
    }

    func testOpenAITranscriptionFiltersRealtimeModelsOutOfFileUploadProvider() {
        let models = [
            "gpt-4o-mini-transcribe",
            "gpt-realtime-whisper",
            "whisper-1"
        ]

        let filtered = AppShell.filterModels(
            models,
            providerID: "openai_whisper",
            backend: .openai,
            usage: .transcription
        )

        XCTAssertEqual(filtered, ["gpt-4o-mini-transcribe", "whisper-1"])
    }

    func testOpenAIRealtimeTranscriptionOnlyIncludesRealtimeWhisperModels() {
        let models = [
            "gpt-4o-mini-transcribe",
            "gpt-realtime-voice",
            "gpt-realtime-whisper",
            "whisper-1"
        ]

        let filtered = AppShell.filterModels(
            models,
            providerID: "openai_realtime_transcription",
            backend: .openai,
            usage: .transcription
        )

        XCTAssertEqual(filtered, ["gpt-realtime-whisper"])
    }

    func testRealtimeProviderUses24kCaptureRate() {
        var settings = AppSettings.default
        settings.transcriptionProviderID = "openai_realtime_transcription"
        settings.transcriptionModel = "gpt-realtime-whisper"

        XCTAssertEqual(AppShell.captureSampleRate(for: settings), 24_000)
    }

    func testDefaultProviderUses16kCaptureRate() {
        XCTAssertEqual(AppShell.captureSampleRate(for: .default), 16_000)
    }
}
