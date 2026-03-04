import Foundation

func normalizedInstruction(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func resolvedInstruction(_ value: String?, fallback: String) -> String {
    normalizedInstruction(value) ?? fallback
}
