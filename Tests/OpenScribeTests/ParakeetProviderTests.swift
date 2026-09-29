import XCTest
@testable import OpenScribe

final class ParakeetProviderTests: XCTestCase {
    func testLanguageHintLeavesAutoDetectionToParakeet() {
        XCTAssertNil(ParakeetEngine.languageHint(for: nil))
        XCTAssertNil(ParakeetEngine.languageHint(for: "auto"))
    }

    func testLanguageHintMapsSupportedLanguageCodes() {
        XCTAssertEqual(ParakeetEngine.languageHint(for: "de"), .german)
        XCTAssertEqual(ParakeetEngine.languageHint(for: "EN"), .english)
    }

    func testDefaultSettingsUseParakeetUltra() {
        XCTAssertEqual(AppSettings.default.transcriptionProviderID, "parakeet")
        XCTAssertEqual(AppSettings.default.transcriptionModel, ModelDownloadManager.parakeetUltraModelID)
        XCTAssertTrue(ProviderModelCatalog.isLocalTranscriptionProvider("parakeet"))
        XCTAssertTrue(ProviderModelCatalog.isLocalTranscriptionProvider("whispercpp"))
        XCTAssertFalse(ProviderModelCatalog.isLocalTranscriptionProvider("groq_whisper"))
    }
}
