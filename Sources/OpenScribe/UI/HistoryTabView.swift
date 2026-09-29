import AppKit
import SwiftUI

/// Sessions of one calendar day, newest first.
struct HistoryDayGroup: Identifiable, Equatable {
    let day: Date
    let title: String
    let entries: [SessionHistoryEntry]

    var id: Date { day }

    static func groups(
        _ entries: [SessionHistoryEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HistoryDayGroup] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var order: [Date] = []
        var byDay: [Date: [SessionHistoryEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            if byDay[day] == nil {
                order.append(day)
            }
            byDay[day, default: []].append(entry)
        }
        return order.map { day in
            let title: String
            if day == today {
                title = "Today"
            } else if day == yesterday {
                title = "Yesterday"
            } else {
                let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: today)
                title = (sameYear ? dayFormatter : dayWithYearFormatter).string(from: day)
            }
            return HistoryDayGroup(day: day, title: title, entries: byDay[day] ?? [])
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

    private static let dayWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMMyyyy")
        return formatter
    }()
}

extension SessionHistoryEntry {
    var transcribedLocally: Bool {
        ProviderModelCatalog.isLocalTranscriptionProvider(sttProvider)
    }

    /// True when audio or text left the Mac for this session.
    var usedCloud: Bool {
        guard state == .completed, !hadNoSpeech else { return false }
        return !transcribedLocally || polishRan
    }
}

struct HistoryTabView: View {
    @EnvironmentObject private var shell: AppShell
    @ObservedObject var playback: AudioPlaybackManager
    @Binding var hoverHint: String?

    @State private var selectedID: UUID?
    @State private var selectionMode = false
    @State private var checkedIDs: Set<UUID> = []
    @State private var pendingDelete: [SessionHistoryEntry] = []

    private var entries: [SessionHistoryEntry] { shell.visibleHistorySessions }

