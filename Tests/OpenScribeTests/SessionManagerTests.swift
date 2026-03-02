import Foundation
import XCTest
@testable import OpenScribe

final class SessionManagerTests: XCTestCase {
    func testStartSessionCreatesSessionArtifacts() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        let session = try manager.startSession(settings: .default, inputDeviceName: "Test Mic")

        XCTAssertTrue(FileManager.default.fileExists(atPath: session.paths.folderURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.paths.metadataURL.path))
        XCTAssertEqual(session.paths.audioURL.lastPathComponent, "audio.m4a")
        XCTAssertEqual(session.paths.audioTempURL.lastPathComponent, "audio.capture.wav.part")

        let metadataData = try Data(contentsOf: session.paths.metadataURL)
        let metadata = try JSONDecoder.iso8601.decode(SessionMetadata.self, from: metadataData)
        XCTAssertEqual(metadata.state, .recording)
        XCTAssertEqual(metadata.inputDeviceName, "Test Mic")
    }

    func testFinalizeAudioMovesPartFileAtomically() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)
        var session = try manager.startSession(settings: .default, inputDeviceName: nil)

        let sourceWAV = try fixtureWAVURL()
        try FileManager.default.copyItem(at: sourceWAV, to: session.paths.audioTempURL)
        try manager.finalizeAudioFile(&session)

        XCTAssertFalse(FileManager.default.fileExists(atPath: session.paths.audioTempURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.paths.audioURL.path))
        XCTAssertEqual(session.paths.audioURL.pathExtension.lowercased(), "m4a")
    }

    func testStateTransitionPersistsToMetadata() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)
        var session = try manager.startSession(settings: .default, inputDeviceName: nil)

        try manager.transition(&session, to: .transcribing, details: "Test transition")

        let metadataData = try Data(contentsOf: session.paths.metadataURL)
        let metadata = try JSONDecoder.iso8601.decode(SessionMetadata.self, from: metadataData)

        XCTAssertEqual(metadata.state, .transcribing)
        XCTAssertTrue(metadata.stateTransitions.contains(where: { $0.state == .transcribing }))
    }

    func testLoadLatestPolishedTranscriptReturnsNewestNonEmptyValue() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        var old = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writePolished("older polished text", for: &old)

        Thread.sleep(forTimeInterval: 1.1)

        var newer = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writePolished("newest polished text", for: &newer)

        XCTAssertEqual(manager.loadLatestPolishedTranscript(), "newest polished text")
    }

    func testLoadSessionHistoryReturnsNewestFirstAndRespectsLimit() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        var oldest = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writeRaw("oldest raw", for: &oldest)
        try manager.writePolished("oldest polished", for: &oldest)
        try manager.transition(&oldest, to: .completed, details: "oldest complete")

        Thread.sleep(forTimeInterval: 1.1)

        var middle = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writeRaw("middle raw", for: &middle)
        try manager.writePolished("middle polished", for: &middle)
        try manager.transition(&middle, to: .completed, details: "middle complete")

        Thread.sleep(forTimeInterval: 1.1)

        var newest = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writeRaw("newest raw", for: &newest)
        try manager.writePolished("newest polished", for: &newest)
        try manager.transition(&newest, to: .completed, details: "newest complete")

        let history = manager.loadSessionHistory(limit: 2)

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].id, newest.id)
        XCTAssertEqual(history[1].id, middle.id)
    }

    func testLoadSessionHistoryPreviewFallsBackToRawText() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        var session = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writeRaw("raw only transcript preview", for: &session)

        let history = manager.loadSessionHistory(limit: 10)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].previewText, "raw only transcript preview")
    }

    func testLoadSessionHistoryPreviewPrefersPolishedText() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        var session = try manager.startSession(settings: .default, inputDeviceName: nil)
        try manager.writeRaw("raw transcript", for: &session)
        try manager.writePolished("polished transcript", for: &session)

        let history = manager.loadSessionHistory(limit: 10)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].previewText, "polished transcript")
    }

    func testLoadSessionHistoryPageReportsHasMoreWhenLimitIsLowerThanTotal() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        _ = try manager.startSession(settings: .default, inputDeviceName: nil)
        Thread.sleep(forTimeInterval: 1.1)
        _ = try manager.startSession(settings: .default, inputDeviceName: nil)

        let page = manager.loadSessionHistoryPage(limit: 1)

        XCTAssertEqual(page.entries.count, 1)
        XCTAssertTrue(page.hasMore)
    }

    func testLoadSessionHistoryPageWithIntMaxLoadsWholeHistory() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        _ = try manager.startSession(settings: .default, inputDeviceName: nil)
        Thread.sleep(forTimeInterval: 1.1)
        _ = try manager.startSession(settings: .default, inputDeviceName: nil)

        let page = manager.loadSessionHistoryPage(limit: Int.max)

        XCTAssertEqual(page.entries.count, 2)
        XCTAssertFalse(page.hasMore)
    }

    func testLoadSessionContextReturnsPersistedMetadataAndPaths() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        var session = try manager.startSession(settings: .default, inputDeviceName: "Mic X")
        try manager.writeRaw("hello raw", for: &session)
        try manager.writePolished("hello polished", for: &session)
        try manager.transition(&session, to: .completed, details: "done")

        let loaded = manager.loadSessionContext(folderURL: session.paths.folderURL)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, session.id)
        XCTAssertEqual(loaded?.metadata.inputDeviceName, "Mic X")
        XCTAssertEqual(loaded?.metadata.state, .completed)
        XCTAssertEqual(loaded?.paths.audioURL.lastPathComponent, "audio.m4a")
        XCTAssertEqual(loaded?.paths.rawURL.lastPathComponent, "raw.txt")
        XCTAssertEqual(loaded?.paths.polishedURL.lastPathComponent, "polished.md")
    }

    func testLoadSessionContextReturnsNilWhenMetadataIsMissing() throws {
        let layout = try makeTempLayout()
        let manager = SessionManager(layout: layout)

        let missing = layout.recordings
            .appendingPathComponent("2026-03-02", isDirectory: true)
            .appendingPathComponent("120000-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)

        XCTAssertNil(manager.loadSessionContext(folderURL: missing))
    }

    private func makeTempLayout() throws -> DirectoryLayout {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OpenScribeTests-\(UUID().uuidString)", isDirectory: true)

        let layout = DirectoryLayout(
            appSupport: root,
            recordings: root.appendingPathComponent("Recordings", isDirectory: true),
            rules: root.appendingPathComponent("Rules", isDirectory: true),
            models: root.appendingPathComponent("Models/whisper", isDirectory: true),
            config: root.appendingPathComponent("Config", isDirectory: true),
            rulesFile: root.appendingPathComponent("Rules/rules.md"),
            rulesHistory: root.appendingPathComponent("Rules/rules.history.jsonl"),
            settingsFile: root.appendingPathComponent("Config/settings.json")
        )

        try layout.ensureExists()
        return layout
    }

    private func fixtureWAVURL() throws -> URL {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "basic_en_smoke", withExtension: "wav", subdirectory: "Fixtures/audio"),
            Bundle.module.url(forResource: "basic_en_smoke", withExtension: "wav", subdirectory: "audio"),
            Bundle.module.url(forResource: "basic_en_smoke", withExtension: "wav")
        ]

        for candidate in candidates {
            if let candidate {
                return candidate
            }
        }

        throw NSError(
            domain: "SessionManagerTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Missing fixture wav for finalize test."]
        )
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
