import Foundation
import XCTest
@testable import OpenScribe

final class FixturePipelineTests: XCTestCase {
    private struct FixtureSuite: Codable {
        let version: Int
        let cases: [FixtureCase]
    }

    private struct FixtureCase: Codable {
        let id: String
        let audio: String
        let provider: String
        let model: String
        let language: String
        let tags: [String]
        let rawContains: [String]
        let rawNotContains: [String]

        enum CodingKeys: String, CodingKey {
            case id
            case audio
            case provider
            case model
            case language
            case tags
            case rawContains = "raw_contains"
            case rawNotContains = "raw_not_contains"
        }
    }

    func testFixtureCatalogLoads() throws {
        let suite = try loadFixtureSuite()
        XCTAssertGreaterThanOrEqual(suite.version, 1)
        XCTAssertFalse(suite.cases.isEmpty)

        for item in suite.cases {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.audio.isEmpty)
            XCTAssertFalse(item.provider.isEmpty)
            XCTAssertFalse(item.model.isEmpty)
            XCTAssertFalse(item.language.isEmpty)
            XCTAssertTrue(fileExistsForFixtureAudio(item.audio), "Missing fixture audio: \(item.audio)")
        }
    }

    @MainActor
    func testWhisperCppFixtureCases() async throws {
        guard ProcessInfo.processInfo.environment["RUN_AUDIO_FIXTURE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_AUDIO_FIXTURE_TESTS=1 to run offline whisper fixture integration tests.")
        }

        let suite = try loadFixtureSuite()
        let whisperCases = suite.cases.filter { $0.provider == "whispercpp" }
        guard !whisperCases.isEmpty else {
            throw XCTSkip("No whispercpp fixture cases configured.")
        }

        guard let binaryURL = resolveWhisperBinary() else {
            throw XCTSkip("whisper.cpp binary not found in standard locations.")
        }

        let layout = try DirectoryLayout.resolve()
        let modelManager = ModelDownloadManager(layout: layout)

        let requiredModels = Set(whisperCases.map(\.model))
        let missingModels = requiredModels.filter { !modelManager.isInstalled(modelID: $0) }
        if !missingModels.isEmpty {
            throw XCTSkip("Missing local model(s): \(missingModels.sorted().joined(separator: ", ")).")
        }

        let provider = WhisperCppProvider(binaryURL: binaryURL, modelManager: modelManager)

        for fixtureCase in whisperCases {
            let audioURL = try fixtureAudioURL(named: fixtureCase.audio)
            let result = try await provider.transcribe(
                audioFileURL: audioURL,
                language: fixtureCase.language,
                model: fixtureCase.model
            )

            let normalized = normalizeForAssertions(result.text)
            XCTAssertFalse(normalized.isEmpty, "Case \(fixtureCase.id): transcript should not be empty")

            for expected in fixtureCase.rawContains {
                let expectedNormalized = normalizeForAssertions(expected)
                XCTAssertTrue(
                    normalized.contains(expectedNormalized),
                    "Case \(fixtureCase.id): expected to contain '\(expected)'. Transcript: \(result.text)"
                )
            }

            for forbidden in fixtureCase.rawNotContains {
                let forbiddenNormalized = normalizeForAssertions(forbidden)
                XCTAssertFalse(
                    normalized.contains(forbiddenNormalized),
                    "Case \(fixtureCase.id): expected to NOT contain '\(forbidden)'. Transcript: \(result.text)"
                )
            }
        }
    }

    @MainActor
    func testWhisperCppAcceptsM4AInput() async throws {
        guard ProcessInfo.processInfo.environment["RUN_AUDIO_FIXTURE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_AUDIO_FIXTURE_TESTS=1 to run offline whisper fixture integration tests.")
        }

        guard let binaryURL = resolveWhisperBinary() else {
            throw XCTSkip("whisper.cpp binary not found in standard locations.")
        }

        let layout = try DirectoryLayout.resolve()
        let modelManager = ModelDownloadManager(layout: layout)
        guard modelManager.isInstalled(modelID: "base") else {
            throw XCTSkip("Missing local model: base.")
        }

        let sourceWAV = try fixtureAudioURL(named: "basic_en_smoke.wav")
        let tempM4A = FileManager.default.temporaryDirectory
            .appendingPathComponent("openscribe-m4a-fixture-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: tempM4A) }

        try AudioTranscoder.transcodeToM4A(sourceWAVURL: sourceWAV, destinationURL: tempM4A)

        let provider = WhisperCppProvider(binaryURL: binaryURL, modelManager: modelManager)
        let result = try await provider.transcribe(audioFileURL: tempM4A, language: "auto", model: "base")
        let normalized = normalizeForAssertions(result.text)
        XCTAssertFalse(normalized.isEmpty, "m4a transcription should not be empty")
        XCTAssertTrue(normalized.contains("open scribe"), "Expected m4a transcript to include 'open scribe'. Transcript: \(result.text)")
    }

    private func loadFixtureSuite() throws -> FixtureSuite {
        let url = try fixtureJSONURL()
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FixtureSuite.self, from: data)
    }

    private func fixtureJSONURL() throws -> URL {
        let url =
            Bundle.module.url(forResource: "cases", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "cases", withExtension: "json")

        guard let url else {
            throw NSError(domain: "FixturePipelineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixtures cases.json"])
        }
        return url
    }

    private func fixtureAudioURL(named fileName: String) throws -> URL {
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let url =
            Bundle.module.url(forResource: baseName, withExtension: "wav", subdirectory: "Fixtures/audio")
            ?? Bundle.module.url(forResource: baseName, withExtension: "wav", subdirectory: "audio")
            ?? Bundle.module.url(forResource: baseName, withExtension: "wav")

        guard let url else {
            throw NSError(domain: "FixturePipelineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing fixture audio \(fileName)"])
        }
        return url
    }

    private func fileExistsForFixtureAudio(_ fileName: String) -> Bool {
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return
            Bundle.module.url(forResource: baseName, withExtension: "wav", subdirectory: "Fixtures/audio") != nil
            || Bundle.module.url(forResource: baseName, withExtension: "wav", subdirectory: "audio") != nil
            || Bundle.module.url(forResource: baseName, withExtension: "wav") != nil
    }

    private func resolveWhisperBinary() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp"
        ]

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func normalizeForAssertions(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Za-z])([0-9])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([0-9])([A-Za-z])", with: "$1 $2", options: .regularExpression)

        normalized = normalized.lowercased()
        let components = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return components
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
