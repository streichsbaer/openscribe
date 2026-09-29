import Foundation
import XCTest
@testable import OpenScribe

final class ModelDownloadManagerTests: XCTestCase {
    func testCatalogPinsImmutableRevisionAndExpectedHashes() throws {
        let manager = ModelDownloadManager(layout: try makeTempLayout())
        let expectedWhisperHashes = [
            "tiny": "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
            "base": "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            "small": "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
            "medium": "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208",
            "large-v3-turbo": "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
        ]

        let whisper = manager.catalog.filter { $0.kind == .whisper }
        XCTAssertEqual(Set(whisper.map(\.id)), Set(expectedWhisperHashes.keys))
        for asset in whisper {
            XCTAssertEqual(asset.files.count, 1)
            XCTAssertTrue(
                asset.repositoryURL.absoluteString.hasSuffix("/resolve/\(ModelDownloadManager.modelRepositoryRevision)/"),
                "Model URL must use the pinned repository revision"
            )
            XCTAssertEqual(asset.files[0].sha256, expectedWhisperHashes[asset.id])
            XCTAssertGreaterThan(asset.expectedSizeBytes, 0)
        }
    }

    func testParakeetModelsPinRevisionAndHashEveryFile() throws {
        let manager = ModelDownloadManager(layout: try makeTempLayout())
        let ultra = try XCTUnwrap(manager.asset(for: ModelDownloadManager.parakeetUltraModelID))
        let vocabulary = try XCTUnwrap(manager.asset(for: ModelDownloadManager.parakeetVocabularyModelID))

        XCTAssertEqual(ultra.kind, .parakeet)
        XCTAssertEqual(vocabulary.kind, .parakeetVocabulary)
        XCTAssertTrue(ultra.repositoryURL.absoluteString.hasSuffix("/resolve/\(ParakeetModelFiles.ultraRevision)/"))
        XCTAssertTrue(vocabulary.repositoryURL.absoluteString.hasSuffix("/resolve/\(ParakeetModelFiles.vocabularyBoostRevision)/"))
        XCTAssertEqual(ultra.files.count, 20)
        for file in ultra.files + vocabulary.files {
            XCTAssertEqual(file.sha256.count, 64, file.path)
            XCTAssertGreaterThan(file.sizeBytes, 0, file.path)
        }
        XCTAssertEqual(manager.transcriptionModels(providerID: "parakeet").map(\.id), [ModelDownloadManager.parakeetUltraModelID])
    }

    func testLocalPathsKeepWhisperFilesAndUseFoldersForParakeet() throws {
        let layout = try makeTempLayout()
        let manager = ModelDownloadManager(layout: layout)

        XCTAssertEqual(manager.localPath(for: "base"), layout.whisperModels.appendingPathComponent("ggml-base.bin"))
        XCTAssertEqual(
            manager.localPath(for: ModelDownloadManager.parakeetUltraModelID),
            layout.parakeetModels.appendingPathComponent(ModelDownloadManager.parakeetUltraModelID, isDirectory: true)
        )
    }

    func testValidateRejectsHashMismatch() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("model".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let spec = ModelAssetFile(path: "weights.bin", sizeBytes: 5, sha256: String(repeating: "0", count: 64))

        XCTAssertThrowsError(try ModelDownloadManager.validate(file: spec, modelID: "test", at: file))
    }

    private func makeTempLayout() throws -> DirectoryLayout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenScribeModelTests-\(UUID().uuidString)", isDirectory: true)
        let layout = DirectoryLayout(
            appSupport: root,
            recordings: root.appendingPathComponent("Recordings", isDirectory: true),
            rules: root.appendingPathComponent("Rules", isDirectory: true),
            stats: root.appendingPathComponent("Stats", isDirectory: true),
            models: root.appendingPathComponent("Models", isDirectory: true),
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
