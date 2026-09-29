import XCTest
@testable import OpenScribe

final class SetupAssistantChecklistTests: XCTestCase {
    func testGroqSetupCompletesWhenEveryRequirementMatches() {
        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: true,
            autoPasteEnabled: true,
            hasSuccessfulRecording: true,
            latestOutputAvailable: true,
            testFieldContainsOutput: true,
            groqKeySaved: true,
            groqVerified: true,
            transcriptionProviderID: SetupAssistantChecklist.groqTranscriptionProviderID,
            transcriptionModel: SetupAssistantChecklist.groqTranscriptionModel,
            polishEnabled: true,
            polishProviderID: SetupAssistantChecklist.groqPolishProviderID,
            polishModel: SetupAssistantChecklist.groqPolishModel,
            languageMode: "auto",
            selectedLocalModel: SetupAssistantChecklist.defaultLocalModelID,
            localModelInstalled: false
        )

        XCTAssertTrue(SetupAssistantChecklist.isComplete(for: .groq, context: context))
        XCTAssertEqual(SetupAssistantChecklist.items(for: .groq, context: context).count, 7)
    }

    func testGroqSetupStaysIncompleteWithoutVerifiedGroqKey() {
        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: true,
            autoPasteEnabled: true,
            hasSuccessfulRecording: false,
            latestOutputAvailable: false,
            testFieldContainsOutput: false,
            groqKeySaved: true,
            groqVerified: false,
            transcriptionProviderID: SetupAssistantChecklist.groqTranscriptionProviderID,
            transcriptionModel: SetupAssistantChecklist.groqTranscriptionModel,
            polishEnabled: true,
            polishProviderID: SetupAssistantChecklist.groqPolishProviderID,
            polishModel: SetupAssistantChecklist.groqPolishModel,
            languageMode: "auto",
            selectedLocalModel: SetupAssistantChecklist.defaultLocalModelID,
            localModelInstalled: false
        )

        let items = SetupAssistantChecklist.items(for: .groq, context: context)

        XCTAssertFalse(SetupAssistantChecklist.isComplete(for: .groq, context: context))
        XCTAssertFalse(items.contains(where: { $0.id == "groq.keyVerified" && $0.isComplete }))
    }

    func testGroqSetupUsesApprovedChecklistOrder() {
        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: false,
            autoPasteEnabled: false,
            hasSuccessfulRecording: false,
            latestOutputAvailable: false,
            testFieldContainsOutput: false,
            groqKeySaved: false,
            groqVerified: false,
            transcriptionProviderID: "",
            transcriptionModel: "",
            polishEnabled: false,
            polishProviderID: "",
            polishModel: "",
            languageMode: "",
            selectedLocalModel: SetupAssistantChecklist.defaultLocalModelID,
            localModelInstalled: false
        )

        let ids = SetupAssistantChecklist.items(for: .groq, context: context).map(\.id)

        XCTAssertEqual(
            ids,
            [
                "groq.keySaved",
                "groq.keyVerified",
                "groq.setup",
                "groq.accessibility",
                "groq.autopaste",
                "groq.recording",
                "groq.pasteTest"
            ]
        )
    }

    func testLocalSetupCompletesWhenSelectedModelIsInstalledAndRecordingSucceeded() {
        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: true,
            autoPasteEnabled: true,
            hasSuccessfulRecording: true,
            latestOutputAvailable: true,
            testFieldContainsOutput: true,
            groqKeySaved: false,
            groqVerified: false,
            transcriptionProviderID: "whispercpp",
            transcriptionModel: "small",
            polishEnabled: false,
            polishProviderID: "openai_polish",
            polishModel: "gpt-5-nano",
            languageMode: "auto",
            selectedLocalModel: "small",
            localModelInstalled: true
        )

        XCTAssertTrue(SetupAssistantChecklist.isComplete(for: .local, context: context))
        XCTAssertEqual(SetupAssistantChecklist.items(for: .local, context: context).count, 6)
    }

    func testLocalSetupDefaultsToParakeetUltra() {
        let option = SetupAssistantChecklist.localOption(for: SetupAssistantChecklist.defaultLocalModelID)
        XCTAssertEqual(option.id, ModelDownloadManager.parakeetUltraModelID)
        XCTAssertEqual(option.providerID, "parakeet")

        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: true,
            autoPasteEnabled: true,
            hasSuccessfulRecording: true,
            latestOutputAvailable: true,
            testFieldContainsOutput: true,
            groqKeySaved: false,
            groqVerified: false,
            transcriptionProviderID: "parakeet",
            transcriptionModel: ModelDownloadManager.parakeetUltraModelID,
            polishEnabled: false,
            polishProviderID: "openai_polish",
            polishModel: "gpt-5-nano",
            languageMode: "auto",
            selectedLocalModel: ModelDownloadManager.parakeetUltraModelID,
            localModelInstalled: true
        )

        XCTAssertTrue(SetupAssistantChecklist.isComplete(for: .local, context: context))
    }

    func testLocalSetupRequiresTheProviderThatOwnsTheSelectedModel() {
        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: true,
            autoPasteEnabled: true,
            hasSuccessfulRecording: true,
            latestOutputAvailable: true,
            testFieldContainsOutput: true,
            groqKeySaved: false,
            groqVerified: false,
            transcriptionProviderID: "whispercpp",
            transcriptionModel: ModelDownloadManager.parakeetUltraModelID,
            polishEnabled: false,
            polishProviderID: "openai_polish",
            polishModel: "gpt-5-nano",
            languageMode: "auto",
            selectedLocalModel: ModelDownloadManager.parakeetUltraModelID,
            localModelInstalled: true
        )

        XCTAssertFalse(SetupAssistantChecklist.localSetupMatches(context))
        XCTAssertFalse(SetupAssistantChecklist.isComplete(for: .local, context: context))
        XCTAssertTrue(
            SetupAssistantChecklist.sessionMatchesTrack(
                sttProvider: "parakeet",
                sttModel: ModelDownloadManager.parakeetUltraModelID,
                polishProvider: "disabled",
                polishModel: "passthrough",
                track: .local,
                selectedLocalModel: ModelDownloadManager.parakeetUltraModelID
            )
        )
    }

    func testLocalSetupRequiresAccessibilityAndAutoPasteForCompletion() {
        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: false,
            autoPasteEnabled: false,
            hasSuccessfulRecording: true,
            latestOutputAvailable: true,
            testFieldContainsOutput: false,
            groqKeySaved: false,
            groqVerified: false,
            transcriptionProviderID: "whispercpp",
            transcriptionModel: "small",
            polishEnabled: false,
            polishProviderID: "openai_polish",
            polishModel: "gpt-5-nano",
            languageMode: "auto",
            selectedLocalModel: "small",
            localModelInstalled: true
        )

        let items = SetupAssistantChecklist.items(for: .local, context: context)

        XCTAssertFalse(SetupAssistantChecklist.isComplete(for: .local, context: context))
        XCTAssertFalse(items.contains(where: { $0.id == "local.accessibility" && $0.isComplete }))
        XCTAssertFalse(items.contains(where: { $0.id == "local.autopaste" && $0.isComplete }))
        XCTAssertFalse(items.contains(where: { $0.id == "local.pasteTest" && $0.isComplete }))
    }

    func testLocalSetupUsesApprovedChecklistOrder() {
        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: false,
            autoPasteEnabled: false,
            hasSuccessfulRecording: false,
            latestOutputAvailable: false,
            testFieldContainsOutput: false,
            groqKeySaved: false,
            groqVerified: false,
            transcriptionProviderID: "",
            transcriptionModel: "",
            polishEnabled: false,
            polishProviderID: "",
            polishModel: "",
            languageMode: "",
            selectedLocalModel: "small",
            localModelInstalled: false
        )

        let ids = SetupAssistantChecklist.items(for: .local, context: context).map(\.id)

        XCTAssertEqual(
            ids,
            [
                "local.setup",
                "local.model",
                "local.accessibility",
                "local.autopaste",
                "local.recording",
                "local.pasteTest"
            ]
        )
    }

    func testAutoPresentOnlyTriggersBeforeAnySessionHistoryOrPermanentDismissal() {
        XCTAssertTrue(
            SetupAssistantChecklist.shouldAutoPresent(
                hasSessionHistory: false,
                doNotShowAgain: false
            )
        )
        XCTAssertFalse(
            SetupAssistantChecklist.shouldAutoPresent(
                hasSessionHistory: true,
                doNotShowAgain: false
            )
        )
        XCTAssertFalse(
            SetupAssistantChecklist.shouldAutoPresent(
                hasSessionHistory: false,
                doNotShowAgain: true
            )
        )
    }

    func testGroqTrackMatchingRejectsLocalOnlySession() {
        XCTAssertFalse(
            SetupAssistantChecklist.sessionMatchesTrack(
                sttProvider: "whispercpp",
                sttModel: "small",
                polishProvider: "disabled",
                polishModel: "passthrough",
                track: .groq,
                selectedLocalModel: "small"
            )
        )
    }

    func testLocalTrackMatchingRejectsGroqSession() {
        XCTAssertFalse(
            SetupAssistantChecklist.sessionMatchesTrack(
                sttProvider: SetupAssistantChecklist.groqTranscriptionProviderID,
                sttModel: SetupAssistantChecklist.groqTranscriptionModel,
                polishProvider: SetupAssistantChecklist.groqPolishProviderID,
                polishModel: SetupAssistantChecklist.groqPolishModel,
                track: .local,
                selectedLocalModel: "small"
            )
        )
    }

    func testAppleSiliconRecommendsLocalTrackFirst() {
        let recommended = SetupAssistantTrack.recommended(onAppleSilicon: true)

        XCTAssertEqual(recommended, .local)
        XCTAssertEqual(SetupAssistantTrack.ordered(recommended: recommended), [.local, .groq])
        XCTAssertTrue(SetupAssistantTrack.recommendationNote(onAppleSilicon: true).contains("Local only"))
    }

    func testIntelRecommendsGroqTrackFirst() {
        let recommended = SetupAssistantTrack.recommended(onAppleSilicon: false)

        XCTAssertEqual(recommended, .groq)
        XCTAssertEqual(SetupAssistantTrack.ordered(recommended: recommended), [.groq, .local])
        XCTAssertTrue(SetupAssistantTrack.recommendationNote(onAppleSilicon: false).contains("Groq cloud"))
    }

    func testRecommendedLocalModelIsParakeetUltra() {
        XCTAssertEqual(SetupAssistantChecklist.defaultLocalModelID, ModelDownloadManager.parakeetUltraModelID)
        XCTAssertEqual(SetupAssistantChecklist.localOption(for: SetupAssistantChecklist.defaultLocalModelID).providerID, "parakeet")
    }
}
