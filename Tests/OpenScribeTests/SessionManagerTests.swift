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
