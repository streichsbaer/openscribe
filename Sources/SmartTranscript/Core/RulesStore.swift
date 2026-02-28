import AppKit
import Foundation

final class RulesStore: ObservableObject {
    @Published private(set) var currentRules: String = ""

    private let rulesURL: URL
    private let historyURL: URL
    private let fileManager: FileManager

    init(layout: DirectoryLayout, fileManager: FileManager = .default) {
        self.rulesURL = layout.rulesFile
        self.historyURL = layout.rulesHistory
        self.fileManager = fileManager

        try? bootstrapDefaults()
        currentRules = (try? load()) ?? ""
    }

    func load() throws -> String {
        let content = try String(contentsOf: rulesURL, encoding: .utf8)
        currentRules = content
        return content
    }

    func save(_ content: String) throws {
        try atomicWrite(content, to: rulesURL)
        currentRules = content
    }

    func reload() {
        currentRules = (try? load()) ?? currentRules
    }

    func openInExternalEditor() {
        NSWorkspace.shared.open(rulesURL)
    }

    func appendHistory(summary: String, diff: String, approved: Bool) {
        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "summary": summary,
            "approved": approved,
            "diff": diff
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8) else {
            return
        }

        line.append("\n")

        if fileManager.fileExists(atPath: historyURL.path),
           let handle = try? FileHandle(forWritingTo: historyURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: historyURL, atomically: true, encoding: .utf8)
        }
    }

    private func bootstrapDefaults() throws {
        if fileManager.fileExists(atPath: rulesURL.path) {
            return
        }

        try atomicWrite(Self.defaultTemplate, to: rulesURL)
    }

    private func atomicWrite(_ content: String, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).tmp")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        try fileManager.moveItem(at: tempURL, to: url)
    }

    static let defaultTemplate = """
    # SmartTranscript Rules

    ## Goal
    Convert raw dictation into clean Markdown while preserving intent and wording.

    ## Spoken Formatting Commands
    - If speaker says "new line", insert a single newline.
    - If speaker says "new paragraph", insert a blank line (two newlines).
    - If speaker says "bullet point", start a list item with `- `.
    - If speaker enumerates "one", "two", "three", format as numbered list when context is clearly a list.

    ## Style
    - Keep punctuation clean and spacing normalized.
    - Keep headings and lists in valid Markdown.
    - Do not use em dashes.
    - Do not use contrastive negation phrasing like "it is not X, it is Y."
    - Remove filler words by default while preserving meaning.
    - Remove described background audio/noises like "(keyboard clicking)" unless they are contextually relevant.
    - Do not invent facts.

    ## Glossary
    - Add project-specific replacements below as `heard -> canonical`.
    - Example: `seismic -> Cysmiq`, but infer whether it’s Cysmiq Shift (which is our AI agent), or seismic shift (in normal conversational usage)
    """
}
