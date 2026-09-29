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

enum StatsRange: String, CaseIterable, Identifiable {
    case week
    case month
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week:
            return "7 days"
        case .month:
            return "30 days"
        case .all:
            return "All"
        }
    }
}

/// Words in one chart bar: a day for the 7 and 30 day ranges, a month for all time.
struct StatsBucket: Equatable {
    let start: Date
    let words: Int
}

/// Totals for one range. Each session counts once, with its latest transcription, so retries do not
/// add the same words twice.
struct StatsRangeSummary: Equatable {
    let range: StatsRange
    let start: Date?
    let words: Int
    let recordingSeconds: Double
    let wordsPerMinute: Double?
    let buckets: [StatsBucket]
    let sessions: Int
    /// Transcribed on this Mac and never polished.
    let localOnlySessions: Int
    /// Transcribed on this Mac, then the text went to a cloud polish provider.
    let textToCloudSessions: Int
    /// Audio went to a cloud transcription provider.
    let audioToCloudSessions: Int
    let localTranscriptionModels: [String]
    let cloudTranscriptionProviders: [String]
    let cloudPolishProviders: [String]
    let averageLocalTranscriptionMs: Double?

    static func empty(_ range: StatsRange) -> StatsRangeSummary {
        StatsRangeSummary(
            range: range,
            start: nil,
            words: 0,
            recordingSeconds: 0,
            wordsPerMinute: nil,
            buckets: [],
            sessions: 0,
            localOnlySessions: 0,
            textToCloudSessions: 0,
            audioToCloudSessions: 0,
            localTranscriptionModels: [],
            cloudTranscriptionProviders: [],
            cloudPolishProviders: [],
            averageLocalTranscriptionMs: nil
        )
    }
}

final class StatsStore {
    private struct EventsFileState: Equatable {
        let size: Int
        let modificationDate: Date?
    }

    private let eventsURL: URL
    private let fileManager: FileManager
    private var cachedEvents: [StatsEvent]?
    private var cachedFileState: EventsFileState?

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

        let stateBeforeAppend = eventsFileState()
        let canExtendCache = cachedEvents != nil && cachedFileState == stateBeforeAppend

