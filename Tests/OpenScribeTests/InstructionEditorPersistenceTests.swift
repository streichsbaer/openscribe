import XCTest
@testable import OpenScribe

final class InstructionEditorPersistenceTests: XCTestCase {
    func testDonePersistsTranscriptionWhenChanged() {
        let change = InstructionEditorPersistence.changeOnDone(
            target: .transcription,
            transcriptionDraft: "  custom stt  ",
            storedTranscription: nil,
            polishDraft: "",
            storedPolish: nil
        )

        XCTAssertEqual(change, .setTranscription("custom stt"))
    }

    func testDonePersistsPolishWhenChanged() {
        let change = InstructionEditorPersistence.changeOnDone(
            target: .polish,
            transcriptionDraft: "",
            storedTranscription: nil,
            polishDraft: "  custom polish  ",
            storedPolish: nil
        )

        XCTAssertEqual(change, .setPolish("custom polish"))
    }

    func testDoneNoChangeWhenNormalizedValueMatchesStored() {
        let change = InstructionEditorPersistence.changeOnDone(
            target: .polish,
            transcriptionDraft: "",
            storedTranscription: nil,
            polishDraft: "  saved  ",
            storedPolish: "saved"
        )

        XCTAssertEqual(change, .none)
    }

    func testFocusLossPersistsTranscription() {
        let changes = InstructionEditorPersistence.changesOnFocusChange(
            from: .transcription,
            to: nil,
            transcriptionDraft: "updated",
            storedTranscription: "before",
            polishDraft: "",
            storedPolish: nil
        )

        XCTAssertEqual(changes, [.setTranscription("updated")])
    }

    func testFocusLossPersistsPolishWhenSwitchingToOtherEditor() {
        let changes = InstructionEditorPersistence.changesOnFocusChange(
            from: .polish,
            to: .transcription,
            transcriptionDraft: "",
            storedTranscription: nil,
            polishDraft: "updated polish",
            storedPolish: "before polish"
        )

        XCTAssertEqual(changes, [.setPolish("updated polish")])
    }

    func testFocusUnchangedDoesNotPersistWhileTyping() {
        let changes = InstructionEditorPersistence.changesOnFocusChange(
            from: .polish,
            to: .polish,
            transcriptionDraft: "",
            storedTranscription: nil,
            polishDraft: "typing only",
            storedPolish: nil
        )

        XCTAssertTrue(changes.isEmpty)
    }
}
