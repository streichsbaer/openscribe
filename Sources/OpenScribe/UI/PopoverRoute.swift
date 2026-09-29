import Foundation

/// Where a dictation goes, step by step, and one honest sentence about what leaves the Mac.
struct PopoverRoute: Equatable {
    enum Delivery: Equatable {
        case paste
        case copy
        case none
    }

    struct Step: Equatable {
        let title: String
        let detail: String
        let isLocal: Bool
    }

    let transcription: Step
    /// Nil when polish is off.
    let polish: Step?
    let delivery: Delivery
    let isFinished: Bool
    /// The part of the sentence shown in the local or cloud color.
    let lead: String
    let rest: String

    var staysOnMac: Bool {
        transcription.isLocal && polish == nil
    }

    init(
        transcriptionProvider: String,
        transcriptionModelName: String,
        polishProvider: String?,
        polishModel: String?,
        delivery: Delivery,
        isFinished: Bool,
        transcriptionMs: Int?,
        polishMs: Int?
    ) {
        let isLocal = ProviderModelCatalog.isLocalTranscriptionProvider(transcriptionProvider)
        let transcriptionTiming = transcriptionMs.map { " · " + PopoverFormat.processing(ms: $0) } ?? ""
        transcription = Step(
            title: isLocal ? transcriptionModelName : ProviderNames.shortModel(transcriptionModelName),
            detail: (isLocal ? "On this Mac" : "\(ProviderNames.display(transcriptionProvider)) cloud") + transcriptionTiming,
            isLocal: isLocal
        )

        if let polishProvider, let polishModel, polishProvider != "disabled", !polishProvider.isEmpty {
            polish = Step(
                title: ProviderNames.shortModel(polishModel),
                detail: "\(ProviderNames.display(polishProvider)) cloud" + (polishMs.map { " · " + PopoverFormat.processing(ms: $0) } ?? ""),
                isLocal: false
            )
        } else {
            polish = nil
        }
        self.delivery = delivery
        self.isFinished = isFinished

        let polishName = polishProvider.map(ProviderNames.display) ?? ""
        switch (isLocal, polish != nil) {
        case (true, false):
            lead = isFinished ? "Stayed on this Mac." : "Stays on this Mac."
            rest = isFinished ? "Nothing was sent anywhere." : "Your voice and text are not sent anywhere."
        case (true, true):
            lead = isFinished ? "Text went to \(polishName) to polish." : "Text goes to \(polishName) to polish."
            rest = isFinished ? "Your audio stayed on this Mac." : "Your audio stays on this Mac."
        case (false, let polished):
            let sttName = ProviderNames.display(transcriptionProvider)
            lead = isFinished ? "Audio went to \(sttName) to transcribe." : "Audio goes to \(sttName) to transcribe."
            if polished {
                rest = isFinished ? "Then the text went to \(polishName) to polish." : "Then the text goes to \(polishName) to polish."
            } else {
                rest = ""
            }
        }
    }
}

/// A word-level comparison of the raw and polished transcript for the Changes view.
enum TranscriptDiff {
    enum Kind: Equatable {
        case same
        case removed
        case added
    }

    struct Token: Equatable {
        let text: String
        let kind: Kind
    }

    static func words(from original: String, to revised: String) -> [Token] {
        let originalWords = split(original)
        let revisedWords = split(revised)
        let difference = revisedWords.difference(from: originalWords) { key($0) == key($1) }

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _):
                removed.insert(offset)
            case let .insert(offset, _, _):
                inserted.insert(offset)
            }
        }

        var tokens: [Token] = []
        func append(_ word: String, _ kind: Kind) {
            if let last = tokens.last, last.kind == kind {
                tokens[tokens.count - 1] = Token(text: last.text + " " + word, kind: kind)
            } else {
                tokens.append(Token(text: word, kind: kind))
            }
        }

        var originalIndex = 0
        var revisedIndex = 0
        while originalIndex < originalWords.count || revisedIndex < revisedWords.count {
            if originalIndex < originalWords.count, removed.contains(originalIndex) {
                append(originalWords[originalIndex], .removed)
                originalIndex += 1
            } else if revisedIndex < revisedWords.count, inserted.contains(revisedIndex) {
                append(revisedWords[revisedIndex], .added)
                revisedIndex += 1
            } else if originalIndex < originalWords.count, revisedIndex < revisedWords.count {
                append(revisedWords[revisedIndex], .same)
                originalIndex += 1
                revisedIndex += 1
            } else {
                break
            }
        }
        return tokens
    }

    private static func split(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    /// Case and punctuation changes alone do not count as a changed word.
    private static func key(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
