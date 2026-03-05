import Foundation

enum StatsStage: String, Codable, CaseIterable {
    case transcription
    case polish

    var displayLabel: String {
        switch self {
        case .transcription:
            return "Transcription"
        case .polish:
            return "Polish"
        }
    }
}

enum StatsUnit: String, Codable {
    case words
    case audioSeconds = "audio_seconds"
}

struct StatsEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    let stage: StatsStage
    let providerId: String
    let model: String
    let inputUnits: Double
    let outputUnits: Double
    let inputUnit: StatsUnit
    let outputUnit: StatsUnit
    let inputTokens: Int?
    let outputTokens: Int?
    let recordingDurationMs: Int?
    let wordsPerMinute: Double?
    let wordDelta: Int?
    let wordDeltaPercent: Double?
    let processingDurationMs: Int?
}

struct StatsProviderUsage: Identifiable, Equatable {
    let stage: StatsStage
    let providerId: String
    let model: String
    let runCount: Int
    let inputUnits: Double
    let outputUnits: Double
    let inputUnit: StatsUnit
    let outputUnit: StatsUnit
    let inputTokens: Int
    let outputTokens: Int
    let tokenRunCount: Int

    var id: String {
        "\(stage.rawValue)|\(providerId)|\(model)|\(inputUnit.rawValue)|\(outputUnit.rawValue)"
    }
}

struct StatsSummary: Equatable {
    let totalEvents: Int
    let sessionCount: Int
    let transcriptionRuns: Int
    let polishRuns: Int
    let currentActiveDayStreak: Int
    let longestActiveDayStreak: Int
    let averageDaysBetweenActiveDays: Double?
    let spokenWords: Int
    let wordsLast7Days: Int
    let wordsLast30Days: Int
    let averageWordsPerMinute: Double?
    let polishDeltaWords: Int
    let polishDeltaPercent: Double?
    let providerUsage: [StatsProviderUsage]
    let lastEventAt: Date?
    let latestTranscriptionEvent: StatsEvent?
    let latestPolishEvent: StatsEvent?
    let activeDayCount: Int
    let averageWordsPerDay: Double?
    let averageWordsPerSession: Double?
    let totalRecordingDurationSeconds: Double
    let averageRecordingDurationSeconds: Double?
    let averageTranscriptionProcessingMs: Double?
    let averagePolishProcessingMs: Double?
    let weeklyTrend: Double?
    let dailyWordCounts: [Date: Int]
    let dailySessionCounts: [Date: Int]

    static let empty = StatsSummary(
        totalEvents: 0,
        sessionCount: 0,
        transcriptionRuns: 0,
        polishRuns: 0,
        currentActiveDayStreak: 0,
        longestActiveDayStreak: 0,
        averageDaysBetweenActiveDays: nil,
        spokenWords: 0,
        wordsLast7Days: 0,
        wordsLast30Days: 0,
        averageWordsPerMinute: nil,
        polishDeltaWords: 0,
        polishDeltaPercent: nil,
        providerUsage: [],
        lastEventAt: nil,
        latestTranscriptionEvent: nil,
        latestPolishEvent: nil,
        activeDayCount: 0,
        averageWordsPerDay: nil,
        averageWordsPerSession: nil,
        totalRecordingDurationSeconds: 0,
        averageRecordingDurationSeconds: nil,
        averageTranscriptionProcessingMs: nil,
        averagePolishProcessingMs: nil,
        weeklyTrend: nil,
        dailyWordCounts: [:],
        dailySessionCounts: [:]
    )
}

final class StatsStore {
    private let eventsURL: URL
    private let fileManager: FileManager

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(layout: DirectoryLayout, fileManager: FileManager = .default) {
        eventsURL = layout.statsEventsFile
        self.fileManager = fileManager
    }

    func append(_ event: StatsEvent) throws {
        var line = try Self.encoder.encode(event)
        line.append(0x0A)

        if fileManager.fileExists(atPath: eventsURL.path),
           let handle = try? FileHandle(forWritingTo: eventsURL) {
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: line)
            return
        }