    private var selectedEntry: SessionHistoryEntry? {
        entries.first(where: { $0.id == selectedID }) ?? entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                emptyState
            } else {
                list
                if selectionMode {
                    selectionBar
                } else if let entry = selectedEntry {
                    actionBar(for: entry)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .popoverCard()
        .onChange(of: shell.historySessions) { _, sessions in
            let valid = Set(sessions.map(\.id))
            checkedIDs = checkedIDs.intersection(valid)
            if let selectedID, !valid.contains(selectedID) {
                self.selectedID = nil
            }
        }
        .confirmationDialog(
            pendingDelete.count == 1 ? "Move this session to the Trash?" : "Move \(pendingDelete.count) sessions to the Trash?",
            isPresented: Binding(
                get: { !pendingDelete.isEmpty },
                set: { if !$0 { pendingDelete = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingDelete.count == 1 ? "Move to Trash" : "Move \(pendingDelete.count) to Trash", role: .destructive) {
                shell.deleteHistorySessions(pendingDelete)
                checkedIDs.subtract(pendingDelete.map(\.id))
                if checkedIDs.isEmpty {
                    selectionMode = false
                }
                pendingDelete = []
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = []
            }
        } message: {
            Text("You can put sessions back from the Trash in Finder.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(PopoverPalette.muted)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PopoverPalette.subtle))
            Text("No sessions yet. Your recordings show up here.")
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                ForEach(HistoryDayGroup.groups(entries)) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            row(entry)
                        }
                    } header: {
                        dayHeader(group)
                    }
                }
                if shell.historyCanLoadMore {
                    Button(shell.historyIsLoading ? "Loading…" : "Show more") {
                        shell.loadMoreHistorySessions(mode: .next25)
                    }
                    .buttonStyle(PopoverButtonStyle())
                    .disabled(shell.historyIsLoading)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [PopoverPalette.card.opacity(0), PopoverPalette.card], startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
                .allowsHitTesting(false)
        }
    }

    private func dayHeader(_ group: HistoryDayGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(group.entries.count == 1 ? "1 session" : "\(group.entries.count) sessions")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(PopoverPalette.muted)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .padding(.horizontal, -8)
        )
    }

    private func row(_ entry: SessionHistoryEntry) -> some View {
        let isSelected = !selectionMode && entry.id == selectedEntry?.id
        let isChecked = checkedIDs.contains(entry.id)
        return HStack(alignment: entry.state == .failed || entry.hadNoSpeech ? .center : .top, spacing: 12) {
            if selectionMode {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isChecked ? Color.primary : PopoverPalette.muted)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(PopoverFormat.time(entry.createdAt))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                if let durationMs = entry.durationMs {
                    Text(PopoverFormat.clock(seconds: Double(durationMs) / 1000))
                        .font(.system(size: 12))
                        .foregroundStyle(PopoverPalette.muted)
                }
            }
            .monospacedDigit()
            .frame(width: 62, alignment: .leading)

            rowContent(entry)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.usedCloud {
                Image(systemName: "cloud")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PopoverPalette.cloud)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(PopoverPalette.cloudTint))
                    .help(entry.transcribedLocally ? "Text went to the cloud to polish" : "Audio went to the cloud to transcribe")
            }
        }
        .padding(10)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected || isChecked ? PopoverPalette.selection : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            if selectionMode {
                if isChecked {
                    checkedIDs.remove(entry.id)
                } else {
                    checkedIDs.insert(entry.id)
                }
            } else {
                selectedID = entry.id
            }
        }
        .accessibilityElement(children: entry.state == .failed ? .contain : .combine)
        .accessibilityAddTraits(isSelected || isChecked ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func rowContent(_ entry: SessionHistoryEntry) -> some View {
        if entry.state == .failed {
            HStack(spacing: 10) {
                Text(failureText(entry))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Retry") {
                    shell.retryHistorySession(entry)
                }
                .buttonStyle(PopoverButtonStyle())
                .disabled(!shell.canRunHistoryProcessingActions)
                .accessibilityLabel("Retry the \(PopoverFormat.time(entry.createdAt)) session")
            }
        } else if entry.hadNoSpeech {
            Text("No speech detected")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.75))
        } else if entry.previewText.isEmpty {
            Text("No transcript text")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.75))
        } else {
            Text(entry.previewText)
                .font(.system(size: 13))
                .lineSpacing(2)
                .lineLimit(2)
        }
    }

    private func failureText(_ entry: SessionHistoryEntry) -> String {
        guard let error = entry.lastError?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty else {
            return "Not transcribed."
        }
        let firstSentence = error.split(separator: "\n").first.map(String.init) ?? error
        return "Not transcribed. \(firstSentence)"
    }

    // MARK: Bottom bars

    private func actionBar(for entry: SessionHistoryEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(PopoverFormat.time(entry.createdAt))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text("·").foregroundStyle(PopoverPalette.muted)
                    Image(systemName: entry.usedCloud ? "cloud.fill" : "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.usedCloud ? PopoverPalette.cloud : PopoverPalette.local)
                    Text(routeSummary(entry))
                        .fontWeight(.semibold)
                        .foregroundStyle(entry.usedCloud ? PopoverPalette.cloud : PopoverPalette.local)
                }
                Text(engineSummary(entry))
                    .foregroundStyle(PopoverPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)

            if let audioURL = audioURL(for: entry) {
                Button {
                    playback.toggle(url: audioURL)
                } label: {
                    Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill")
                }
                .buttonStyle(PopoverIconButtonStyle(circular: true))
                .accessibilityLabel(playback.isPlaying ? "Stop playback" : "Play the \(PopoverFormat.time(entry.createdAt)) recording")
            }

            Button {
                shell.copyText(shell.historyTranscriptText(entry), message: "Copied")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(PopoverButtonStyle(kind: .primary))
            .disabled(entry.previewText.isEmpty)

            Menu {
                Button("Open in Live") {
                    if shell.openHistorySession(entry) {
                        shell.selectPopoverTab(.live)
                    }
                }
                .disabled(!shell.canRunHistoryProcessingActions)
                Button("Transcribe Again") {
                    shell.retryHistorySession(entry)
                }
                .disabled(!shell.canRunHistoryProcessingActions || audioURL(for: entry) == nil)
                Button("Reveal in Finder") {
                    shell.revealHistorySessionInFinder(entry)
                }
                Divider()
                Button("Select Several…") {
                    selectionMode = true
                    checkedIDs = [entry.id]
                }
                Button("Move to Trash…", role: .destructive) {
                    pendingDelete = [entry]
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .popoverMenuButton()
            .accessibilityLabel("More actions for the \(PopoverFormat.time(entry.createdAt)) session")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(PopoverPalette.hairline).frame(height: 1)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 8) {
            Text(checkedIDs.count == 1 ? "1 selected" : "\(checkedIDs.count) selected")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
            Spacer()
            Button("Select All") {
                checkedIDs = Set(entries.map(\.id))
            }
            .buttonStyle(PopoverButtonStyle())
            Button("Move to Trash…") {
                pendingDelete = entries.filter { checkedIDs.contains($0.id) }
            }
            .buttonStyle(PopoverButtonStyle())
            .disabled(checkedIDs.isEmpty)
            Button("Done") {
                selectionMode = false
                checkedIDs = []
            }
            .buttonStyle(PopoverButtonStyle(kind: .primary))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(PopoverPalette.hairline).frame(height: 1)
        }
    }

    private func routeSummary(_ entry: SessionHistoryEntry) -> String {
        if !entry.transcribedLocally {
            return "Audio went to \(ProviderNames.display(entry.sttProvider))"
        }
        if entry.polishRan {
            return "Text went to \(ProviderNames.display(entry.polishProvider))"
        }
        return "Stayed on this Mac"
    }

    private func engineSummary(_ entry: SessionHistoryEntry) -> String {
        let transcription = shell.modelManager.asset(for: entry.sttModel)?.displayName
            ?? "\(ProviderNames.display(entry.sttProvider)) \(ProviderNames.shortModel(entry.sttModel))"
        if entry.polishRan {
            return "\(transcription) · \(ProviderNames.display(entry.polishProvider)) \(ProviderNames.shortModel(entry.polishModel))"
        }
        return "\(transcription) · polish off"
    }

    private func audioURL(for entry: SessionHistoryEntry) -> URL? {
        let url = entry.folderURL.appendingPathComponent("audio.m4a")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
