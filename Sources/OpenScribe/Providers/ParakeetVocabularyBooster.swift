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
        let output = rescorer.ctcTokenRescore(
            transcript: text,
            tokenTimings: tokenTimings,
            logProbs: spot.logProbs,
            frameDuration: spot.frameDuration,
            cbw: sizeConfig.cbw,
            marginSeconds: 0.5,
            minSimilarity: max(sizeConfig.minSimilarity, context.minSimilarity)
        )
        return output.wasModified ? output.text : text
    }
}
