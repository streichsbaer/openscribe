import Foundation
import XCTest
@testable import OpenScribe

@MainActor
final class RetryTranscriptionFailureStateResetTests: XCTestCase {
    func testApplyClearsPolishedStateAndPersistsBlankWhenFreshRawWasWritten() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        var previousSession = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writePolished("previous polished value", for: &previousSession)
        try manager.transition(&previousSession, to: .completed, details: "previous complete")

        Thread.sleep(forTimeInterval: 1.1)

        var currentSession = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writePolished("stale polished value", for: &currentSession)

        var polishedTranscript = "stale polished value"
        var polishedProviderID = "openai_polish"
        var polishedModel = "gpt-5-nano"
        var latestPolished = "stale polished value"

        RetryTranscriptionFailureStateReset.apply(
            didWriteFreshRawTranscript: true,
            polishEnabled: true,
            session: &currentSession,
            sessionManager: manager,
            polishedTranscript: &polishedTranscript,
            polishedTranscriptProviderID: &polishedProviderID,
            polishedTranscriptModel: &polishedModel,
            latestPolishedTranscript: &latestPolished
        )

        XCTAssertEqual(polishedTranscript, "")
        XCTAssertEqual(polishedProviderID, "")
        XCTAssertEqual(polishedModel, "")

        let persistedPolished = try String(contentsOf: currentSession.paths.polishedURL, encoding: .utf8)
        XCTAssertEqual(persistedPolished, "")

        XCTAssertEqual(latestPolished, "previous polished value")
    }

    func testApplyNoOpsWhenFreshRawWasNotWritten() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        var session = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writePolished("existing polished value", for: &session)

        var polishedTranscript = "existing polished value"
        var polishedProviderID = "openai_polish"
        var polishedModel = "gpt-5-nano"
        var latestPolished = "existing polished value"

        RetryTranscriptionFailureStateReset.apply(
            didWriteFreshRawTranscript: false,
            polishEnabled: true,
            session: &session,
            sessionManager: manager,
            polishedTranscript: &polishedTranscript,
            polishedTranscriptProviderID: &polishedProviderID,
            polishedTranscriptModel: &polishedModel,
            latestPolishedTranscript: &latestPolished
        )

        XCTAssertEqual(polishedTranscript, "existing polished value")
        XCTAssertEqual(polishedProviderID, "openai_polish")
        XCTAssertEqual(polishedModel, "gpt-5-nano")
        XCTAssertEqual(latestPolished, "existing polished value")

        let persistedPolished = try String(contentsOf: session.paths.polishedURL, encoding: .utf8)
        XCTAssertEqual(persistedPolished, "existing polished value")
    }

    private func makeTempLayout() throws -> DirectoryLayout {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OpenScribeRetryResetTests-\(UUID().uuidString)", isDirectory: true)

        let layout = DirectoryLayout(
            appSupport: root,
            recordings: root.appendingPathComponent("Recordings", isDirectory: true),
            rules: root.appendingPathComponent("Rules", isDirectory: true),
            stats: root.appendingPathComponent("Stats", isDirectory: true),
            models: root.appendingPathComponent("Models/whisper", isDirectory: true),
            config: root.appendingPathComponent("Config", isDirectory: true),
            rulesFile: root.appendingPathComponent("Rules/rules.md"),
            rulesHistory: root.appendingPathComponent("Rules/rules.history.jsonl"),
            statsEventsFile: root.appendingPathComponent("Stats/usage.events.jsonl"),
            settingsFile: root.appendingPathComponent("Config/settings.json")
        )

        try layout.ensureExists()
        return layout
    }
}