        try line.write(to: eventsURL, options: .atomic)
    }

    func loadSummary() -> StatsSummary {
        let events = loadEvents()
        guard !events.isEmpty else {
            return .empty
        }

        let transcriptionEvents = events.filter { $0.stage == .transcription }
        let polishEvents = events.filter { $0.stage == .polish }
        let calendar = Calendar.current
        let now = Date()

        let transcriptionWordEvents = transcriptionEvents.filter { $0.outputUnit == .words }
        let spokenWords = Int(transcriptionWordEvents.reduce(0.0) { partial, event in
            partial + event.outputUnits
        }.rounded())
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        let wordsLast7Days = Int(transcriptionWordEvents.filter { $0.timestamp >= sevenDaysAgo }.reduce(0.0) { partial, event in
            partial + event.outputUnits
        }.rounded())
        let wordsLast30Days = Int(transcriptionWordEvents.filter { $0.timestamp >= thirtyDaysAgo }.reduce(0.0) { partial, event in
            partial + event.outputUnits
        }.rounded())

        let totalRecordingMs = transcriptionEvents.reduce(0) { partial, event in
            partial + max(0, event.recordingDurationMs ?? 0)
        }
        let averageWordsPerMinute: Double?
        if totalRecordingMs > 0 {
            let totalMinutes = Double(totalRecordingMs) / 60_000.0
            averageWordsPerMinute = totalMinutes > 0 ? Double(spokenWords) / totalMinutes : nil
        } else {
            averageWordsPerMinute = nil
        }

        let polishInputWords = polishEvents
            .filter { $0.inputUnit == .words }
            .reduce(0.0) { partial, event in
                partial + event.inputUnits
            }
        let polishOutputWords = polishEvents
            .filter { $0.outputUnit == .words }
            .reduce(0.0) { partial, event in
                partial + event.outputUnits
            }
        let polishDeltaWords = Int((polishOutputWords - polishInputWords).rounded())
        let polishDeltaPercent: Double?
        if polishInputWords > 0 {
            polishDeltaPercent = ((polishOutputWords - polishInputWords) / polishInputWords) * 100.0
        } else {
            polishDeltaPercent = nil
        }

        let providerUsage = summarizeProviderUsage(events)
        let sessionCount = Set(events.map(\.sessionId)).count
        let lastEventAt = events.map(\.timestamp).max()
        let latestTranscriptionEvent = transcriptionEvents.max(by: { $0.timestamp < $1.timestamp })
        let latestPolishEvent = polishEvents.max(by: { $0.timestamp < $1.timestamp })
        let activeTranscriptionDays = Set(transcriptionEvents.map { calendar.startOfDay(for: $0.timestamp) })
        let currentActiveDayStreak = currentActiveDayRun(
            for: activeTranscriptionDays,
            now: now,
            calendar: calendar
        )
        let longestActiveDayStreak = longestActiveDayRun(
            for: activeTranscriptionDays,
            calendar: calendar
        )
        let averageDaysBetweenActiveDays = averageGapBetweenActiveDays(
            for: activeTranscriptionDays,
            calendar: calendar
        )

        let activeDayCount = activeTranscriptionDays.count
        let averageWordsPerDay: Double? = activeDayCount > 0 ? Double(spokenWords) / Double(activeDayCount) : nil
        let averageWordsPerSession: Double? = sessionCount > 0 ? Double(spokenWords) / Double(sessionCount) : nil
        let totalRecordingDurationSeconds = Double(totalRecordingMs) / 1000.0
        let averageRecordingDurationSeconds: Double? = transcriptionEvents.count > 0
            ? totalRecordingDurationSeconds / Double(transcriptionEvents.count) : nil

        let transcriptionProcessingValues = transcriptionEvents.compactMap(\.processingDurationMs)
        let averageTranscriptionProcessingMs: Double? = transcriptionProcessingValues.isEmpty
            ? nil : Double(transcriptionProcessingValues.reduce(0, +)) / Double(transcriptionProcessingValues.count)

        let polishProcessingValues = polishEvents.compactMap(\.processingDurationMs)
        let averagePolishProcessingMs: Double? = polishProcessingValues.isEmpty
            ? nil : Double(polishProcessingValues.reduce(0, +)) / Double(polishProcessingValues.count)

        var dailyWordCounts: [Date: Int] = [:]
        var dailySessionSets: [Date: Set<UUID>] = [:]
        for event in transcriptionWordEvents {
            let day = calendar.startOfDay(for: event.timestamp)
            dailyWordCounts[day, default: 0] += Int(event.outputUnits.rounded())
            dailySessionSets[day, default: []].insert(event.sessionId)
        }
        let dailySessionCounts = dailySessionSets.mapValues(\.count)

        let weeklyTrend: Double?
        if wordsLast30Days > 0 {
            let weeklyRate = Double(wordsLast7Days) / 1.0
            let monthlyWeeklyRate = Double(wordsLast30Days) / (30.0 / 7.0)
            weeklyTrend = ((weeklyRate - monthlyWeeklyRate) / monthlyWeeklyRate) * 100.0
        } else {
            weeklyTrend = nil
        }

        return StatsSummary(
            totalEvents: events.count,
            sessionCount: sessionCount,
            transcriptionRuns: transcriptionEvents.count,
            polishRuns: polishEvents.count,
            currentActiveDayStreak: currentActiveDayStreak,
            longestActiveDayStreak: longestActiveDayStreak,
            averageDaysBetweenActiveDays: averageDaysBetweenActiveDays,
            spokenWords: spokenWords,
            wordsLast7Days: wordsLast7Days,
            wordsLast30Days: wordsLast30Days,
            averageWordsPerMinute: averageWordsPerMinute,
            polishDeltaWords: polishDeltaWords,
            polishDeltaPercent: polishDeltaPercent,
            providerUsage: providerUsage,
            lastEventAt: lastEventAt,
            latestTranscriptionEvent: latestTranscriptionEvent,
            latestPolishEvent: latestPolishEvent,
            activeDayCount: activeDayCount,
            averageWordsPerDay: averageWordsPerDay,
            averageWordsPerSession: averageWordsPerSession,
            totalRecordingDurationSeconds: totalRecordingDurationSeconds,
            averageRecordingDurationSeconds: averageRecordingDurationSeconds,
            averageTranscriptionProcessingMs: averageTranscriptionProcessingMs,
            averagePolishProcessingMs: averagePolishProcessingMs,
            weeklyTrend: weeklyTrend,
            dailyWordCounts: dailyWordCounts,
            dailySessionCounts: dailySessionCounts
        )
    }

    private func currentActiveDayRun(
        for activeDays: Set<Date>,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)

        let startDay: Date
        if activeDays.contains(today) {
            startDay = today
        } else if let yesterday, activeDays.contains(yesterday) {
            startDay = yesterday
        } else {
            return 0
        }

        var streak = 0
        var cursor = startDay
        while activeDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: previousDay)
        }

        return streak
    }

    private func longestActiveDayRun(for activeDays: Set<Date>, calendar: Calendar) -> Int {
        let sortedDays = activeDays.sorted()
        guard !sortedDays.isEmpty else {
            return 0
        }
        guard sortedDays.count > 1 else {
            return 1
        }

        var longest = 1
        var current = 1
        for index in 1..<sortedDays.count {
            let previous = sortedDays[index - 1]
            let day = sortedDays[index]
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? Int.max
            if gap == 1 {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }
        return longest
    }

    private func averageGapBetweenActiveDays(for activeDays: Set<Date>, calendar: Calendar) -> Double? {
        let sortedDays = activeDays.sorted()
        guard sortedDays.count > 1 else {
            return nil
        }

        var totalGapDays = 0
        var gapCount = 0
        for index in 1..<sortedDays.count {
            let previous = sortedDays[index - 1]
            let day = sortedDays[index]
            let interval = max(0, calendar.dateComponents([.day], from: previous, to: day).day ?? 0)
            let gap = max(0, interval - 1)
            totalGapDays += gap
            gapCount += 1
        }
        guard gapCount > 0 else {
            return nil
        }
        return Double(totalGapDays) / Double(gapCount)
    }

    private func loadEvents() -> [StatsEvent] {
        guard fileManager.fileExists(atPath: eventsURL.path),
              let content = try? String(contentsOf: eventsURL, encoding: .utf8) else {
            return []
        }

        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else {
                    return nil
                }
                return try? Self.decoder.decode(StatsEvent.self, from: data)
            }
    }

    private func summarizeProviderUsage(_ events: [StatsEvent]) -> [StatsProviderUsage] {
        struct UsageKey: Hashable {
            let stage: StatsStage
            let providerId: String
            let model: String
            let inputUnit: StatsUnit
            let outputUnit: StatsUnit
        }

        struct UsageAggregate {
            var runCount: Int
            var inputUnits: Double
            var outputUnits: Double
            var inputTokens: Int
            var outputTokens: Int
            var tokenRunCount: Int
        }

        var grouped: [UsageKey: UsageAggregate] = [:]
        for event in events {
            let key = UsageKey(
                stage: event.stage,
                providerId: event.providerId,
                model: event.model,
                inputUnit: event.inputUnit,
                outputUnit: event.outputUnit
            )
            var aggregate = grouped[key] ?? UsageAggregate(
                runCount: 0,
                inputUnits: 0,
                outputUnits: 0,
                inputTokens: 0,
                outputTokens: 0,
                tokenRunCount: 0
            )
            aggregate.runCount += 1
            aggregate.inputUnits += event.inputUnits
            aggregate.outputUnits += event.outputUnits
            if event.inputTokens != nil || event.outputTokens != nil {
                aggregate.tokenRunCount += 1
                aggregate.inputTokens += max(0, event.inputTokens ?? 0)
                aggregate.outputTokens += max(0, event.outputTokens ?? 0)
            }
            grouped[key] = aggregate
        }

        return grouped.map { key, aggregate in
            StatsProviderUsage(
                stage: key.stage,
                providerId: key.providerId,
                model: key.model,
                runCount: aggregate.runCount,
                inputUnits: aggregate.inputUnits,
                outputUnits: aggregate.outputUnits,
                inputUnit: key.inputUnit,
                outputUnit: key.outputUnit,
                inputTokens: aggregate.inputTokens,
                outputTokens: aggregate.outputTokens,
                tokenRunCount: aggregate.tokenRunCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.runCount != rhs.runCount {
                return lhs.runCount > rhs.runCount
            }
            if lhs.stage != rhs.stage {
                return lhs.stage.rawValue < rhs.stage.rawValue
            }
            if lhs.providerId != rhs.providerId {
                return lhs.providerId < rhs.providerId
            }
            return lhs.model < rhs.model
        }
    }
}
