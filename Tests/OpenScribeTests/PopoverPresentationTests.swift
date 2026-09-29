import Foundation
import XCTest
@testable import OpenScribe

final class PopoverPresentationTests: XCTestCase {
    func testLocalRouteWithPolishOffStaysOnTheMac() {
        let route = PopoverRoute(
            transcriptionProvider: "parakeet",
            transcriptionModelName: "Parakeet Ultra",
            polishProvider: nil,
            polishModel: nil,
            delivery: .paste,
            isFinished: true,
            transcriptionMs: 120,
            polishMs: nil
        )

        XCTAssertTrue(route.staysOnMac)
        XCTAssertNil(route.polish)
        XCTAssertEqual(route.transcription.title, "Parakeet Ultra")
        XCTAssertEqual(route.transcription.detail, "On this Mac · 0.1 s")
        XCTAssertEqual(route.lead, "Stayed on this Mac.")
        XCTAssertEqual(route.rest, "Nothing was sent anywhere.")
    }

    func testLocalRouteWithPolishSaysOnlyTextLeaves() {
        let route = PopoverRoute(
            transcriptionProvider: "parakeet",
            transcriptionModelName: "Parakeet Ultra",
            polishProvider: "groq_polish",
            polishModel: "openai/gpt-oss-120b",
            delivery: .paste,
            isFinished: false,
            transcriptionMs: nil,
            polishMs: nil
        )

        XCTAssertFalse(route.staysOnMac)
        XCTAssertEqual(route.polish?.title, "gpt-oss-120b")
        XCTAssertEqual(route.polish?.detail, "Groq cloud")
        XCTAssertEqual(route.lead, "Text goes to Groq to polish.")
        XCTAssertEqual(route.rest, "Your audio stays on this Mac.")
    }

    func testCloudTranscriptionSaysAudioLeaves() {
        let route = PopoverRoute(
            transcriptionProvider: "openai_whisper",
            transcriptionModelName: "gpt-4o-mini-transcribe",
            polishProvider: "disabled",
            polishModel: "passthrough",
            delivery: .copy,
            isFinished: true,
            transcriptionMs: 1_400,
            polishMs: nil
        )

        XCTAssertFalse(route.transcription.isLocal)
        XCTAssertNil(route.polish)
        XCTAssertEqual(route.transcription.detail, "OpenAI cloud · 1.4 s")
        XCTAssertEqual(route.lead, "Audio went to OpenAI to transcribe.")
        XCTAssertEqual(route.rest, "")
    }

    func testDiffMarksRemovedFillersAndIgnoresCaseAndPunctuation() {
        let tokens = TranscriptDiff.words(
            from: "okay so let's push the branch um then open the PR",
            to: "Let's push the branch, then open the PR."
        )

        XCTAssertEqual(tokens, [
            .init(text: "okay so", kind: .removed),
            .init(text: "Let's push the branch,", kind: .same),
            .init(text: "um", kind: .removed),
            .init(text: "then open the PR.", kind: .same)
        ])
    }

    func testDiffMarksAddedWords() {
        let tokens = TranscriptDiff.words(from: "run the tests", to: "run all the tests")

        XCTAssertEqual(tokens, [
            .init(text: "run", kind: .same),
            .init(text: "all", kind: .added),
            .init(text: "the tests", kind: .same)
        ])
    }

    func testHistoryGroupsByDayWithTodayAndYesterday() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: Date())!
        let entries = [
            entry(at: now),
            entry(at: now.addingTimeInterval(-3_600)),
            entry(at: calendar.date(byAdding: .day, value: -1, to: now)!),
            entry(at: calendar.date(byAdding: .day, value: -5, to: now)!)
        ]

        let groups = HistoryDayGroup.groups(entries, now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.entries.count), [2, 1, 1])
        XCTAssertEqual(groups[0].title, "Today")
        XCTAssertEqual(groups[1].title, "Yesterday")
        XCTAssertFalse(groups[2].title.isEmpty)
    }

    func testHistoryEntryCloudUseFollowsProviders() {
        XCTAssertFalse(entry(at: Date()).usedCloud)
        XCTAssertTrue(entry(at: Date(), polishProvider: "groq_polish").usedCloud)
        XCTAssertTrue(entry(at: Date(), sttProvider: "groq_whisper").usedCloud)
        XCTAssertFalse(entry(at: Date(), sttProvider: "groq_whisper", state: .failed).usedCloud)
    }

    func testWholePercentsAlwaysAddUpToOneHundred() {
        XCTAssertEqual(StatsTabView.wholePercents([21, 0, 35]), [38, 0, 62])
        XCTAssertEqual(StatsTabView.wholePercents([1, 1, 1]).reduce(0, +), 100)
        XCTAssertEqual(StatsTabView.wholePercents([0, 0, 0]), [0, 0, 0])
    }

    private func entry(
        at date: Date,
        sttProvider: String = "parakeet",
        polishProvider: String = "disabled",
        state: SessionState = .completed
    ) -> SessionHistoryEntry {
        SessionHistoryEntry(
            id: UUID(),
            folderURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)"),
            createdAt: date,
            state: state,
            sttProvider: sttProvider,
            sttModel: sttProvider == "parakeet" ? "parakeet-ultra" : "whisper-large-v3-turbo",
            polishProvider: polishProvider,
            polishModel: polishProvider == "disabled" ? "passthrough" : "openai/gpt-oss-120b",
            previewText: "Sample",
            durationMs: 5_000,
            hadNoSpeech: false,
            lastError: nil
        )
    }
}
