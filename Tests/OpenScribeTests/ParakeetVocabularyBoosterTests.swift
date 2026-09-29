import XCTest
@testable import OpenScribe

final class ParakeetVocabularyBoosterTests: XCTestCase {
    func testReplacementsKeepPunctuationAndUseListedCasing() {
        let text = "I think now we can do stuff like Crone, Set Shell, Tmux, mice, etc."
        let result = ParakeetVocabularyBooster.apply(
            [
                replacement("Crone,", in: text, term: "cron"),
                replacement("Set Shell,", in: text, term: "zsh"),
                replacement("mice,", in: text, term: "mise")
            ],
            to: text
        )

        XCTAssertEqual(result, "I think now we can do stuff like cron, zsh, Tmux, mise, etc.")
    }

    func testFixesReportWhatWasHeardAndSkipCasingOnlyChanges() {
        let text = "Run mies install in the tea mux session, then Tmux again."
        let fixes = ParakeetVocabularyBooster.fixes(
            for: [
                replacement("mies", in: text, term: "mise"),
                replacement("tea mux", in: text, term: "tmux"),
                replacement("Tmux", in: text, term: "tmux"),
                replacement("mies", in: text, term: "mise")
            ],
            in: text
        )

        XCTAssertEqual(fixes, [
            VocabularyFix(heard: "mies", term: "mise"),
            VocabularyFix(heard: "tea mux", term: "tmux")
        ])
    }

    func testSentenceStartCapitalizesLowercaseTerm() {
        let text = "It works. Crone runs nightly. Crone"
        let first = replacement("Crone runs", in: text, term: "cron runs")
        let result = ParakeetVocabularyBooster.apply(
            [
                first,
                ParakeetVocabularyBooster.Replacement(
                    utf8Range: (text.utf8.count - 5)..<text.utf8.count,
                    term: "cron"
                )
            ],
            to: text
        )

        XCTAssertEqual(result, "It works. Cron runs nightly. Cron")
    }

    func testTermCasingWinsInsideASentence() {
        let text = "Open the open scribe settings and set up post gress."
        let result = ParakeetVocabularyBooster.apply(
            [
                replacement("open scribe", in: text, term: "OpenScribe"),
                replacement("post gress.", in: text, term: "PostgreSQL")
            ],
            to: text
        )

        XCTAssertEqual(result, "Open the OpenScribe settings and set up PostgreSQL.")
    }

    func testLeadingPunctuationAndQuestionMarksSurvive() {
        let text = "Did you run \"kube control\"?"
        let result = ParakeetVocabularyBooster.apply([replacement("\"kube control\"?", in: text, term: "kubectl")], to: text)

        XCTAssertEqual(result, "Did you run \"kubectl\"?")
    }

    func testMultibyteTextBeforeReplacementStaysIntact() {
        let text = "Grüße aus München, starte die work tree."
        let result = ParakeetVocabularyBooster.apply([replacement("work tree.", in: text, term: "worktree")], to: text)

        XCTAssertEqual(result, "Grüße aus München, starte die worktree.")
    }

    func testOverlappingAndOutOfBoundsReplacementsAreSkipped() {
        let text = "use the mono repo now"
        let result = ParakeetVocabularyBooster.apply(
            [
                replacement("mono repo", in: text, term: "monorepo"),
                replacement("repo now", in: text, term: "repository"),
                ParakeetVocabularyBooster.Replacement(utf8Range: 90..<95, term: "ignored")
            ],
            to: text
        )

        XCTAssertEqual(result, "use the monorepo now")
    }

    func testNoReplacementsReturnsTextUnchanged() {
        XCTAssertEqual(ParakeetVocabularyBooster.apply([], to: "Nothing to change."), "Nothing to change.")
    }

    private func replacement(_ phrase: String, in text: String, term: String) -> ParakeetVocabularyBooster.Replacement {
        let range = text.range(of: phrase)!
        let lower = text.utf8.distance(from: text.utf8.startIndex, to: range.lowerBound)
        let upper = text.utf8.distance(from: text.utf8.startIndex, to: range.upperBound)
        return ParakeetVocabularyBooster.Replacement(utf8Range: lower..<upper, term: term)
    }
}
