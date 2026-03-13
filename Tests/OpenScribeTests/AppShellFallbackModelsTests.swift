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
}
