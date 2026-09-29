import Foundation

final class VocabularyStore: ObservableObject {
    static let builtInResourceName = "developer-terms"

    @Published private(set) var userText: String = ""
    let builtInEntries: [VocabularyEntry]

    private let userURL: URL
    private let fileManager: FileManager

    init(layout: DirectoryLayout, builtInText: String? = VocabularyStore.loadBuiltInText(), fileManager: FileManager = .default) {
        self.userURL = layout.vocabularyFile
        self.fileManager = fileManager
        self.builtInEntries = VocabularyParser.parse(builtInText ?? "")

        if !fileManager.fileExists(atPath: userURL.path) {
            try? Self.defaultTemplate.write(to: userURL, atomically: true, encoding: .utf8)
        }
        userText = (try? String(contentsOf: userURL, encoding: .utf8)) ?? ""
    }

    var userEntries: [VocabularyEntry] {
        VocabularyParser.parse(userText)
    }

    func entries(includeBuiltIn: Bool) -> [VocabularyEntry] {
        VocabularyParser.merge(user: userEntries, builtIn: includeBuiltIn ? builtInEntries : [])
    }

    func save(_ text: String) throws {
        try text.write(to: userURL, atomically: true, encoding: .utf8)
        userText = text
    }

    static func loadBuiltInText() -> String? {
        guard let url = OpenScribeResourceLocator.url(forResource: builtInResourceName, withExtension: "txt") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static let defaultTemplate = """
    # Your vocabulary
    # One term per line, written the way it should appear in transcripts.
    # Add sounds-like spellings after a colon, separated by commas.
    # Example:
    # Kubernetes: cube er net ease
    # Your entries replace built-in entries with the same term.

    """
}

enum VocabularyPrompt {
    /// Whisper reads its prompt as preceding text, so a glossary sentence biases spelling toward the
    /// terms. Longer prompts are truncated by Whisper, so the list is capped.
    static func whisperGlossary(_ entries: [VocabularyEntry], limitCharacters: Int = 700) -> String? {
        var terms: [String] = []
        var used = 0
        for entry in entries {
            guard used + entry.term.count + 2 <= limitCharacters else {
                break
            }
            terms.append(entry.term)
            used += entry.term.count + 2
        }
        return terms.isEmpty ? nil : "Glossary: \(terms.joined(separator: ", "))."
    }

    /// Adds a vocabulary section to the polish rules so the model restores exact spellings.
    static func polishRules(_ rulesMarkdown: String, entries: [VocabularyEntry]) -> String {
        guard !entries.isEmpty else {
            return rulesMarkdown
        }
        let lines = entries.map { entry in
            entry.aliases.isEmpty ? "- \(entry.term)" : "- \(entry.term) (may be heard as: \(entry.aliases.joined(separator: ", ")))"
        }
        return rulesMarkdown + """


        ## Vocabulary

        When the text refers to one of these terms, write it exactly as spelled here:
        \(lines.joined(separator: "\n"))
        """
    }
}
