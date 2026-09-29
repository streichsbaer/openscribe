import XCTest
@testable import OpenScribe

final class VocabularyStoreTests: XCTestCase {
    func testParserReadsTermsAliasesAndSkipsCommentsAndEmptyTerms() {
        let entries = VocabularyParser.parse("""
        # comment
        gitignore: git ignore, get ignore
          mise :  meez
        Kubernetes

        : missing term
        """)

        XCTAssertEqual(entries, [
            VocabularyEntry(term: "gitignore", aliases: ["git ignore", "get ignore"]),
            VocabularyEntry(term: "mise", aliases: ["meez"]),
            VocabularyEntry(term: "Kubernetes", aliases: [])
        ])
    }

    func testUserEntriesComeFirstAndReplaceBuiltInTerms() {
        let merged = VocabularyParser.merge(
            user: [VocabularyEntry(term: "MISE", aliases: ["mees"])],
            builtIn: [
                VocabularyEntry(term: "gitignore", aliases: []),
                VocabularyEntry(term: "mise", aliases: ["meez"])
            ]
        )

        XCTAssertEqual(merged, [
            VocabularyEntry(term: "MISE", aliases: ["mees"]),
            VocabularyEntry(term: "gitignore", aliases: [])
        ])
    }

    func testStoreCreatesTemplateAndSavesUserEntries() throws {
        let layout = try makeTempLayout()
        let store = VocabularyStore(layout: layout, builtInText: "worktree: work tree")

        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.vocabularyFile.path))
        XCTAssertTrue(store.userEntries.isEmpty)
        XCTAssertEqual(store.entries(includeBuiltIn: true).map(\.term), ["worktree"])

        try store.save("OpenScribe: open scribe")

        XCTAssertEqual(store.entries(includeBuiltIn: true).map(\.term), ["OpenScribe", "worktree"])
        XCTAssertEqual(store.entries(includeBuiltIn: false).map(\.term), ["OpenScribe"])
        XCTAssertEqual(try String(contentsOf: layout.vocabularyFile, encoding: .utf8), "OpenScribe: open scribe")
    }

    func testWhisperGlossaryIsCappedAndPromptOnlyAppliesToShortRecordings() {
        let entries = (1...200).map { VocabularyEntry(term: "term\($0)", aliases: []) }
        let glossary = VocabularyPrompt.whisperGlossary(entries)

        XCTAssertNotNil(glossary)
        XCTAssertLessThanOrEqual(glossary?.count ?? 0, 720)
        XCTAssertNil(VocabularyPrompt.whisperGlossary([]))
        XCTAssertNotNil(WhisperCppProvider.vocabularyPrompt(entries, audioDurationSeconds: 30))
        XCTAssertNil(WhisperCppProvider.vocabularyPrompt(entries, audioDurationSeconds: 600))
        XCTAssertNil(WhisperCppProvider.vocabularyPrompt(entries, audioDurationSeconds: nil))

        let args = WhisperCppProvider.arguments(
            modelPath: "/m.bin",
            inputPath: "/i.wav",
            outputBasePath: "/o",
            language: nil,
            prompt: "Glossary: worktree."
        )
        XCTAssertEqual(args.firstIndex(of: "--prompt").map { args[$0 + 1] }, "Glossary: worktree.")
    }

    func testPolishRulesGainVocabularySectionOnlyWhenEntriesExist() {
        let rules = VocabularyPrompt.polishRules(
            "# Rules",
            entries: [VocabularyEntry(term: "gitignore", aliases: ["git ignore"])]
        )

        XCTAssertTrue(rules.hasPrefix("# Rules"))
        XCTAssertTrue(rules.contains("## Vocabulary"))
        XCTAssertTrue(rules.contains("- gitignore (may be heard as: git ignore)"))
        XCTAssertEqual(VocabularyPrompt.polishRules("# Rules", entries: []), "# Rules")
    }

    func testShippedDeveloperListParses() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenScribe/Resources/Vocabulary/developer-terms.txt")
        let entries = VocabularyParser.parse(try String(contentsOf: url, encoding: .utf8))

        XCTAssertGreaterThan(entries.count, 50)
        XCTAssertEqual(Set(entries.map { $0.term.lowercased() }).count, entries.count, "Terms must be unique")
    }

    private func makeTempLayout() throws -> DirectoryLayout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenScribeVocabularyTests-\(UUID().uuidString)", isDirectory: true)
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
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return layout
    }
}
