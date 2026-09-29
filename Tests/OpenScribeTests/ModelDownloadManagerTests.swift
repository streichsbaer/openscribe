import Foundation
import XCTest
@testable import OpenScribe

final class ModelDownloadManagerTests: XCTestCase {
    func testCatalogPinsImmutableRevisionAndExpectedHashes() throws {
        let manager = ModelDownloadManager(layout: try makeTempLayout())
        let expectedHashes = [
            "tiny": "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
            "base": "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            "small": "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
            "medium": "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208",
            "large-v3-turbo": "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
        ]

        XCTAssertEqual(Set(manager.catalog.map(\.id)), Set(expectedHashes.keys))
        for asset in manager.catalog {
            XCTAssertTrue(
                asset.downloadURL.path.contains("/resolve/\(ModelDownloadManager.modelRepositoryRevision)/"),
                "Model URL must use the pinned repository revision"
            )
            XCTAssertEqual(asset.sha256, expectedHashes[asset.id])
            XCTAssertEqual(asset.sha256.count, 64)
            XCTAssertGreaterThan(asset.expectedSizeBytes, 0)
        }
    }

    private func makeTempLayout() throws -> DirectoryLayout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenScribeModelTests-\(UUID().uuidString)", isDirectory: true)
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
