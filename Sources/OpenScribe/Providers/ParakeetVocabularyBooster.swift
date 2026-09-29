import FluidAudio
import Foundation

/// Rescores Parakeet transcripts toward vocabulary terms. A small CTC model spots the terms in the
/// audio; a word is replaced only when the audio supports the term more than the original word.
struct ParakeetVocabularyBooster {
    struct Tuning: Sendable {
        var rescorer: VocabularyRescorer.Config
        /// String similarity a word needs to the term or one of its sounds-like spellings.
        var minSimilarity: Float?
        /// Terms this short sit one letter from everyday words ("Tom" and TOML), so they need a
        /// closer match. Exact sounds-like spellings still match.
        var shortTermMaxLength: Int? = nil
        var shortTermMinSimilarity: Float? = nil
    }

    /// Tuned with Scripts/stt-bench (runs 2026-09-29-devterms-*). FluidAudio's defaults rewrote ordinary
    /// words into terms ("Miss" into "mise", "shocked" into "Docker"). With these gates, developer-term
    /// recall rose from 56 to 84 percent while LibriSpeech error stayed identical and no term was inserted
    /// into general speech.
    static let shippedTuning = Tuning(
        rescorer: VocabularyRescorer.Config(spotterRescueEnabled: false),
        minSimilarity: 0.75,
        shortTermMaxLength: 5,
        shortTermMinSimilarity: 0.85
    )

    private let context: CustomVocabularyContext
    private let spotter: CtcKeywordSpotter
    private let rescorer: VocabularyRescorer
    private let sizeConfig: ContextBiasingConstants.VocabSizeConfig

    init(entries: [VocabularyEntry], modelDirectory: URL, tuning: Tuning = shippedTuning) async throws {
        let models = try await CtcModels.loadDirect(from: modelDirectory, variant: .ctc110m)
        let tokenizer = try await CtcTokenizer.load(from: modelDirectory)
        let terms = entries.compactMap { entry -> CustomVocabularyTerm? in
            let tokens = tokenizer.encode(entry.term)
            guard !tokens.isEmpty else {
                return nil
            }
            let isShort = tuning.shortTermMaxLength.map { entry.term.count <= $0 } ?? false
            return CustomVocabularyTerm(
                text: entry.term,
                aliases: entry.aliases.isEmpty ? nil : entry.aliases,
                ctcTokenIds: tokens,
                minSimilarity: isShort ? tuning.shortTermMinSimilarity : nil
            )
        }
        context = tuning.minSimilarity.map { CustomVocabularyContext(terms: terms, minSimilarity: $0) }
            ?? CustomVocabularyContext(terms: terms)
        spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        rescorer = try await VocabularyRescorer.create(
            spotter: spotter,
            vocabulary: context,
            config: tuning.rescorer,
            ctcModelDirectory: modelDirectory
        )
        sizeConfig = ContextBiasingConstants.rescorerConfig(forVocabSize: context.terms.count)
        // The first CTC inference compiles its kernels; pay that cost now, not on a dictation.
        _ = try? await spotter.spotKeywordsWithLogProbs(
            audioSamples: [Float](repeating: 0, count: 16_000),
            customVocabulary: context,
            minScore: nil
        )
    }

    func rescore(text: String, tokenTimings: [TokenTiming], samples: [Float]) async -> String {
        guard !context.terms.isEmpty, !tokenTimings.isEmpty,
              let spot = try? await spotter.spotKeywordsWithLogProbs(
                  audioSamples: samples,
                  customVocabulary: context,
                  minScore: nil
              ),
              !spot.logProbs.isEmpty else {
            return text
        }
        // FluidAudio decides which words to replace; OpenScribe applies those decisions to the untouched
        // transcript so punctuation around a replaced word survives and the term keeps its listed casing.
        let evidence = rescorer.ctcTokenEvaluateCandidates(
            transcript: text,
            tokenTimings: tokenTimings,
            logProbs: spot.logProbs,
            frameDuration: spot.frameDuration,
            cbw: sizeConfig.cbw,
            marginSeconds: 0.5,
            minSimilarity: max(sizeConfig.minSimilarity, context.minSimilarity)
        )
        let replacements = evidence.candidates.compactMap { candidate -> Replacement? in
            guard candidate.legacyOutcome == .applied, let range = candidate.baseTextUTF8Range else {
                return nil
            }
            return Replacement(utf8Range: range, term: candidate.canonicalTerm)
        }
        return Self.apply(replacements, to: evidence.baseText)
    }

    struct Replacement: Equatable {
        let utf8Range: Range<Int>
        let term: String
    }

    /// Replaces each range with its term. Punctuation at the edges of the replaced words stays, and the
    /// term keeps its listed casing except for a capital first letter at the start of a sentence.
    static func apply(_ replacements: [Replacement], to text: String) -> String {
        let bytes = Array(text.utf8)
        var result = ""
        var cursor = 0
        for replacement in replacements.sorted(by: { $0.utf8Range.lowerBound < $1.utf8Range.lowerBound }) {
            let range = replacement.utf8Range
            guard range.lowerBound >= cursor, range.upperBound <= bytes.count, !range.isEmpty,
                  let before = String(bytes: bytes[cursor..<range.lowerBound], encoding: .utf8),
                  let original = String(bytes: bytes[range], encoding: .utf8) else {
                continue
            }
            let leading = String(original.prefix { !$0.isLetter && !$0.isNumber })
            let trailing = String(original.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
            let core = original.dropFirst(leading.count).dropLast(trailing.count)

            var term = replacement.term
            let startsSentence = (result + before).trimmingCharacters(in: .whitespacesAndNewlines).last
                .map { ".!?".contains($0) } ?? true
            if startsSentence, core.first?.isUppercase == true, let first = term.first, first.isLowercase {
                term = first.uppercased() + term.dropFirst()
            }
            result += before + leading + term + trailing
            cursor = range.upperBound
        }
        result += String(bytes: bytes[cursor...], encoding: .utf8) ?? ""
        return result
    }
}
