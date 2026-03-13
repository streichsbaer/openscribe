import XCTest
@testable import OpenScribe

final class KeychainEntryTests: XCTestCase {
    func testProviderDisplayNames() {
        XCTAssertEqual(KeychainEntry.openAI.providerDisplayName, "OpenAI")
        XCTAssertEqual(KeychainEntry.groq.providerDisplayName, "Groq")
        XCTAssertEqual(KeychainEntry.openRouter.providerDisplayName, "OpenRouter")
        XCTAssertEqual(KeychainEntry.gemini.providerDisplayName, "Gemini")
        XCTAssertEqual(KeychainEntry.cerebras.providerDisplayName, "Cerebras")
    }
}
