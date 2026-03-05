import Foundation
import XCTest
@testable import OpenScribe

final class StatsStoreTests: XCTestCase {
    func testLoadSummaryAggregatesTranscriptionAndPolishMetrics() throws {
        let layout = try makeTempLayout()
        let store = StatsStore(layout: layout)

        let now = Date()
        let sessionOne = UUID()
        let sessionTwo = UUID()

        try store.append(StatsEvent(
            id: UUID(),
            sessionId: sessionOne,
            timestamp: now,
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 60.0,
            outputUnits: 120.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: 310,
            outputTokens: 126,
            recordingDurationMs: 60_000,
            wordsPerMinute: 120.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: sessionOne,
            timestamp: now.addingTimeInterval(1),
            stage: .polish,
            providerId: "gemini_polish",
            model: "gemini-2.5-flash-lite",
            inputUnits: 120.0,
            outputUnits: 96.0,
            inputUnit: .words,
            outputUnit: .words,
            inputTokens: 420,
            outputTokens: 290,
            recordingDurationMs: nil,
            wordsPerMinute: nil,
            wordDelta: -24,
            wordDeltaPercent: -20.0,
            processingDurationMs: nil
        ))
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: sessionTwo,
            timestamp: now.addingTimeInterval(2),
            stage: .transcription,
            providerId: "openai_whisper",
            model: "gpt-4o-mini-transcribe",
            inputUnits: 30.0,
            outputUnits: 45.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: 180,
            outputTokens: 60,
            recordingDurationMs: 30_000,
            wordsPerMinute: 90.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))

        let summary = store.loadSummary()

        XCTAssertEqual(summary.totalEvents, 3)
        XCTAssertEqual(summary.sessionCount, 2)
        XCTAssertEqual(summary.transcriptionRuns, 2)
        XCTAssertEqual(summary.polishRuns, 1)
        XCTAssertEqual(summary.currentActiveDayStreak, 1)
        XCTAssertEqual(summary.longestActiveDayStreak, 1)
        XCTAssertNil(summary.averageDaysBetweenActiveDays)
        XCTAssertEqual(summary.spokenWords, 165)
        XCTAssertEqual(summary.wordsLast7Days, 165)
        XCTAssertEqual(summary.wordsLast30Days, 165)
        XCTAssertEqual(summary.averageWordsPerMinute ?? 0, 110, accuracy: 0.01)
        XCTAssertEqual(summary.polishDeltaWords, -24)
        XCTAssertEqual(summary.polishDeltaPercent ?? 0, -20, accuracy: 0.01)
        XCTAssertEqual(summary.providerUsage.count, 3)
        let transcriptionUsage = summary.providerUsage.first(where: { $0.stage == .transcription && $0.providerId == "groq_whisper" })
        XCTAssertEqual(transcriptionUsage?.inputTokens, 310)
        XCTAssertEqual(transcriptionUsage?.outputTokens, 126)
        XCTAssertEqual(transcriptionUsage?.tokenRunCount, 1)
        let polishUsage = summary.providerUsage.first(where: { $0.stage == .polish && $0.providerId == "gemini_polish" })
        XCTAssertEqual(polishUsage?.inputTokens, 420)
        XCTAssertEqual(polishUsage?.outputTokens, 290)
        XCTAssertEqual(polishUsage?.tokenRunCount, 1)
        XCTAssertEqual(summary.latestTranscriptionEvent?.sessionId, sessionTwo)
        XCTAssertEqual(summary.latestTranscriptionEvent?.outputTokens, 60)
        XCTAssertEqual(summary.latestPolishEvent?.sessionId, sessionOne)
        XCTAssertEqual(summary.latestPolishEvent?.outputTokens, 290)
        let expectedLastEvent = now.addingTimeInterval(2)
        XCTAssertEqual(summary.lastEventAt?.timeIntervalSince(expectedLastEvent) ?? 0, 0, accuracy: 1.0)
    }

    func testLoadSummaryReturnsEmptyWhenLedgerIsMissing() throws {
        let layout = try makeTempLayout()
        let store = StatsStore(layout: layout)

        let summary = store.loadSummary()

        XCTAssertEqual(summary, .empty)
    }

    func testLoadSummaryComputesConsecutiveActiveDayStreaks() throws {
        let layout = try makeTempLayout()
        let store = StatsStore(layout: layout)

        let calendar = Calendar.current
        let baseDay = calendar.startOfDay(for: Date())
        let offsets = [-4, -2, -1, 0]

        for (index, dayOffset) in offsets.enumerated() {
            let timestamp = (calendar.date(byAdding: .day, value: dayOffset, to: baseDay) ?? baseDay)
                .addingTimeInterval(3_600)
            try store.append(StatsEvent(
                id: UUID(),
                sessionId: UUID(),
                timestamp: timestamp,
                stage: .transcription,
                providerId: "groq_whisper",
                model: "whisper-large-v3-turbo",
                inputUnits: 45.0,
                outputUnits: Double(50 + index),
                inputUnit: .audioSeconds,
                outputUnit: .words,
                inputTokens: nil,
                outputTokens: nil,
                recordingDurationMs: 45_000,
                wordsPerMinute: 100.0,
                wordDelta: nil,
                wordDeltaPercent: nil,
                processingDurationMs: nil
            ))
        }

        let summary = store.loadSummary()

        XCTAssertEqual(summary.currentActiveDayStreak, 3)
        XCTAssertEqual(summary.longestActiveDayStreak, 3)
        XCTAssertEqual(summary.averageDaysBetweenActiveDays ?? 0, 1.0 / 3.0, accuracy: 0.01)
    }

    func testNewSummaryFields() throws {
        let layout = try makeTempLayout()
        let store = StatsStore(layout: layout)

        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
            .addingTimeInterval(3600)

        let sessionOne = UUID()
        let sessionTwo = UUID()

        try store.append(StatsEvent(
            id: UUID(),
            sessionId: sessionOne,
            timestamp: yesterday,
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 60.0,
            outputUnits: 100.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 60_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: sessionTwo,
            timestamp: now,
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 30.0,
            outputUnits: 50.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 30_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))

        let summary = store.loadSummary()

        XCTAssertEqual(summary.activeDayCount, 2)
        XCTAssertEqual(summary.averageWordsPerDay ?? 0, 75.0, accuracy: 0.01)
        XCTAssertEqual(summary.averageWordsPerSession ?? 0, 75.0, accuracy: 0.01)
        XCTAssertEqual(summary.totalRecordingDurationSeconds, 90.0, accuracy: 0.01)
        XCTAssertEqual(summary.averageRecordingDurationSeconds ?? 0, 45.0, accuracy: 0.01)
    }

    func testProcessingDurationAverages() throws {
        let layout = try makeTempLayout()
        let store = StatsStore(layout: layout)

        let now = Date()
        let session = UUID()

        try store.append(StatsEvent(
            id: UUID(),
            sessionId: session,
            timestamp: now,
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 30.0,
            outputUnits: 50.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 30_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: 2000
        ))
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: session,
            timestamp: now.addingTimeInterval(1),
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 30.0,
            outputUnits: 50.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 30_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: 4000
        ))
        // Transcription event with nil processingDurationMs should be excluded from average
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: session,
            timestamp: now.addingTimeInterval(2),
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 30.0,
            outputUnits: 50.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 30_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: session,
            timestamp: now.addingTimeInterval(3),
            stage: .polish,
            providerId: "gemini_polish",
            model: "gemini-2.5-flash-lite",
            inputUnits: 50.0,
            outputUnits: 45.0,
            inputUnit: .words,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: nil,
            wordsPerMinute: nil,
            wordDelta: -5,
            wordDeltaPercent: -10.0,
            processingDurationMs: 1500
        ))

        let summary = store.loadSummary()

        XCTAssertEqual(summary.averageTranscriptionProcessingMs ?? 0, 3000.0, accuracy: 0.01)
        XCTAssertEqual(summary.averagePolishProcessingMs ?? 0, 1500.0, accuracy: 0.01)
    }

    func testWeeklyTrend() throws {
        let layout = try makeTempLayout()
        let store = StatsStore(layout: layout)

        let calendar = Calendar.current
        let now = Date()

        // 100 words 3 days ago (within 7-day window)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: UUID(),
            timestamp: threeDaysAgo,
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 60.0,
            outputUnits: 100.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 60_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))

        // 100 words 20 days ago (within 30-day but not 7-day)
        let twentyDaysAgo = calendar.date(byAdding: .day, value: -20, to: now)!
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: UUID(),
            timestamp: twentyDaysAgo,
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 60.0,
            outputUnits: 100.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 60_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))

        let summary = store.loadSummary()

        // wordsLast7Days = 100, wordsLast30Days = 200
        // weeklyRate = 100/1.0 = 100
        // monthlyWeeklyRate = 200/(30/7) = 200/4.2857 = 46.667
        // trend = ((100 - 46.667) / 46.667) * 100 = 114.29%
        XCTAssertNotNil(summary.weeklyTrend)
        XCTAssertEqual(summary.weeklyTrend ?? 0, 114.29, accuracy: 0.5)
    }

    func testDailyWordCountsAggregation() throws {
        let layout = try makeTempLayout()
        let store = StatsStore(layout: layout)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let session = UUID()

        // Two events on today
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: session,
            timestamp: today.addingTimeInterval(3600),
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 30.0,
            outputUnits: 80.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 30_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: session,
            timestamp: today.addingTimeInterval(7200),
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 30.0,
            outputUnits: 45.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 30_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))

        // One event yesterday
        try store.append(StatsEvent(
            id: UUID(),
            sessionId: UUID(),
            timestamp: yesterday.addingTimeInterval(3600),
            stage: .transcription,
            providerId: "groq_whisper",
            model: "whisper-large-v3-turbo",
            inputUnits: 60.0,
            outputUnits: 200.0,
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: nil,
            outputTokens: nil,
            recordingDurationMs: 60_000,
            wordsPerMinute: 100.0,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: nil
        ))

        let summary = store.loadSummary()

        XCTAssertEqual(summary.dailyWordCounts.count, 2)
        XCTAssertEqual(summary.dailyWordCounts[today], 125)
        XCTAssertEqual(summary.dailyWordCounts[yesterday], 200)
    }

    func testDailyWordCountsEmptyWhenNoEvents() throws {
        let layout = try makeTempLayout()
        let store = StatsStore(layout: layout)

        let summary = store.loadSummary()

        XCTAssertTrue(summary.dailyWordCounts.isEmpty)
    }

    func testWeeklyTrendNilWhenNoWords() throws {
        let layout = try makeTempLayout()
        let store = StatsStore(layout: layout)

        let summary = store.loadSummary()

        XCTAssertNil(summary.weeklyTrend)
    }

    private func makeTempLayout() throws -> DirectoryLayout {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OpenScribeStatsTests-\(UUID().uuidString)", isDirectory: true)

        let layout = DirectoryLayout(
            appSupport: root,
            recordings: root.appendingPathComponent("Recordings", isDirectory: true),
            rules: root.appendingPathComponent("Rules", isDirectory: true),
            stats: root.appendingPathComponent("Stats", isDirectory: true),
            models: root.appendingPathComponent("Models/whisper", isDirectory: true),
            config: root.appendingPathComponent("Config", isDirectory: true),
            rulesFile: root.appendingPathComponent("Rules/rules.md"),
            rulesHistory: root.appendingPathComponent("Rules/rules.history.jsonl"),
            statsEventsFile: root.appendingPathComponent("Stats/usage.events.jsonl"),
            settingsFile: root.appendingPathComponent("Config/settings.json")
        )

        try layout.ensureExists()
        return layout
    }
}
