import Foundation

/// A term to transcribe exactly as written, with optional sounds-like spellings.
struct VocabularyEntry: Codable, Equatable, Hashable, Sendable {
    let term: String
    let aliases: [String]
}

/// Vocabulary text format: one term per line, sounds-like spellings after a colon separated by
/// commas, `#` starts a comment. Example: `gitignore: git ignore, get ignore`.
enum VocabularyParser {
    static func parse(_ text: String) -> [VocabularyEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                return nil
            }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let term = parts[0].trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else {
                return nil
            }
            let aliases = parts.count > 1
                ? parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            return VocabularyEntry(term: term, aliases: aliases)
        }
    }

    /// Your entries first; a built-in entry is dropped when you list the same term.
    static func merge(user: [VocabularyEntry], builtIn: [VocabularyEntry]) -> [VocabularyEntry] {
        var seen = Set(user.map { $0.term.lowercased() })
        var merged = user
        for entry in builtIn where seen.insert(entry.term.lowercased()).inserted {
            merged.append(entry)
        }
        return merged
    }
}
