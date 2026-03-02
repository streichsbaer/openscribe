import AVFoundation
import Foundation
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var shell: AppShell
    @StateObject private var playbackManager = AudioPlaybackManager()
    @AppStorage("ui.transcriptPanelsExpanded") private var expandedTextPanels = false
    @State private var selectedRetryApproachID = ""
    @State private var selectedRetryPolishOptionID = ""
    @State private var retryTranscriptionFilter = ""
    @State private var retryPolishFilter = ""
    @State private var historySelectionMode = false
    @State private var selectedHistorySessionIDs: Set<UUID> = []
    @State private var pendingDeleteEntries: [SessionHistoryEntry] = []
    @State private var hoverHint: String?
    private let infoLabelWidth: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            mainTabBar

            if shell.selectedPopoverTab == .live {
                inputSection
                sessionSection
                textSection
            } else {
                historySection
            }

            footerSection
        }
        .padding(12)
        .frame(width: popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            syncPopoverSize()
            syncRetryPolishSelection()
            syncRetryTranscriptionSelection()
            if shell.selectedPopoverTab == .history {
                shell.refreshHistorySessions(preserveLoadedCount: true)
            }
        }
        .onChange(of: expandedTextPanels) { _, newValue in
            handleExpandedTextPanelsChanged(newValue)
        }
        .onChange(of: shell.selectedPopoverTab) { _, newValue in
            handleSelectedTabChanged(newValue)
        }
        .onChange(of: shell.settings.polishProviderID) { _, _ in
            syncRetryPolishSelection()
        }
        .onChange(of: shell.settings.polishModel) { _, _ in
            syncRetryPolishSelection()
        }
        .onChange(of: shell.settings.transcriptionProviderID) { _, _ in
            syncRetryTranscriptionSelection()
        }
        .onChange(of: shell.settings.transcriptionModel) { _, _ in
            syncRetryTranscriptionSelection()
        }
        .onChange(of: shell.rawTranscriptProviderID) { _, _ in
            syncRetryTranscriptionSelection()
        }
        .onChange(of: shell.rawTranscriptModel) { _, _ in
            syncRetryTranscriptionSelection()
        }
        .onChange(of: shell.historySessions) { _, sessions in
            let validIDs = Set(sessions.map(\.id))
            selectedHistorySessionIDs = selectedHistorySessionIDs.intersection(validIDs)
        }
        .confirmationDialog(
            historyDeleteConfirmationTitle,
            isPresented: Binding(
                get: { !pendingDeleteEntries.isEmpty },
                set: { newValue in
                    if !newValue {
                        pendingDeleteEntries = []
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(historyDeleteConfirmationActionLabel, role: .destructive) {
                shell.deleteHistorySessions(pendingDeleteEntries)
                clearHistorySelectionAfterDelete()
                pendingDeleteEntries = []
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteEntries = []
            }
        } message: {
            Text(historyDeleteConfirmationMessage)
        }
    }

    private var mainTabBar: some View {
        HStack {
            Spacer(minLength: 0)
            mainTabPicker
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var mainTabPicker: some View {
        Picker("Popover tab", selection: $shell.selectedPopoverTab) {
            Text("Live").tag(PopoverTabSelection.live)
            Text("History").tag(PopoverTabSelection.history)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 210)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Label("OpenScribe", systemImage: "waveform.badge.mic")
                .font(.headline)

            Spacer()

            stateChip
        }
    }

    private var inputSection: some View {
        card(title: "Input") {
            VStack(alignment: .leading, spacing: 8) {
                keyValueRow("Device", shell.currentSession?.metadata.inputDeviceName ?? AVAudioSessionBridge.defaultInputName)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Level")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.18))
                                .frame(height: 9)

                            Capsule()
                                .fill(shell.microphoneIndicatorColorName == "green" ? Color.green : Color.gray)
                                .frame(width: max(6, CGFloat(shell.meterLevel) * geometry.size.width), height: 9)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 9)
                }

                Text(permissionText)
                    .font(.caption)
                    .foregroundColor(shell.permissionState == .authorized ? .secondary : .orange)
            }
        }
    }

    private var sessionSection: some View {
        card(title: "Session") {
            VStack(alignment: .leading, spacing: 10) {
                keyValueRow("State", shell.sessionState.displayLabel)

                HStack(spacing: 8) {
                    Button(startStopButtonLabel) {
                        shell.toggleRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(startStopButtonDisabled)
                    .instantHint(startStopHelpText, hoverHint: $hoverHint)

                    if let audioURL = shell.currentSession?.paths.audioURL,
                       FileManager.default.fileExists(atPath: audioURL.path) {
                        Button(playbackManager.isPlaying ? "Stop Audio" : "Play Audio") {
                            playbackManager.toggle(url: audioURL)
                        }
                        .buttonStyle(.bordered)
                        .instantHint("Play or stop latest session audio", hoverHint: $hoverHint)
                    }

                    Button("Reveal") {
                        shell.revealCurrentSessionInFinder()
                    }
                    .buttonStyle(.bordered)
                    .instantHint("Reveal latest session in Finder", hoverHint: $hoverHint)
                }

                if let session = shell.currentSession {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(session.paths.folderURL.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 4)

                        Button {
                            shell.copyCurrentSessionPath()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .instantHint("Copy session path", hoverHint: $hoverHint)
                    }
                }
            }
        }
    }

    private var textSection: some View {
        card(title: "Text", trailing: {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedTextPanels.toggle()
                }
            } label: {
                Image(systemName: expandedTextPanels ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .instantHint(expandedTextPanels ? "Compact transcript panels" : "Expand transcript panels", hoverHint: $hoverHint)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                transcriptSubsection {
                    transcriptHeaderTitle(title: "Raw transcript", sourceSummary: rawSourceSummary)
                    rawTranscriptPanel

                    HStack(alignment: .center, spacing: 8) {
                        Text("Retry with another model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            shell.copyRawTranscript()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .instantHint(copyRawHelpText, hoverHint: $hoverHint)
                    }

                    HStack(alignment: .center, spacing: 8) {
                        TextField("Search provider/model", text: $retryTranscriptionFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: compactControls ? 160 : 190)

                        Picker("Transcriber", selection: $selectedRetryApproachID) {
                            ForEach(displayedRetryApproaches) { approach in
                                Text(approach.title)
                                    .tag(approach.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)

                        Button {
                            shell.retryTranscription(
                                temporaryProviderID: selectedRetryApproach.providerID,
                                temporaryModel: selectedRetryApproach.model
                            )
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!canRetryTranscription)
                        .instantHint("Rerun raw transcription using selected provider/model", hoverHint: $hoverHint)
                    }
                }

                transcriptSubsection {
                    transcriptHeaderTitle(title: "Polished transcript", sourceSummary: polishedSourceSummary)
                    ScrollView {
                        Text(polishedBodyText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: polishedPanelHeight)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack(alignment: .center, spacing: 8) {
                        Text("Retry with another model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            shell.copyLatestPolished()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .instantHint(copyPolishedHelpText, hoverHint: $hoverHint)
                    }

                    HStack(alignment: .center, spacing: 8) {
                        TextField("Search provider/model", text: $retryPolishFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: compactControls ? 160 : 190)
                            .disabled(!shell.settings.polishEnabled)

                        Picker("Polish retry option", selection: $selectedRetryPolishOptionID) {
                            ForEach(displayedRetryPolishOptions) { option in
                                Text(option.title)
                                    .tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .disabled(!shell.settings.polishEnabled)

                        Button {
                            shell.retryPolish(
                                temporaryProviderID: selectedRetryPolishOption.providerID,
                                temporaryModel: selectedRetryPolishOption.model
                            )
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(shell.rawTranscript.isEmpty || !shell.settings.polishEnabled)
                        .instantHint("Rerun polish using selected provider/model", hoverHint: $hoverHint)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        card(title: "History", trailing: {
            HStack(spacing: 6) {
                Button(historySelectionMode ? "Done" : "Select") {
                    historySelectionMode.toggle()
                    if !historySelectionMode {
                        selectedHistorySessionIDs.removeAll()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(shell.historyIsLoading || shell.visibleHistorySessions.isEmpty)
                .instantHint(historySelectionMode ? "Exit multi-select mode" : "Select multiple sessions", hoverHint: $hoverHint)

                Button {
                    shell.refreshHistorySessions(preserveLoadedCount: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(shell.historyIsLoading)
                .instantHint("Refresh session history", hoverHint: $hoverHint)
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                if shell.visibleHistorySessions.isEmpty {
                    Text("No sessions yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(shell.visibleHistorySessions) { entry in
                                historyRow(entry)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: historyListHeight)
                    .padding(.trailing, 2)
                }

                if historySelectionMode {
                    HStack(alignment: .center, spacing: 8) {
                        Text("\(selectedHistoryEntries.count) selected")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Select all visible") {
                            selectedHistorySessionIDs = Set(shell.visibleHistorySessions.map(\.id))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(shell.visibleHistorySessions.isEmpty || shell.historyIsLoading)

                        Button("Delete selected") {
                            guard !selectedHistoryEntries.isEmpty else {
                                return
                            }
                            pendingDeleteEntries = selectedHistoryEntries
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(selectedHistoryEntries.isEmpty || shell.historyIsLoading)
                    }
                }

                HStack(alignment: .center, spacing: 8) {
                    Text("Loaded \(shell.visibleHistorySessions.count) session(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if shell.historyCanLoadMore {
                        Menu {
                            ForEach(shell.historyLoadMoreModes) { mode in
                                Button(mode.actionLabel) {
                                    shell.loadMoreHistorySessions(mode: mode)
                                    if historySelectionMode {
                                        selectedHistorySessionIDs = selectedHistorySessionIDs.intersection(Set(shell.visibleHistorySessions.map(\.id)))
                                    }
                                }
                            }
                        } label: {
                            if shell.historyIsLoading {
                                Text("Loading...")
                            } else {
                                Text("Load more")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(shell.historyIsLoading)
                        .instantHint("Load additional history sessions", hoverHint: $hoverHint)
                    } else {
                        Text("All sessions loaded")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        HStack(alignment: .center) {
            statusText
                .lineLimit(2)

            Spacer()

            Button("Settings") {
                openSettings()
            }
            .buttonStyle(.bordered)
            .instantHint(settingsHelpText, hoverHint: $hoverHint)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let hoverHint {
            Text(hoverHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let hotkeyError = shell.hotkeyError {
            Text("Hotkey issue: \(hotkeyError)")
                .font(.caption)
                .foregroundColor(.orange)
        } else if let lastError = shell.lastError {
            Text(lastError)
                .font(.caption)
                .foregroundColor(.red)
        } else {
            Text(shell.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateChip: some View {
        switch shell.sessionState {
        case .recording:
            if let createdAt = shell.currentSession?.metadata.createdAt {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    stateChipLabel(
                        "Recording \(formattedDuration(Int(timeline.date.timeIntervalSince(createdAt))))",
                        color: .green
                    )
                }
            } else {
                stateChipLabel("Recording", color: .green)
            }
        case .transcribing:
            stateChipLabel("Transcribing \(formattedDuration(shell.transcribeElapsedSeconds))", color: .orange)
        case .polishing:
            stateChipLabel("Polishing \(formattedDuration(shell.polishElapsedSeconds))", color: .mint)
        default:
            stateChipLabel(shell.sessionState.displayLabel, color: stateChipColor)
        }
    }

    private func stateChipLabel(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private var stateChipColor: Color {
        switch shell.sessionState {
        case .recording:
            return .green
        case .transcribing, .finalizingAudio:
            return .orange
        case .polishing:
            return .mint
        case .failed:
            return .red
        case .completed:
            return .blue
        case .idle:
            return .gray
        }
    }

    private func historyRow(_ entry: SessionHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if historySelectionMode {
                    Button {
                        toggleHistorySelection(entry)
                    } label: {
                        Image(systemName: selectedHistorySessionIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                }

                Text(historyTimestamp(entry.createdAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                stateChipLabel(entry.state.displayLabel, color: historyStateColor(entry.state))
                Spacer(minLength: 0)

                if !historySelectionMode {
                    historyRowActions(entry)
                }
            }

            Text("\(providerDisplayName(for: entry.sttProvider)) / \(entry.sttModel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if entry.previewText.isEmpty {
                Text("No transcript text yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.previewText)
                    .font(.subheadline)
                    .lineLimit(expandedTextPanels ? 4 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onTapGesture {
            if historySelectionMode {
                toggleHistorySelection(entry)
            } else {
                openHistorySessionAndShowLive(entry)
            }
        }
    }

    private func historyRowActions(_ entry: SessionHistoryEntry) -> some View {
        HStack(spacing: 4) {
            Button {
                openHistorySessionAndShowLive(entry)
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .disabled(!shell.canRunHistoryProcessingActions)
            .instantHint("Load session in Live tab", hoverHint: $hoverHint)

            if let audioURL = historyAudioURL(for: entry) {
                Button {
                    playbackManager.toggle(url: audioURL)
                } label: {
                    Image(systemName: playbackManager.isPlaying ? "stop.circle" : "play.circle")
                }
                .buttonStyle(.borderless)
                .instantHint(playbackManager.isPlaying ? "Stop audio playback" : "Play session audio", hoverHint: $hoverHint)
            }

            Button {
                shell.revealHistorySessionInFinder(entry)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .instantHint("Reveal session folder in Finder", hoverHint: $hoverHint)

            Button(role: .destructive) {
                pendingDeleteEntries = [entry]
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .instantHint("Delete session", hoverHint: $hoverHint)
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func card<Content: View, Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.headline)
                Spacer()
                trailing()
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: infoLabelWidth, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissionText: String {
        switch shell.permissionState {
        case .authorized:
            return "Microphone permission granted"
        case .denied:
            return "No input: microphone permission denied"
        case .undetermined:
            return "Microphone permission not requested"
        }
    }

    private func openSettings() {
        shell.openSettingsWindow()
    }

    private func openHistorySessionAndShowLive(_ entry: SessionHistoryEntry) {
        if shell.openHistorySession(entry) {
            shell.selectedPopoverTab = .live
        }
    }

    private func syncPopoverSize() {
        shell.updatePopoverSize(
            selectedTab: shell.selectedPopoverTab,
            expandedTextPanels: expandedTextPanels
        )
    }

    private func handleExpandedTextPanelsChanged(_ newValue: Bool) {
        shell.updatePopoverSize(
            selectedTab: shell.selectedPopoverTab,
            expandedTextPanels: newValue
        )
    }

    private func handleSelectedTabChanged(_ newValue: PopoverTabSelection) {
        shell.updatePopoverSize(
            selectedTab: newValue,
            expandedTextPanels: expandedTextPanels
        )
        if newValue == .history {
            shell.refreshHistorySessions(preserveLoadedCount: true)
        }
    }

    private var polishedBodyText: String {
        if !shell.polishedTranscript.isEmpty {
            return shell.polishedTranscript
        }
        if shell.sessionState == .polishing {
            return "Polishing in progress..."
        }
        return "Polished transcript will appear here."
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let minutes = safeSeconds / 60
        let remainder = safeSeconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private var rawPanelHeight: CGFloat {
        panelHeight(hasContent: !rawPanelIsPlaceholder)
    }

    private var polishedPanelHeight: CGFloat {
        panelHeight(hasContent: !shell.polishedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func panelHeight(hasContent: Bool) -> CGFloat {
        if expandedTextPanels {
            return hasContent ? 220 : 150
        }
        return hasContent ? 110 : 78
    }

    private var compactControls: Bool {
        !expandedTextPanels
    }

    private func transcriptHeaderTitle(title: String, sourceSummary: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(sourceSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func transcriptSubsection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var rawTranscriptPanel: some View {
        ScrollView {
            Text(rawPanelText)
                .font(.body)
                .foregroundStyle(rawPanelIsPlaceholder ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(height: rawPanelHeight)
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var canRetryTranscription: Bool {
        guard let session = shell.currentSession else {
            return false
        }
        guard FileManager.default.fileExists(atPath: session.paths.audioURL.path) else {
            return false
        }
        switch shell.sessionState {
        case .recording, .finalizingAudio, .transcribing, .polishing:
            return false
        case .idle, .completed, .failed:
            return true
        }
    }

    private var startStopButtonLabel: String {
        switch shell.sessionState {
        case .recording:
            return "Stop (\(startStopHotkeyDisplay))"
        case .finalizingAudio, .transcribing, .polishing:
            return "Processing..."
        case .idle, .completed, .failed:
            return "Start (\(startStopHotkeyDisplay))"
        }
    }

    private var startStopHotkeyDisplay: String {
        HotkeyDisplay.string(for: shell.settings.startStopHotkey)
    }

    private var copyHotkeyDisplay: String {
        HotkeyDisplay.string(for: shell.settings.copyHotkey)
    }

    private var copyRawHotkeyDisplay: String {
        HotkeyDisplay.string(for: shell.settings.copyRawHotkey)
    }

    private var pasteHotkeyDisplay: String {
        HotkeyDisplay.string(for: shell.settings.pasteHotkey)
    }

    private var openSettingsHotkeyDisplay: String {
        HotkeyDisplay.string(for: shell.settings.openSettingsHotkey)
    }

    private var startStopHelpText: String {
        "Toggle recording (\(startStopHotkeyDisplay))"
    }

    private var copyPolishedHelpText: String {
        "Copy polished transcript (\(copyHotkeyDisplay)). Paste latest with \(pasteHotkeyDisplay) when Accessibility permission is granted."
    }

    private var copyRawHelpText: String {
        "Copy raw transcript (\(copyRawHotkeyDisplay))."
    }

    private var settingsHelpText: String {
        "Open Settings (\(openSettingsHotkeyDisplay)). Cmd+, works when OpenScribe is focused."
    }

    private var startStopButtonDisabled: Bool {
        switch shell.sessionState {
        case .finalizingAudio, .transcribing, .polishing:
            return true
        case .idle, .recording, .completed, .failed:
            return false
        }
    }

    private var retryApproaches: [RetryModelOption] {
        var options: [RetryModelOption] = localTranscriptionOptions()
        options.append(contentsOf: verifiedOptions(
            providerID: "openai_whisper",
            providerName: "OpenAI",
            models: shell.availableModels(for: "openai_whisper", usage: .transcription)
        ))
        options.append(contentsOf: verifiedOptions(
            providerID: "groq_whisper",
            providerName: "Groq",
            models: shell.availableModels(for: "groq_whisper", usage: .transcription)
        ))
        options.append(contentsOf: verifiedOptions(
            providerID: "openrouter_transcribe",
            providerName: "OpenRouter",
            models: shell.availableModels(for: "openrouter_transcribe", usage: .transcription)
        ))
        options.append(contentsOf: verifiedOptions(
            providerID: "gemini_transcribe",
            providerName: "Gemini",
            models: shell.availableModels(for: "gemini_transcribe", usage: .transcription)
        ))
        return options.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
    }

    private var displayedRetryApproaches: [RetryModelOption] {
        optionsFilteredByText(
            retryApproaches,
            filter: retryTranscriptionFilter,
            includeID: selectedRetryApproachID
        )
    }

    private var selectedRetryApproach: RetryModelOption {
        retryApproaches.first(where: { $0.id == selectedRetryApproachID })
            ?? displayedRetryApproaches.first
            ?? RetryModelOption(id: "fallback-transcription", title: "Unavailable", providerID: shell.settings.transcriptionProviderID, model: shell.settings.transcriptionModel)
    }

    private var rawSourceSummary: String {
        sourceSummary(
            transcript: shell.rawTranscript,
            providerID: shell.rawTranscriptProviderID,
            model: shell.rawTranscriptModel,
            fallbackProviderID: shell.currentSession?.metadata.sttProvider,
            fallbackModel: shell.currentSession?.metadata.sttModel
        )
    }

    private var polishedSourceSummary: String {
        sourceSummary(
            transcript: shell.polishedTranscript,
            providerID: shell.polishedTranscriptProviderID,
            model: shell.polishedTranscriptModel,
            fallbackProviderID: shell.currentSession?.metadata.polishProvider,
            fallbackModel: shell.currentSession?.metadata.polishModel
        )
    }

    private var retryPolishOptions: [RetryModelOption] {
        guard shell.settings.polishEnabled else {
            return [RetryModelOption(
                id: "\(shell.settings.polishProviderID)|\(shell.settings.polishModel)",
                title: "\(providerDisplayName(for: shell.settings.polishProviderID)) / \(shell.settings.polishModel)",
                providerID: shell.settings.polishProviderID,
                model: shell.settings.polishModel
            )]
        }

        var options: [RetryModelOption] = []
        options.append(contentsOf: verifiedOptions(
            providerID: "openai_polish",
            providerName: "OpenAI",
            models: shell.availableModels(for: "openai_polish", usage: .polish)
        ))
        options.append(contentsOf: verifiedOptions(
            providerID: "groq_polish",
            providerName: "Groq",
            models: shell.availableModels(for: "groq_polish", usage: .polish)
        ))
        options.append(contentsOf: verifiedOptions(
            providerID: "openrouter_polish",
            providerName: "OpenRouter",
            models: shell.availableModels(for: "openrouter_polish", usage: .polish)
        ))
        options.append(contentsOf: verifiedOptions(
            providerID: "gemini_polish",
            providerName: "Gemini",
            models: shell.availableModels(for: "gemini_polish", usage: .polish)
        ))

        if options.isEmpty {
            options = [RetryModelOption(
                id: "\(shell.settings.polishProviderID)|\(shell.settings.polishModel)",
                title: "\(providerDisplayName(for: shell.settings.polishProviderID)) / \(shell.settings.polishModel)",
                providerID: shell.settings.polishProviderID,
                model: shell.settings.polishModel
            )]
        }
        return options.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
    }

    private var displayedRetryPolishOptions: [RetryModelOption] {
        optionsFilteredByText(
            retryPolishOptions,
            filter: retryPolishFilter,
            includeID: selectedRetryPolishOptionID
        )
    }

    private var selectedRetryPolishOption: RetryModelOption {
        retryPolishOptions.first(where: { $0.id == selectedRetryPolishOptionID })
            ?? displayedRetryPolishOptions.first
            ?? RetryModelOption(id: "fallback-polish", title: "Unavailable", providerID: shell.settings.polishProviderID, model: shell.settings.polishModel)
    }

    private func syncRetryPolishSelection() {
        if retryPolishOptions.contains(where: { $0.id == selectedRetryPolishOptionID }) {
            return
        }
        let preferredID = "\(shell.settings.polishProviderID)|\(shell.settings.polishModel)"
        if retryPolishOptions.contains(where: { $0.id == preferredID }) {
            selectedRetryPolishOptionID = preferredID
            return
        }
        selectedRetryPolishOptionID = retryPolishOptions.first?.id ?? preferredID
    }

    private func syncRetryTranscriptionSelection() {
        let sourceProvider = shell.rawTranscriptProviderID.isEmpty ? (shell.currentSession?.metadata.sttProvider ?? "") : shell.rawTranscriptProviderID
        let sourceModel = shell.rawTranscriptModel.isEmpty ? (shell.currentSession?.metadata.sttModel ?? "") : shell.rawTranscriptModel

        if let id = retryApproachID(providerID: sourceProvider, model: sourceModel) {
            selectedRetryApproachID = id
            return
        }

        if let id = retryApproachID(
            providerID: shell.settings.transcriptionProviderID,
            model: shell.settings.transcriptionModel
        ) {
            selectedRetryApproachID = id
            return
        }

        if let first = retryApproaches.first {
            selectedRetryApproachID = first.id
        }
    }

    private func retryApproachID(providerID: String, model: String) -> String? {
        guard !providerID.isEmpty, !model.isEmpty else {
            return nil
        }
        return retryApproaches.first(where: { $0.providerID == providerID && $0.model == model })?.id
    }

    private func optionsFilteredByText(
        _ options: [RetryModelOption],
        filter: String,
        includeID: String
    ) -> [RetryModelOption] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var filtered: [RetryModelOption]
        if trimmed.isEmpty {
            filtered = options
        } else {
            filtered = options.filter { $0.title.lowercased().contains(trimmed) }
        }

        if filtered.contains(where: { $0.id == includeID }) {
            return filtered
        }

        if let current = options.first(where: { $0.id == includeID }) {
            return [current] + filtered
        }
        return filtered
    }

    private func verifiedOptions(
        providerID: String,
        providerName: String,
        models: [String]
    ) -> [RetryModelOption] {
        let status = shell.providerConnectivityStatus(for: providerID)
        guard status.state == .verified else {
            return []
        }
        return models.map { model in
            RetryModelOption(
                id: "\(providerID)|\(model)",
                title: "\(providerName) / \(model)",
                providerID: providerID,
                model: model
            )
        }
    }

    private func localTranscriptionOptions() -> [RetryModelOption] {
        let installedModels = shell.modelManager.catalog
            .map(\.id)
            .filter { shell.modelManager.isInstalled(modelID: $0) }
            .sorted()

        let models = installedModels.isEmpty ? [shell.settings.transcriptionModel] : installedModels
        return models.map { model in
            RetryModelOption(
                id: "whispercpp|\(model)",
                title: "Local whisper.cpp / \(model)",
                providerID: "whispercpp",
                model: model
            )
        }
    }

    private func providerDisplayName(for providerID: String) -> String {
        switch providerID {
        case "whispercpp":
            return "Local whisper.cpp"
        case "openai_whisper":
            return "OpenAI"
        case "groq_whisper":
            return "Groq"
        case "openrouter_transcribe":
            return "OpenRouter"
        case "gemini_transcribe":
            return "Gemini"
        case "openai_polish":
            return "OpenAI"
        case "groq_polish":
            return "Groq"
        case "openrouter_polish":
            return "OpenRouter"
        case "gemini_polish":
            return "Gemini"
        default:
            return providerID
        }
    }

    private func sourceSummary(
        transcript: String,
        providerID: String,
        model: String,
        fallbackProviderID: String?,
        fallbackModel: String?
    ) -> String {
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Used: none yet"
        }

        let resolvedProvider = providerID.isEmpty ? (fallbackProviderID ?? "") : providerID
        let resolvedModel = model.isEmpty ? (fallbackModel ?? "") : model

        if resolvedProvider.isEmpty || resolvedModel.isEmpty {
            return "Used: unknown"
        }
        return "Used: \(providerDisplayName(for: resolvedProvider)) / \(resolvedModel)"
    }

    private var rawPlaceholderText: String {
        switch shell.sessionState {
        case .recording:
            return "Raw transcript appears after you stop recording."
        case .finalizingAudio, .transcribing:
            return "Transcribing audio..."
        case .idle, .polishing, .completed, .failed:
            return "Raw transcript will appear here."
        }
    }

    private var rawPanelText: String {
        let trimmed = shell.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return rawPlaceholderText
        }
        return shell.rawTranscript
    }

    private var rawPanelIsPlaceholder: Bool {
        shell.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedHistoryEntries: [SessionHistoryEntry] {
        shell.visibleHistorySessions.filter { selectedHistorySessionIDs.contains($0.id) }
    }

    private var historyDeleteConfirmationTitle: String {
        pendingDeleteEntries.count == 1 ? "Delete Session" : "Delete Sessions"
    }

    private var historyDeleteConfirmationActionLabel: String {
        pendingDeleteEntries.count == 1 ? "Delete session" : "Delete \(pendingDeleteEntries.count) sessions"
    }

    private var historyDeleteConfirmationMessage: String {
        if pendingDeleteEntries.count == 1 {
            return "Move this session to Trash?"
        }
        return "Move \(pendingDeleteEntries.count) selected sessions to Trash?"
    }

    private func clearHistorySelectionAfterDelete() {
        let pendingIDs = Set(pendingDeleteEntries.map(\.id))
        selectedHistorySessionIDs = selectedHistorySessionIDs.subtracting(pendingIDs)
        if historySelectionMode && selectedHistorySessionIDs.isEmpty {
            historySelectionMode = false
        }
    }

    private func historyAudioURL(for entry: SessionHistoryEntry) -> URL? {
        let audioURL = entry.folderURL.appendingPathComponent("audio.m4a")
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return nil
        }
        return audioURL
    }

    private func toggleHistorySelection(_ entry: SessionHistoryEntry) {
        if selectedHistorySessionIDs.contains(entry.id) {
            selectedHistorySessionIDs.remove(entry.id)
        } else {
            selectedHistorySessionIDs.insert(entry.id)
        }
    }

    private var historyListHeight: CGFloat {
        expandedTextPanels ? 560 : 380
    }

    private func historyTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func historyStateColor(_ state: SessionState) -> Color {
        switch state {
        case .recording:
            return .green
        case .finalizingAudio, .transcribing:
            return .orange
        case .polishing:
            return .mint
        case .failed:
            return .red
        case .completed:
            return .blue
        case .idle:
            return .gray
        }
    }

    private var popoverWidth: CGFloat {
        (shell.selectedPopoverTab == .history || expandedTextPanels) ? 620 : 540
    }

}

private struct RetryModelOption: Identifiable {
    let id: String
    let title: String
    let providerID: String
    let model: String
}

private struct InstantHintModifier: ViewModifier {
    let text: String
    @Binding var hoverHint: String?

    func body(content: Content) -> some View {
        content
            .help(text)
            .onHover { isHovering in
                if isHovering {
                    hoverHint = text
                } else if hoverHint == text {
                    hoverHint = nil
                }
            }
    }
}

private extension View {
    func instantHint(_ text: String, hoverHint: Binding<String?>) -> some View {
        modifier(InstantHintModifier(text: text, hoverHint: hoverHint))
    }
}

enum AVAudioSessionBridge {
    static var defaultInputName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "Unknown input"
    }
}
