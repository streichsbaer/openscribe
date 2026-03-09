import XCTest
@testable import OpenScribe

final class SetupAssistantChecklistTests: XCTestCase {
    func testRecommendedSetupCompletesWhenEveryRequirementMatches() {
        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: true,
            autoPasteEnabled: true,
            hasSuccessfulRecording: true,
            latestOutputAvailable: true,
            testFieldContainsOutput: true,
            groqKeySaved: true,
            groqVerified: true,
            transcriptionProviderID: SetupAssistantChecklist.recommendedTranscriptionProviderID,
            transcriptionModel: SetupAssistantChecklist.recommendedTranscriptionModel,
            polishEnabled: true,
            polishProviderID: SetupAssistantChecklist.recommendedPolishProviderID,
            polishModel: SetupAssistantChecklist.recommendedPolishModel,
            languageMode: "auto",
            selectedLocalModel: SetupAssistantChecklist.defaultLocalModelID,
            localModelInstalled: false
        )

        XCTAssertTrue(SetupAssistantChecklist.isComplete(for: .recommended, context: context))
        XCTAssertEqual(SetupAssistantChecklist.items(for: .recommended, context: context).count, 8)
    }

    func testRecommendedSetupStaysIncompleteWithoutVerifiedGroqKey() {
        let context = SetupAssistantChecklistContext(
            accessibilityPermissionGranted: true,
            autoPasteEnabled: true,
            hasSuccessfulRecording: false,
            latestOutputAvailable: false,
            testFieldContainsOutput: false,
            groqKeySaved: true,
            groqVerified: false,
            transcriptionProviderID: SetupAssistantChecklist.recommendedTranscriptionProviderID,
            transcriptionModel: SetupAssistantChecklist.recommendedTranscriptionModel,
            polishEnabled: true,
            polishProviderID: SetupAssistantChecklist.recommendedPolishProviderID,
            polishModel: SetupAssistantChecklist.recommendedPolishModel,
            languageMode: "auto",
            selectedLocalModel: SetupAssistantChecklist.defaultLocalModelID,
            localModelInstalled: false
        )

        let items = SetupAssistantChecklist.items(for: .recommended, context: context)

        XCTAssertFalse(SetupAssistantChecklist.isComplete(for: .recommended, context: context))
        XCTAssertFalse(items.contains(where: { $0.id == "recommended.keyVerified" && $0.isComplete }))
    }

    func testRecommendedSetupUsesApprovedChecklistOrder() {
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

        let ids = SetupAssistantChecklist.items(for: .recommended, context: context).map(\.id)

        XCTAssertEqual(
            ids,
            [
                "recommended.keySaved",
                "recommended.keyVerified",
                "recommended.transcribe",
                "recommended.polish",
                "recommended.accessibility",
                "recommended.autopaste",
                "recommended.recording",
                "recommended.pasteTest"
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

    func testRecommendedTrackMatchingRejectsLocalOnlySession() {
        XCTAssertFalse(
            SetupAssistantChecklist.sessionMatchesTrack(
                sttProvider: "whispercpp",
                sttModel: "small",
                polishProvider: "disabled",
                polishModel: "passthrough",
                track: .recommended,
                selectedLocalModel: "small"
            )
        )
    }

    func testLocalTrackMatchingRejectsRecommendedSession() {
        XCTAssertFalse(
            SetupAssistantChecklist.sessionMatchesTrack(
                sttProvider: SetupAssistantChecklist.recommendedTranscriptionProviderID,
                sttModel: SetupAssistantChecklist.recommendedTranscriptionModel,
                polishProvider: SetupAssistantChecklist.recommendedPolishProviderID,
                polishModel: SetupAssistantChecklist.recommendedPolishModel,
                track: .local,
                selectedLocalModel: "small"
            )
        )
    }
}
