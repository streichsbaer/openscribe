import SwiftUI

struct StatsTabView: View {
    @EnvironmentObject private var shell: AppShell
    @Binding var hoverHint: String?

    @State private var range: StatsRange = .week
    @State private var showDetails = false

    private var summary: StatsRangeSummary {
        shell.statsRangeSummaries[range] ?? .empty(range)
    }

    var body: some View {
        if shell.statsSummary.totalEvents == 0 {
            VStack(spacing: 10) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PopoverPalette.muted)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PopoverPalette.subtle))
                Text("No stats yet. Finish a recording to start.")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .popoverCard()
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    heroCard
                    activityCard
                    whereCard
                    lastRunRow
                    if showDetails {
                        detailsCard
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.automatic)
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(rangeTitle)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(StatsRange.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                (Text(PopoverFormat.number(summary.words))
                    .font(.system(size: 34, weight: .semibold))
                    + Text(" words")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(PopoverPalette.muted))
                    .monospacedDigit()
                if summary.recordingSeconds > 0 {
                    Text(speakingLine)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.8))
                }
            }

            chart
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .popoverCard()
    }

    private var rangeTitle: String {
        guard let start = summary.start else { return "No dictation yet" }
        switch range {
        case .week, .month:
            return "\(Self.dayFormatter.string(from: start)) to \(Self.dayFormatter.string(from: Date()))"
        case .all:
            return "Since \(Self.monthYearFormatter.string(from: start))"
        }
    }

    private var speakingLine: String {
        var line = "\(PopoverFormat.speaking(seconds: summary.recordingSeconds)) of speaking"
        if let wpm = summary.wordsPerMinute {
            line += " · \(Int(wpm.rounded())) wpm"
        }
        return line
    }

    @ViewBuilder
    private var chart: some View {
        let buckets = summary.buckets
        let maxWords = max(1, buckets.map(\.words).max() ?? 1)
        switch range {
        case .week:
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                    let isToday = index == buckets.count - 1
                    VStack(spacing: 5) {
                        Text(PopoverFormat.number(bucket.words))
                            .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isToday ? Color.primary : Color.primary.opacity(0.75))
                        bar(words: bucket.words, maxWords: maxWords, height: 56, isToday: isToday, cornerRadius: 6)
                            .frame(maxWidth: 34)
                        Text(isToday ? "Today" : Self.weekdayFormatter.string(from: bucket.start))
                            .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? Color.primary : PopoverPalette.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        case .month, .all:
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: range == .month ? 3 : 8) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                        bar(
                            words: bucket.words,
                            maxWords: maxWords,
                            height: 72,
                            isToday: index == buckets.count - 1,
                            cornerRadius: 3
                        )
                        .frame(maxWidth: .infinity)
                        .help("\(PopoverFormat.number(bucket.words)) words, \(range == .month ? Self.dayFormatter.string(from: bucket.start) : Self.monthYearFormatter.string(from: bucket.start))")
                    }
                }
                .frame(height: 72, alignment: .bottom)
                HStack {
                    if let first = buckets.first {
                        Text(range == .month ? Self.dayFormatter.string(from: first.start) : Self.monthFormatter.string(from: first.start))
                    }
                    Spacer()
                    Text(range == .month ? "Today" : "This month")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.primary)
                }
                .font(.system(size: 12))
                .foregroundStyle(PopoverPalette.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Words per \(range == .month ? "day" : "month"), highest \(PopoverFormat.number(maxWords))")
        }
    }

    private func bar(words: Int, maxWords: Int, height: CGFloat, isToday: Bool, cornerRadius: CGFloat) -> some View {
        let barHeight = words == 0 ? 4 : max(6, height * CGFloat(words) / CGFloat(maxWords))
        return RoundedRectangle(cornerRadius: min(cornerRadius, barHeight / 2), style: .continuous)
            .fill(words == 0 ? PopoverPalette.subtle : (isToday ? Color.primary : Color.primary.opacity(0.5)))
            .frame(height: barHeight)
    }

    // MARK: Activity

    private var activityCard: some View {
        let heatmap = ActivityHeatmapView(dailyWordCounts: shell.statsSummary.dailyWordCounts)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                (Text(streakText).fontWeight(.semibold)
                    + Text(" · longest \(shell.statsSummary.longestActiveDayStreak)").foregroundColor(.primary.opacity(0.75)))
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
            heatmap
            HStack(spacing: 4) {
                Text("\(heatmap.activeDayCount) active days this year")
                    .font(.system(size: 12))
                    .foregroundStyle(PopoverPalette.muted)
                Spacer()
                Text("Less")
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(ActivityHeatmapView.fill(level: level))
                        .frame(width: 9, height: 9)
                }
                Text("More")
            }
            .font(.system(size: 11))
            .foregroundStyle(PopoverPalette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .popoverCard(radius: 16, elevated: false)
    }

    private var streakText: String {
        let streak = shell.statsSummary.currentActiveDayStreak
        return streak == 1 ? "1 day streak" : "\(streak) day streak"
    }

    // MARK: Where your words went

    @ViewBuilder
    private var whereCard: some View {
        let summary = summary
        Group {
            if summary.sessions == 0 {
                Text("No sessions in this range.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if summary.localOnlySessions == summary.sessions {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PopoverPalette.local)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(PopoverPalette.localTint))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.sessions == 1 ? "The session stayed on this Mac" : "All \(PopoverFormat.number(summary.sessions)) sessions stayed on this Mac")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PopoverPalette.local)
                        Text(allLocalDetail(summary))
                            .font(.system(size: 12))
                            .foregroundStyle(PopoverPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                mixedRoutes(summary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .popoverCard(radius: 16, elevated: false)
        .accessibilityElement(children: .combine)
    }

    private func allLocalDetail(_ summary: StatsRangeSummary) -> String {
        let model = summary.localTranscriptionModels.first.flatMap { shell.modelManager.asset(for: $0)?.displayName } ?? "A local model"
        var detail = summary.sessions == 1 ? "\(model) transcribed it" : "\(model) transcribed each"
        if let average = summary.averageLocalTranscriptionMs {
            detail += " in \(PopoverFormat.processing(ms: Int(average.rounded()))) on average"
        }
        detail += "."
        detail += shell.settings.polishEnabled ? " No text went to the cloud." : " Polish is off."
        return detail
    }

    private func mixedRoutes(_ summary: StatsRangeSummary) -> some View {
        let transcribedLocally = summary.localOnlySessions + summary.textToCloudSessions
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PopoverPalette.local)
                if summary.audioToCloudSessions == 0 {
                    (Text("All \(PopoverFormat.number(summary.sessions)) sessions transcribed on this Mac.")
                        .fontWeight(.semibold)
                        .foregroundColor(PopoverPalette.local)
                        + Text(" Audio never left."))
                        .font(.system(size: 13))
                } else {
                    Text("\(PopoverFormat.number(transcribedLocally)) of \(PopoverFormat.number(summary.sessions)) sessions transcribed on this Mac.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PopoverPalette.local)
                }
            }

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    segment(count: summary.localOnlySessions, total: summary.sessions, width: proxy.size.width, color: PopoverPalette.local)
                    segment(count: summary.textToCloudSessions, total: summary.sessions, width: proxy.size.width, color: PopoverPalette.cloudFill)
                    segment(count: summary.audioToCloudSessions, total: summary.sessions, width: proxy.size.width, color: PopoverPalette.cloud)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            let percents = Self.wholePercents([summary.localOnlySessions, summary.textToCloudSessions, summary.audioToCloudSessions])
            VStack(alignment: .leading, spacing: 5) {
                legendRow(color: PopoverPalette.local, count: summary.localOnlySessions, percent: percents[0],
                          text: "stayed entirely on this Mac")
                if summary.textToCloudSessions > 0 {
                    legendRow(color: PopoverPalette.cloudFill, count: summary.textToCloudSessions, percent: percents[1],
                              text: "sent text to \(providerList(summary.cloudPolishProviders)) to polish")
                }
                if summary.audioToCloudSessions > 0 {
                    legendRow(color: PopoverPalette.cloud, count: summary.audioToCloudSessions, percent: percents[2],
                              text: "sent audio to \(providerList(summary.cloudTranscriptionProviders)) to transcribe")
                }
            }
        }
    }

    @ViewBuilder
    private func segment(count: Int, total: Int, width: CGFloat, color: Color) -> some View {
        if count > 0 {
            Rectangle()
                .fill(color)
                .frame(width: max(3, width * CGFloat(count) / CGFloat(max(total, 1))))
        }
    }

    /// Whole percentages that add up to 100, rounding the largest remainders up.
    static func wholePercents(_ counts: [Int]) -> [Int] {
        let total = counts.reduce(0, +)
        guard total > 0 else { return counts.map { _ in 0 } }
        let exact = counts.map { Double($0) * 100 / Double(total) }
        var percents = exact.map { Int($0) }
        let order = exact.indices.sorted { (exact[$0] - Double(percents[$0])) > (exact[$1] - Double(percents[$1])) }
        for index in order.prefix(100 - percents.reduce(0, +)) {
            percents[index] += 1
        }
        return percents
    }

    private func legendRow(color: Color, count: Int, percent: Int, text: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            (Text(PopoverFormat.number(count)).fontWeight(.semibold) + Text(" " + text))
                .font(.system(size: 12))
            Spacer()
            Text("\(percent)%")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(PopoverPalette.muted)
        }
    }

    private func providerList(_ providerIDs: [String]) -> String {
        let names = providerIDs.map(ProviderNames.display).reduce(into: [String]()) { names, name in
            if !names.contains(name) { names.append(name) }
        }
        return ListFormatter.localizedString(byJoining: names.isEmpty ? ["the cloud"] : names)
    }

    // MARK: Last run and details

    private var lastRunRow: some View {
        HStack(spacing: 8) {
            Text(lastRunText)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(PopoverPalette.muted)
                .lineLimit(1)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showDetails.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(showDetails ? "Fewer details" : "More details")
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityValue(showDetails ? "Expanded" : "Collapsed")
        }
        .padding(.horizontal, 4)
    }

    private var lastRunText: String {
        guard let event = shell.statsSummary.latestTranscriptionEvent else {
            return "No runs yet"
        }
        var text = "Last run: \(Int(event.outputUnits.rounded())) words"
        if let ms = event.processingDurationMs {
            text += " in \(PopoverFormat.processing(ms: ms))"
        }
        if let polish = shell.statsSummary.latestPolishEvent, polish.sessionId == event.sessionId,
           let polishMs = polish.processingDurationMs {
            text += ", polished in \(PopoverFormat.processing(ms: polishMs))"
        }
        return text + " at \(PopoverFormat.time(event.timestamp))"
    }

    private var detailsCard: some View {
        let stats = shell.statsSummary
        return VStack(alignment: .leading, spacing: 8) {
            detailRow("Words, all time", PopoverFormat.number(stats.spokenWords))
            detailRow("Sessions, all time", PopoverFormat.number(stats.sessionCount))
            detailRow("Transcription runs", "\(PopoverFormat.number(stats.transcriptionRuns)) including retries")
            detailRow("Longest streak", stats.longestActiveDayStreak == 1 ? "1 day" : "\(stats.longestActiveDayStreak) days")
            if let gap = stats.averageDaysBetweenActiveDays {
                detailRow("Average gap", String(format: "%.1f days between active days", gap))
            }
            if stats.polishRuns > 0 {
                detailRow("Polish runs", PopoverFormat.number(stats.polishRuns))
                detailRow("Polish word change", polishDelta(stats))
                if let average = stats.averagePolishProcessingMs {
                    detailRow("Average polish", PopoverFormat.processing(ms: Int(average.rounded())))
                }
            }
            if !stats.providerUsage.isEmpty {
                Text("Most used")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 4)
                ForEach(Array(stats.providerUsage.prefix(3))) { usage in
                    detailRow(
                        "\(usage.stage.displayLabel)",
                        "\(ProviderNames.display(usage.providerId)) \(ProviderNames.shortModel(usage.model)), \(PopoverFormat.number(usage.runCount)) runs"
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoverCard(radius: 16, elevated: false)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(PopoverPalette.muted)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
    }

    private func polishDelta(_ stats: StatsSummary) -> String {
        let sign = stats.polishDeltaWords > 0 ? "+" : ""
        var text = "\(sign)\(PopoverFormat.number(stats.polishDeltaWords)) words"
        if let percent = stats.polishDeltaPercent {
            text += String(format: " (%@%.1f%%)", percent > 0 ? "+" : "", percent)
        }
        return text
    }

    // MARK: Formatters

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter
    }()
}
