import SwiftUI

struct ActivityHeatmapView: View {
    let dailyWordCounts: [Date: Int]
    let dailySessionCounts: [Date: Int]
    @Binding var hoverHint: String?

    private static let cellSize: CGFloat = 8
    private static let cellSpacing: CGFloat = 2
    private static let cellRadius: CGFloat = 2
    private static let dayLabelWidth: CGFloat = 24
    private static let dayLabelGap: CGFloat = 4
    private static let weekCount = 52
    private static let daysPerWeek = 7

    private let calendar = Calendar.current
    private let today: Date
    private let grid: [[HeatmapDay?]]
    private let tiers: HeatmapTiers
    private let monthLabels: [MonthLabel]

    init(
        dailyWordCounts: [Date: Int],
        dailySessionCounts: [Date: Int],
        hoverHint: Binding<String?>
    ) {
        self.dailyWordCounts = dailyWordCounts
        self.dailySessionCounts = dailySessionCounts
        self._hoverHint = hoverHint

        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        self.today = todayStart

        let todayWeekday = cal.component(.weekday, from: todayStart) - 1
        let gridEnd = cal.date(byAdding: .day, value: 6 - todayWeekday, to: todayStart)!
        let gridStart = cal.date(byAdding: .day, value: -(Self.weekCount * Self.daysPerWeek - 1), to: gridEnd)!

        var columns: [[HeatmapDay?]] = []
        var cursor = gridStart
        for weekIndex in 0..<Self.weekCount {
            var column: [HeatmapDay?] = []
            for dayOfWeek in 0..<Self.daysPerWeek {
                let day = cal.startOfDay(for: cursor)
                if day > todayStart {
                    column.append(nil)
                } else {
                    let wordCount = dailyWordCounts[day] ?? 0
                    let sessionCount = dailySessionCounts[day] ?? 0
                    column.append(HeatmapDay(
                        id: day,
                        wordCount: wordCount,
                        sessionCount: sessionCount,
                        weekIndex: weekIndex,
                        dayOfWeek: dayOfWeek
                    ))
                }
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }
            columns.append(column)
        }
        self.grid = columns

        let nonZeroCounts = dailyWordCounts.values.filter { $0 > 0 }.sorted()
        self.tiers = HeatmapTiers(sortedNonZeroCounts: nonZeroCounts)

        var labels: [MonthLabel] = []
        var lastLabelWeek = -4
        for weekIndex in 0..<columns.count {
            guard let firstDay = columns[weekIndex].first(where: { $0 != nil })??.id else {
                continue
            }
            let month = cal.component(.month, from: firstDay)
            let day = cal.component(.day, from: firstDay)
            if day <= 7 && (weekIndex - lastLabelWeek) >= 3 {
                let abbreviation = cal.shortMonthSymbols[month - 1]
                labels.append(MonthLabel(
                    id: "\(weekIndex)-\(month)",
                    abbreviation: abbreviation,
                    weekIndex: weekIndex
                ))
                lastLabelWeek = weekIndex
            }
        }
        self.monthLabels = labels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            monthLabelRow
            HStack(alignment: .top, spacing: Self.dayLabelGap) {
                dayLabelsColumn
                gridView
            }
            legendRow
        }
    }

    private var monthLabelRow: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                ForEach(monthLabels) { label in
                    Text(label.abbreviation)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .offset(x: Self.dayLabelWidth + Self.dayLabelGap
                                + CGFloat(label.weekIndex) * (Self.cellSize + Self.cellSpacing))
                }
            }
        }
        .frame(height: 12)
    }

    private var dayLabelsColumn: some View {
        VStack(spacing: Self.cellSpacing) {
            ForEach(0..<Self.daysPerWeek, id: \.self) { dayOfWeek in
                Group {
                    if dayOfWeek == 1 {
                        Text("Mon")
                    } else if dayOfWeek == 3 {
                        Text("Wed")
                    } else if dayOfWeek == 5 {
                        Text("Fri")
                    } else {
                        Text("")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: Self.dayLabelWidth, height: Self.cellSize, alignment: .trailing)
            }
        }
    }

    private var gridView: some View {
        HStack(spacing: Self.cellSpacing) {
            ForEach(0..<grid.count, id: \.self) { weekIndex in
                VStack(spacing: Self.cellSpacing) {
                    ForEach(0..<Self.daysPerWeek, id: \.self) { dayOfWeek in
                        cellView(weekIndex: weekIndex, dayOfWeek: dayOfWeek)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(weekIndex: Int, dayOfWeek: Int) -> some View {
        if let day = grid[weekIndex][dayOfWeek] {
            let tier = tiers.tier(for: day.wordCount)
            let hint = hintText(for: day)
            RoundedRectangle(cornerRadius: Self.cellRadius)
                .fill(colorForTier(tier))
                .frame(width: Self.cellSize, height: Self.cellSize)
                .onHover { isHovering in
                    if isHovering {
                        hoverHint = hint
                    } else if hoverHint == hint {
                        hoverHint = nil
                    }
                }
        } else {
            Color.clear
                .frame(width: Self.cellSize, height: Self.cellSize)
        }
    }

    private var legendRow: some View {
        HStack(spacing: 4) {
            Spacer()
            Text("Less")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { tier in
                RoundedRectangle(cornerRadius: Self.cellRadius)
                    .fill(colorForTier(tier))
                    .frame(width: Self.cellSize, height: Self.cellSize)
            }
            Text("More")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func colorForTier(_ tier: Int) -> Color {
        switch tier {
        case 1: return Color(red: 143.0 / 255, green: 186.0 / 255, blue: 245.0 / 255)
        case 2: return Color(red: 84.0 / 255, green: 141.0 / 255, blue: 227.0 / 255)
        case 3: return Color(red: 46.0 / 255, green: 102.0 / 255, blue: 199.0 / 255)
        case 4: return Color(red: 26.0 / 255, green: 69.0 / 255, blue: 161.0 / 255)
        default: return Color.primary.opacity(0.04)
        }
    }

    private func hintText(for day: HeatmapDay) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let dateString = formatter.string(from: day.id)
        if day.wordCount == 0 {
            return "No activity on \(dateString)"
        }
        let sessions = day.sessionCount == 1 ? "1 session" : "\(day.sessionCount) sessions"
        return "\(day.wordCount) words, \(sessions) on \(dateString)"
    }
}

struct HeatmapDay: Identifiable {
    let id: Date
    let wordCount: Int
    let sessionCount: Int
    let weekIndex: Int
    let dayOfWeek: Int
}

struct HeatmapTiers {
    let thresholds: [Int]

    init(sortedNonZeroCounts: [Int]) {
        let count = sortedNonZeroCounts.count
        if count == 0 {
            thresholds = [0, 0, 0]
        } else {
            let p25 = sortedNonZeroCounts[count / 4]
            let p50 = sortedNonZeroCounts[count / 2]
            let p75 = sortedNonZeroCounts[count * 3 / 4]
            thresholds = [p25, p50, p75]
        }
    }

    func tier(for wordCount: Int) -> Int {
        guard wordCount > 0 else { return 0 }
        if wordCount > thresholds[2] { return 4 }
        if wordCount > thresholds[1] { return 3 }
        if wordCount > thresholds[0] { return 2 }
        return 1
    }
}

struct MonthLabel: Identifiable {
    let id: String
    let abbreviation: String
    let weekIndex: Int
}