        if fileManager.fileExists(atPath: eventsURL.path) {
            let handle = try FileHandle(forWritingTo: eventsURL)
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: eventsURL, options: .atomic)
        }

        if canExtendCache {
            cachedEvents?.append(event)
            cachedFileState = eventsFileState()
        } else {
            cachedEvents = nil
            cachedFileState = nil
        }
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

        let countedTranscriptions = Array(Self.latestTranscriptionPerSession(transcriptionEvents).values)
        let transcriptionWordEvents = countedTranscriptions.filter { $0.outputUnit == .words }
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

        let totalRecordingMs = countedTranscriptions.reduce(0) { partial, event in
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
        let averageRecordingDurationSeconds: Double? = countedTranscriptions.count > 0
            ? totalRecordingDurationSeconds / Double(countedTranscriptions.count) : nil

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

    func loadRangeSummaries(now: Date = Date(), calendar: Calendar = .current) -> [StatsRange: StatsRangeSummary] {
        let events = loadEvents()
        var summaries: [StatsRange: StatsRangeSummary] = [:]
        for range in StatsRange.allCases {
            summaries[range] = Self.rangeSummary(range, events: events, now: now, calendar: calendar)
        }
        return summaries
    }

    /// How long transcription and polish took for one session, from its latest runs.
    func processingDurations(for sessionId: UUID) -> (transcriptionMs: Int?, polishMs: Int?) {
        let events = loadEvents().filter { $0.sessionId == sessionId }
        let latestTranscription = events.filter { $0.stage == .transcription }.max(by: { $0.timestamp < $1.timestamp })
        let latestPolish = events.filter { $0.stage == .polish }.max(by: { $0.timestamp < $1.timestamp })
        return (latestTranscription?.processingDurationMs, latestPolish?.processingDurationMs)
    }

    static func rangeSummary(
        _ range: StatsRange,
        events: [StatsEvent],
        now: Date,
        calendar: Calendar
    ) -> StatsRangeSummary {
        let today = calendar.startOfDay(for: now)
        let latestBySession = latestTranscriptionPerSession(events.filter { $0.stage == .transcription })
        let firstActiveDay = latestBySession.values.map { calendar.startOfDay(for: $0.timestamp) }.min()

        let start: Date?
        switch range {
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: today)
        case .month:
            start = calendar.date(byAdding: .day, value: -29, to: today)
        case .all:
            start = firstActiveDay
        }

        let counted = latestBySession.values.filter { event in
            guard let start else { return false }
            return event.timestamp >= start
        }
        guard let start, !counted.isEmpty else {
            return StatsRangeSummary(
                range: range,
                start: start,
                words: 0,
                recordingSeconds: 0,
                wordsPerMinute: nil,
                buckets: buckets(for: range, start: start ?? today, today: today, wordEvents: [], calendar: calendar),
                sessions: 0,
                localOnlySessions: 0,
                textToCloudSessions: 0,
                audioToCloudSessions: 0,
                localTranscriptionModels: [],
                cloudTranscriptionProviders: [],
                cloudPolishProviders: [],
                averageLocalTranscriptionMs: nil
            )
        }

        let polishedSessions = Set(events.filter { $0.stage == .polish }.map(\.sessionId))
        let polishProvidersBySession = Dictionary(grouping: events.filter { $0.stage == .polish }, by: \.sessionId)
        let localIDs = ProviderModelCatalog.localTranscriptionProviderIDs

        var localOnly = 0
        var textToCloud = 0
        var audioToCloud = 0
        var localModels: [String: Int] = [:]
        var cloudTranscription: [String: Int] = [:]
        var cloudPolish: [String: Int] = [:]
        for event in counted {
            let isLocal = localIDs.contains(event.providerId)
            if isLocal {
                localModels[event.model, default: 0] += 1
            } else {
                cloudTranscription[event.providerId, default: 0] += 1
            }
            let polished = polishedSessions.contains(event.sessionId)
            if polished {
                for polish in polishProvidersBySession[event.sessionId] ?? [] {
                    cloudPolish[polish.providerId, default: 0] += 1
                }
            }
            if !isLocal {
                audioToCloud += 1
            } else if polished {
                textToCloud += 1
            } else {
                localOnly += 1
            }
        }

        let wordEvents = counted.filter { $0.outputUnit == .words }
        let words = Int(wordEvents.reduce(0.0) { $0 + $1.outputUnits }.rounded())
        let recordingMs = counted.reduce(0) { $0 + max(0, $1.recordingDurationMs ?? 0) }
        let minutes = Double(recordingMs) / 60_000.0
        let localDurations = counted
            .filter { localIDs.contains($0.providerId) }
            .compactMap(\.processingDurationMs)

        return StatsRangeSummary(
            range: range,
            start: start,
            words: words,
            recordingSeconds: Double(recordingMs) / 1000.0,
            wordsPerMinute: minutes > 0 ? Double(words) / minutes : nil,
            buckets: buckets(for: range, start: start, today: today, wordEvents: wordEvents, calendar: calendar),
            sessions: counted.count,
            localOnlySessions: localOnly,
            textToCloudSessions: textToCloud,
            audioToCloudSessions: audioToCloud,
            localTranscriptionModels: rankedKeys(localModels),
            cloudTranscriptionProviders: rankedKeys(cloudTranscription),
            cloudPolishProviders: rankedKeys(cloudPolish),
            averageLocalTranscriptionMs: localDurations.isEmpty
                ? nil : Double(localDurations.reduce(0, +)) / Double(localDurations.count)
        )
    }

    /// The latest transcription run of each session. Retries replace earlier runs.
    static func latestTranscriptionPerSession(_ transcriptionEvents: [StatsEvent]) -> [UUID: StatsEvent] {
        var latest: [UUID: StatsEvent] = [:]
        for event in transcriptionEvents {
            if let existing = latest[event.sessionId], existing.timestamp >= event.timestamp {
                continue
            }
            latest[event.sessionId] = event
        }
        return latest
    }

    private static func buckets(
        for range: StatsRange,
        start: Date,
        today: Date,
        wordEvents: [StatsEvent],
        calendar: Calendar
    ) -> [StatsBucket] {
        switch range {
        case .week, .month:
            var wordsByDay: [Date: Int] = [:]
            for event in wordEvents {
                wordsByDay[calendar.startOfDay(for: event.timestamp), default: 0] += Int(event.outputUnits.rounded())
            }
            let dayCount = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
            return (0..<max(dayCount, 0)).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                return StatsBucket(start: day, words: wordsByDay[day] ?? 0)
            }
        case .all:
            func monthStart(_ date: Date) -> Date {
                calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            }
            var wordsByMonth: [Date: Int] = [:]
            for event in wordEvents {
                wordsByMonth[monthStart(event.timestamp), default: 0] += Int(event.outputUnits.rounded())
            }
            let currentMonth = monthStart(today)
            let firstMonth = max(
                monthStart(start),
                calendar.date(byAdding: .month, value: -11, to: currentMonth) ?? currentMonth
            )
            let monthCount = (calendar.dateComponents([.month], from: firstMonth, to: currentMonth).month ?? 0) + 1
            return (0..<max(monthCount, 1)).compactMap { offset in
                guard let month = calendar.date(byAdding: .month, value: offset, to: firstMonth) else { return nil }
                return StatsBucket(start: month, words: wordsByMonth[month] ?? 0)
            }
        }
    }

    private static func rankedKeys(_ counts: [String: Int]) -> [String] {
        counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        .map(\.key)
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
        let currentState = eventsFileState()
        if let cachedEvents, cachedFileState == currentState {
            return cachedEvents
        }

        guard currentState != nil,
              let content = try? Data(contentsOf: eventsURL) else {
            cachedEvents = []
            cachedFileState = nil
            return []
        }

        let events = content
            .split(separator: 0x0A)
            .compactMap { line in
                try? Self.decoder.decode(StatsEvent.self, from: Data(line))
            }
        cachedEvents = events
        cachedFileState = currentState
        return events
    }

    private func eventsFileState() -> EventsFileState? {
        guard fileManager.fileExists(atPath: eventsURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: eventsURL.path),
              let size = (attributes[.size] as? NSNumber)?.intValue else {
            return nil
        }
        return EventsFileState(size: size, modificationDate: attributes[.modificationDate] as? Date)
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
