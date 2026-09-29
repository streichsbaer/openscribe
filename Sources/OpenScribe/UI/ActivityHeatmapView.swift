import SwiftUI

/// A year of activity, one square per day, in five ink tones. Today is outlined.
struct ActivityHeatmapView: View {
    let dailyWordCounts: [Date: Int]

    private static let weekCount = 52
    private static let cellHeight: CGFloat = 7
    private static let spacing: CGFloat = 2

    private let calendar = Calendar.current
    private let today: Date
    private let firstDay: Date
    private let thresholds: [Int]

    init(dailyWordCounts: [Date: Int], now: Date = Date()) {
        self.dailyWordCounts = dailyWordCounts
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        self.today = today
        let weekday = calendar.component(.weekday, from: today) - 1
        let lastColumnStart = calendar.date(byAdding: .day, value: -weekday, to: today) ?? today
        self.firstDay = calendar.date(byAdding: .day, value: -7 * (Self.weekCount - 1), to: lastColumnStart) ?? today
        self.thresholds = Self.levelThresholds(dailyWordCounts.values.filter { $0 > 0 }.sorted())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            monthLabels
            grid
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(activeDayCount) active days in the last year")
    }

    var activeDayCount: Int {
        dailyWordCounts.filter { $0.key >= firstDay && $0.key <= today && $0.value > 0 }.count
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(0..<Self.weekCount, id: \.self) { week in
                VStack(spacing: Self.spacing) {
                    ForEach(0..<7, id: \.self) { dayOfWeek in
                        cell(for: date(week: week, day: dayOfWeek))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for date: Date) -> some View {
        if date > today {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.cellHeight)
        } else {
            let words = dailyWordCounts[date] ?? 0
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Self.fill(level: level(for: words)))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Color.primary, lineWidth: date == today ? 1.5 : 0)
                )
                .frame(maxWidth: .infinity)
                .frame(height: Self.cellHeight)
                .help(tooltip(date: date, words: words))
        }
    }

    private var monthLabels: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(0..<Self.weekCount, id: \.self) { week in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 13)
                    .overlay(alignment: .leading) {
                        if let label = monthLabel(forWeek: week) {
                            Text(label)
                                .font(.system(size: 11))
                                .foregroundStyle(PopoverPalette.muted)
                                .fixedSize()
                        }
                    }
            }
        }
    }

    private func monthLabel(forWeek week: Int) -> String? {
        let start = date(week: week, day: 0)
        guard calendar.component(.day, from: start) <= 7, week <= Self.weekCount - 4 else {
            return nil
        }
        let previous = (max(0, week - 3)..<week).contains { calendar.component(.day, from: date(week: $0, day: 0)) <= 7 }
        guard !previous else { return nil }
        return calendar.shortMonthSymbols[calendar.component(.month, from: start) - 1]
    }

    private func date(week: Int, day: Int) -> Date {
        calendar.date(byAdding: .day, value: week * 7 + day, to: firstDay) ?? firstDay
    }

    private func level(for words: Int) -> Int {
        guard words > 0 else { return 0 }
        return 1 + thresholds.filter { words > $0 }.count
    }

    private func tooltip(date: Date, words: Int) -> String {
        let day = Self.dateFormatter.string(from: date)
        return words == 0 ? "No dictation on \(day)" : "\(PopoverFormat.number(words)) words on \(day)"
    }

    static func fill(level: Int) -> Color {
        switch level {
        case 0:
            return PopoverPalette.subtle
        case 1:
            return Color.primary.opacity(0.22)
        case 2:
            return Color.primary.opacity(0.42)
        case 3:
            return Color.primary.opacity(0.64)
        default:
            return Color.primary.opacity(0.9)
        }
    }

    /// Splits active days into four even groups by word count.
    private static func levelThresholds(_ sorted: [Int]) -> [Int] {
        guard !sorted.isEmpty else { return [] }
        return [0.25, 0.5, 0.75].map { sorted[min(sorted.count - 1, Int(Double(sorted.count) * $0))] }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
