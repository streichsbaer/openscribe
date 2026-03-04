import Foundation

func unwrapCodeBlockIfNeeded(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else {
        return trimmed
    }

    let lines = trimmed.components(separatedBy: "\n")
    guard lines.count >= 2 else {
        return trimmed
    }

    var body = lines
    if body.first?.hasPrefix("```") == true {
        body.removeFirst()
    }
    if body.last?.hasPrefix("```") == true {
        body.removeLast()
    }

    return body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

func makePolishUserPrompt(rawText: String, rulesMarkdown: String) -> String {
    """
    Apply these polishing and glossary rules to the transcript.

    Hard constraints:
    - Return ONLY the polished transcript text.
    - Preserve meaning and intent.
    - Fix grammar, punctuation, capitalization, and phrasing.
    - Remove stutters, filler words, and irrelevant asides when meaning is unchanged.
    - Do NOT add explanations, labels, or any extra commentary.

    Rules:
    \(rulesMarkdown)

    Raw transcript:
    \(rawText)

    Return only final polished text.
    """
}

func sanitizePolishedOutput(_ markdown: String, rawText: String) -> String {
    let cleaned = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawLower = rawText.lowercased()
    if rawLower.contains("glossary") {
        return cleaned
    }

    let pattern = #"(?im)^(?:#{1,6}\s+)?glossary\b.*(?:\n|$)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return cleaned
    }

    let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
    guard let match = regex.firstMatch(in: cleaned, range: range),
          let headingRange = Range(match.range, in: cleaned) else {
        return cleaned
    }

    let prefix = String(cleaned[..<headingRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    return prefix
}
