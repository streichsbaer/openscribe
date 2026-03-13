import XCTest
@testable import OpenScribe

final class APIKeyResolverTests: XCTestCase {
    private var keychain: KeychainStore!
    private var serviceName: String!

    override func setUp() {
        super.setUp()
        serviceName = "OpenScribeTests.APIKeyResolver.\(UUID().uuidString)"
        keychain = KeychainStore(service: serviceName)
    }

    override func tearDown() {
        for entry in [KeychainEntry.openAI, .groq, .openRouter, .gemini, .cerebras] {
            keychain.delete(entry)
        }
        keychain = nil
        serviceName = nil
        super.tearDown()
    }

    func testResolveReturnsMissingWhenKeychainHasNoValue() {
        let resolver = APIKeyResolver(keychain: keychain)

        let resolution = resolver.resolve(.openAI)

        XCTAssertNil(resolution.value)
        XCTAssertEqual(resolution.source, .missing)
        XCTAssertFalse(resolution.keychainPresent)
    }

    func testResolveReturnsSavedKeyFromKeychain() throws {
        try keychain.save("test-key", for: .openAI)
        let resolver = APIKeyResolver(keychain: keychain)

        let resolution = resolver.resolve(.openAI)

        XCTAssertEqual(resolution.value, "test-key")
        XCTAssertEqual(resolution.source, .keychain)
        XCTAssertTrue(resolution.keychainPresent)
    }
}
