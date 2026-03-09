import XCTest
@testable import OpenScribe

final class SetupAssistantChecklistTests: XCTestCase {
    func testRecommendedSetupCompletesWhenEveryRequirementMatches() {
        let context = SetupAssistantChecklistContext(
            permissionAuthorized: true,
            hasSuccessfulRecording: true,
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
        XCTAssertEqual(SetupAssistantChecklist.items(for: .recommended, context: context).count, 6)
    }

    func testRecommendedSetupStaysIncompleteWithoutVerifiedGroqKey() {
        let context = SetupAssistantChecklistContext(
            permissionAuthorized: true,
            hasSuccessfulRecording: false,
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

    func testLocalSetupCompletesWhenSelectedModelIsInstalledAndRecordingSucceeded() {
        let context = SetupAssistantChecklistContext(
            permissionAuthorized: true,
            hasSuccessfulRecording: true,
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
        XCTAssertEqual(SetupAssistantChecklist.items(for: .local, context: context).count, 4)
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
}
