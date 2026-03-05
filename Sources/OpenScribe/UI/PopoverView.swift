import Foundation
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var shell: AppShell
    @StateObject private var playbackManager = AudioPlaybackManager()
    @State private var selectedRetryApproachID = ""
    @State private var selectedRetryPolishOptionID = ""
    @State private var historySelectionMode = false
    @State private var selectedHistorySessionIDs: Set<UUID> = []
    @State private var pendingDeleteEntries: [SessionHistoryEntry] = []
    @State private var hoverHint: String?
    @State private var showingRawTranscriptPopup = false
    @State private var showingPolishedTranscriptPopup = false
    private static let streakUnlockDays = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            mainTabBar

            if shell.selectedPopoverTab == .live {
                liveSection
            } else if shell.selectedPopoverTab == .history {
                historySection
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                statsSection
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            footerSection
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: popoverWidth)
        .frame(maxHeight: .infinity, alignment: shell.selectedPopoverTab == .live ? .center : .top)
        .onAppear {
            shell.selectPopoverTab(shell.selectedPopoverTab)
            syncRetryPolishSelection()
            syncRetryTranscriptionSelection()
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
        .sheet(isPresented: $showingRawTranscriptPopup) {
            TranscriptPopupView(
                title: "Raw transcript",
                text: shell.rawTranscript,
                sourceSummary: rawSourceSummary
            )
        }
        .sheet(isPresented: $showingPolishedTranscriptPopup) {
            TranscriptPopupView(
                title: "Polished transcript",
                text: shell.polishedTranscript,
                sourceSummary: polishedSourceSummary
            )
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
        Picker("Popover tab", selection: mainTabSelection) {
            Text("Live").tag(PopoverTabSelection.live)
            Text("History").tag(PopoverTabSelection.history)
            Text("Stats").tag(PopoverTabSelection.stats)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 300)
    }

    private var mainTabSelection: Binding<PopoverTabSelection> {
        Binding(
            get: { shell.selectedPopoverTab },
            set: { nextTab in
                shell.selectPopoverTab(nextTab)
            }
        )
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 5) {
                OpenScribeLogo(size: 16)
                Text("OpenScribe")
                    .font(.headline)
            }

            Spacer()

            stateChip
        }
    }

    // MARK: - Live Tab

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            controlBar
            transcriptArea
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Control Bar

    private static let transcriptPanelHeight: CGFloat = 120

    private var controlBar: some View {
        HStack(spacing: 8) {
            Button(startStopButtonLabel) {
                shell.toggleRecording()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(startStopButtonDisabled)
            .instantHint(startStopHelpText, hoverHint: $hoverHint)

            levelMeter
                .frame(width: 80, height: 6)

            devicePicker

            if shell.permissionState != .authorized {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                    .help(permissionWarningText)
            }

            Spacer(minLength: 0)

            Button {
                if let audioURL = shell.currentSession?.paths.audioURL {
                    playbackManager.toggle(url: audioURL)
                }
            } label: {
                Image(systemName: playbackManager.isPlaying ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(playbackManager.isPlaying ? "Stop audio" : "Play audio")
            .opacity(hasAudioFile ? 1 : 0)
            .disabled(!hasAudioFile)
            .instantHint(
                playbackManager.isPlaying ? "Stop audio playback" : "Play session audio",
                hoverHint: $hoverHint
            )

            Button {
                shell.revealCurrentSessionInFinder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reveal in Finder")
            .contextMenu {
                Button("Copy Session Path") {
                    shell.copyCurrentSessionPath()
                }
            }
            .instantHint("Reveal session in Finder (right-click to copy path)", hoverHint: $hoverHint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var hasAudioFile: Bool {
        guard let audioURL = shell.currentSession?.paths.audioURL else { return false }
        return FileManager.default.fileExists(atPath: audioURL.path)
    }

    private var levelMeter: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.18))

                Capsule()
                    .fill(shell.microphoneIndicatorColorName == "green" ? Color.green : Color.gray)
                    .frame(width: max(4, CGFloat(shell.meterLevel) * geometry.size.width))
            }
        }
    }

    private var devicePicker: some View {
        Menu {
            Button("Automatic") {
                shell.setSessionMicrophoneOverride(nil)
            }
            Divider()
            ForEach(shell.availableMicrophones) { device in
                Button(device.name) {
                    shell.setSessionMicrophoneOverride(device.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "mic")
                    .font(.caption2)
                Text(controlBarDeviceName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .instantHint("Change recording input device", hoverHint: $hoverHint)
    }

    private var controlBarDeviceName: String {
        if let overrideID = shell.sessionMicrophoneOverrideID,
           let name = shell.microphoneName(for: overrideID) {
            return name
        }
        return shell.currentSession?.metadata.inputDeviceName
            ?? shell.systemDefaultMicrophoneName
    }

    private var permissionWarningText: String {
        switch shell.permissionState {
        case .denied:
            return "Microphone permission denied. Open System Settings to grant access."
        case .undetermined:
            return "Microphone permission not yet requested."
        case .authorized:
            return ""
        }
    }

    // MARK: Transcript Area

    private var transcriptArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                rawTranscriptSection
                polishedTranscriptSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 2)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var rawTranscriptSection: some View {
        transcriptSubsection {
            Text("Raw transcript")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            rawTranscriptPanel

            HStack(alignment: .center, spacing: 8) {
                Button {
                    shell.copyRawTranscript()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy raw transcript")
                .instantHint(copyRawHelpText, hoverHint: $hoverHint)

                Button {
                    showingRawTranscriptPopup = true
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("View full raw transcript")
                .disabled(shell.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .instantHint("View full raw transcript", hoverHint: $hoverHint)

                Button {
                    shell.retryTranscription(
                        temporaryProviderID: selectedRetryApproach.providerID,
                        temporaryModel: selectedRetryApproach.model
                    )
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Retry transcription")
                .disabled(!canRetryTranscription)
                .instantHint("Retry transcription with selected model", hoverHint: $hoverHint)

                Spacer(minLength: 0)

                SearchableModelSelector(
                    options: retryApproaches,
                    selectedID: $selectedRetryApproachID,
                    disabled: false
                )
                .frame(maxWidth: 220)
            }
        }
    }

    private var polishedTranscriptSection: some View {
        transcriptSubsection {
            Text("Polished transcript")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ScrollView {
                Text(polishedBodyText)
                    .font(.body)
                    .foregroundStyle(shell.polishedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: Self.transcriptPanelHeight)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .center, spacing: 8) {
                Button {
                    shell.copyLatestPolished()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy polished transcript")
                .instantHint(copyPolishedHelpText, hoverHint: $hoverHint)

                Button {
                    showingPolishedTranscriptPopup = true
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("View full polished transcript")
                .disabled(shell.polishedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .instantHint("View full polished transcript", hoverHint: $hoverHint)

                Button {
                    shell.retryPolish(
                        temporaryProviderID: selectedRetryPolishOption.providerID,
                        temporaryModel: selectedRetryPolishOption.model
                    )
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Retry polish")
                .disabled(shell.rawTranscript.isEmpty || !shell.settings.polishEnabled)
                .instantHint("Retry polish with selected model", hoverHint: $hoverHint)

                Spacer(minLength: 0)

                SearchableModelSelector(
                    options: retryPolishOptions,
                    selectedID: $selectedRetryPolishOptionID,
                    disabled: !shell.settings.polishEnabled
                )
                .frame(maxWidth: 220)
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
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(shell.visibleHistorySessions) { entry in
                                historyRow(entry)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
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
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var statsSection: some View {
        card(title: "Stats", trailing: {
            Button {
                shell.refreshStatsSummary()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .instantHint("Refresh usage stats", hoverHint: $hoverHint)
        }) {
            if shell.statsSummary.totalEvents == 0 {
                Text("No stats yet. Complete a transcription to start tracking usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        statsHeroHeader
                        statsHeroGrid
                        statsOverviewSection
                        statsLatestRunSection
                        statsCurrentSessionSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.trailing, 2)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var statsHeroHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("You've been scribing.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("A snapshot of your dictation momentum.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    private var statsHeroGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 180), spacing: 10),
                GridItem(.flexible(minimum: 180), spacing: 10)
            ],
            spacing: 10
        ) {
            statsHeroCard(
                title: "Current streak",
                value: "\(shell.statsSummary.currentActiveDayStreak) \(shell.statsSummary.currentActiveDayStreak == 1 ? "day" : "days")",
                subtitle: streakSummarySubtitle,
                accent: .orange,
                icon: "🔥"
            )

            statsHeroCard(
                title: "Average speed",
                value: "\(formattedStatRate(shell.statsSummary.averageWordsPerMinute)) WPM",
                subtitle: "Estimated from raw transcript output.",
                accent: .blue,
                icon: "🚀"
            )

            statsHeroCard(
                title: "Total words",
                value: formattedStatCount(shell.statsSummary.spokenWords),
                subtitle: wordMilestoneSubtitle,
                accent: .mint,
                icon: "📚"
            )

            statsHeroCard(
                title: "Sessions",
                value: formattedStatCount(shell.statsSummary.sessionCount),
                subtitle: "\(shell.statsSummary.transcriptionRuns) transcription runs logged.",
                accent: .purple,
                icon: "🗂️"
            )
        }
    }

    private func statsHeroCard(
        title: String,
        value: String,
        subtitle: String,
        accent: Color,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(icon)
                    .font(.title3)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.16),
                            Color(NSColor.textBackgroundColor).opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
    }

    private var statsOverviewSection: some View {
        transcriptSubsection {
            VStack(alignment: .leading, spacing: 6) {
                Text("Overview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                statsMetricRow("Current streak", "\(shell.statsSummary.currentActiveDayStreak) days")
                statsMetricRow("Longest streak", "\(shell.statsSummary.longestActiveDayStreak) days")
                statsMetricRow("Avg day gap", formattedActiveDayGap)
                statsMetricRow("Last 7 days", "\(shell.statsSummary.wordsLast7Days) words")
                statsMetricRow("Last 30 days", "\(shell.statsSummary.wordsLast30Days) words")
                statsMetricRow("Raw to polished", formattedPolishDelta)
                statsMetricRow("Book equivalent", averageBookEquivalent)
                statsMetricRow("Most used model", mostUsedModelLabel)
                statsMetricRow("Events", "\(shell.statsSummary.totalEvents)")
                statsMetricRow("Latest event", formattedStatsDate(shell.statsSummary.lastEventAt))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsLatestRunSection: some View {
        transcriptSubsection {
            VStack(alignment: .leading, spacing: 8) {
                Text("Latest run metrics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let latestTranscription = shell.statsSummary.latestTranscriptionEvent {
                    latestRunRow(
                        title: "Transcription",
                        event: latestTranscription
                    )
                } else {
                    Text("No transcription run recorded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let latestPolish = shell.statsSummary.latestPolishEvent {
                    latestRunRow(
                        title: "Polish",
                        event: latestPolish
                    )
                } else {
                    Text("No polish run recorded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func latestRunRow(title: String, event: StatsEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(title): \(providerDisplayName(for: event.providerId)) / \(event.model)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text("In \(formattedStatsUnits(event.inputUnits, unit: event.inputUnit)) | Out \(formattedStatsUnits(event.outputUnits, unit: event.outputUnit))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("Tokens \(formattedTokenPair(input: event.inputTokens, output: event.outputTokens))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("Updated \(formattedStatsDate(event.timestamp))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsCurrentSessionSection: some View {
        transcriptSubsection {
            VStack(alignment: .leading, spacing: 6) {
                Text("Current session details")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let session = shell.currentSession {
                    statsMetricRow("Session", shortSessionID(session.id))
                    statsMetricRow("State", session.metadata.state.displayLabel)
                    statsMetricRow("Created", historyTimestamp(session.metadata.createdAt))
                    statsMetricRow("Duration", formattedSessionDuration(session))
                    statsMetricRow("Transcribe", "\(providerDisplayName(for: session.metadata.sttProvider)) / \(session.metadata.sttModel)")
                    statsMetricRow("Raw units", "\(currentRawWordCount) words from \(formattedStatsUnits(sessionDurationSeconds(session), unit: .audioSeconds))")
                    statsMetricRow("Raw WPM", formattedCurrentSessionWPM(session))
                    statsMetricRow("Polish", "\(providerDisplayName(for: session.metadata.polishProvider)) / \(session.metadata.polishModel)")
                    statsMetricRow("Polished units", "\(currentPolishedWordCount) words")
                    statsMetricRow("Session delta", formattedCurrentSessionDelta)
                } else {
                    Text("Open any history session to view detailed per-session stats.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsMetricRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
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
                    .lineLimit(3)
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

    private func openSettings() {
        shell.openSettingsWindow()
    }

    private func openHistorySessionAndShowLive(_ entry: SessionHistoryEntry) {
        if shell.openHistorySession(entry) {
            shell.selectPopoverTab(.live)
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
        .frame(height: Self.transcriptPanelHeight)
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

    private var selectedRetryApproach: RetryModelOption {
        retryApproaches.first(where: { $0.id == selectedRetryApproachID })
            ?? retryApproaches.first
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

    private var selectedRetryPolishOption: RetryModelOption {
        retryPolishOptions.first(where: { $0.id == selectedRetryPolishOptionID })
            ?? retryPolishOptions.first
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

    private func formattedStatsUnits(_ value: Double, unit: StatsUnit) -> String {
        switch unit {
        case .words:
            return "\(Int(value.rounded())) words"
        case .audioSeconds:
            return String(format: "%.1f sec", value)
        }
    }

    private func formattedTokenPair(input: Int?, output: Int?) -> String {
        if input == nil, output == nil {
            return "in n/a | out n/a"
        }
        let inputLabel = input.map(String.init) ?? "n/a"
        let outputLabel = output.map(String.init) ?? "n/a"
        return "in \(inputLabel) | out \(outputLabel)"
    }

    private func formattedStatRate(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }
        return String(format: "%.1f", value)
    }

    private func formattedStatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var streakSummarySubtitle: String {
        let current = shell.statsSummary.currentActiveDayStreak
        let longest = shell.statsSummary.longestActiveDayStreak
        let unlockDays = Self.streakUnlockDays
        if current < unlockDays {
            return "\(current)/\(unlockDays) active days | Longest \(longest) days"
        }
        return "Longest \(longest) days | Avg gap \(formattedActiveDayGap)"
    }

    private var formattedActiveDayGap: String {
        guard let average = shell.statsSummary.averageDaysBetweenActiveDays else {
            return "n/a"
        }
        return "\(String(format: "%.1f", average)) days"
    }

    private var averageBookEquivalent: String {
        let wordsPerAverageBook = 80_000.0
        let books = Double(shell.statsSummary.spokenWords) / wordsPerAverageBook
        return String(format: "~%.2f average books", books)
    }

    private var wordMilestoneSubtitle: String {
        let spokenWords = shell.statsSummary.spokenWords
        guard spokenWords > 0 else {
            return "Complete a transcription to unlock milestones."
        }

        let levels: [(name: String, words: Int)] = [
            ("Wikipedia article", 650),
            ("Harry Potter 1", 76_900),
            ("average book", 80_000),
            ("Harry Potter series", 1_084_000)
        ]

        let booksLine = averageBookEquivalent
        if let next = levels.first(where: { spokenWords < $0.words }) {
            let remaining = next.words - spokenWords
            return "\(booksLine) | \(formattedStatCount(remaining)) words to \(next.name)"
        }

        return "\(booksLine) | You passed every milestone."
    }

    private var formattedPolishDelta: String {
        let deltaWords = shell.statsSummary.polishDeltaWords
        let signedWords = deltaWords >= 0 ? "+\(deltaWords)" : "\(deltaWords)"
        guard let percent = shell.statsSummary.polishDeltaPercent else {
            return "\(signedWords) words"
        }
        let signedPercent = percent >= 0 ? "+\(String(format: "%.1f", percent))" : String(format: "%.1f", percent)
        return "\(signedWords) words (\(signedPercent)%)"
    }

    private var mostUsedModelLabel: String {
        guard let usage = shell.statsSummary.providerUsage.first else {
            return "-"
        }
        return "\(usage.stage.displayLabel): \(providerDisplayName(for: usage.providerId)) / \(usage.model) (\(usage.runCount)x)"
    }

    private var currentRawWordCount: Int {
        wordCount(shell.rawTranscript)
    }

    private var currentPolishedWordCount: Int {
        let polished = shell.polishedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if polished.isEmpty {
            return 0
        }
        return wordCount(polished)
    }

    private var formattedCurrentSessionDelta: String {
        guard currentPolishedWordCount > 0 else {
            return "-"
        }
        let delta = currentPolishedWordCount - currentRawWordCount
        let signedDelta = delta >= 0 ? "+\(delta)" : "\(delta)"
        guard currentRawWordCount > 0 else {
            return "\(signedDelta) words"
        }
        let percent = (Double(delta) / Double(currentRawWordCount)) * 100.0
        let signedPercent = percent >= 0 ? "+\(String(format: "%.1f", percent))" : String(format: "%.1f", percent)
        return "\(signedDelta) words (\(signedPercent)%)"
    }

    private func formattedCurrentSessionWPM(_ session: SessionContext) -> String {
        let seconds = sessionDurationSeconds(session)
        guard seconds > 0 else {
            return "-"
        }
        let wpm = (Double(currentRawWordCount) / Double(seconds)) * 60.0
        return "\(String(format: "%.1f", wpm))"
    }

    private func formattedSessionDuration(_ session: SessionContext) -> String {
        let seconds = Int(sessionDurationSeconds(session).rounded())
        return formattedDuration(seconds)
    }

    private func sessionDurationSeconds(_ session: SessionContext) -> Double {
        if let durationMs = session.metadata.durationMs, durationMs > 0 {
            return Double(durationMs) / 1_000.0
        }
        if let stoppedAt = session.metadata.stoppedAt {
            let ms = max(0, stoppedAt.timeIntervalSince(session.metadata.createdAt) * 1_000.0)
            return ms / 1_000.0
        }
        return 0
    }

    private func shortSessionID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func wordCount(_ text: String) -> Int {
        text
            .split { character in
                character.isWhitespace || character.isNewline
            }
            .count
    }

    private func formattedStatsDate(_ date: Date?) -> String {
        guard let date else {
            return "-"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var popoverWidth: CGFloat {
        switch shell.selectedPopoverTab {
        case .live:
            return 540
        case .history, .stats:
            return 620
        }
    }

}

private struct RetryModelOption: Identifiable {
    let id: String
    let title: String
    let providerID: String
    let model: String
}

private struct TranscriptPopupView: View {
    let title: String
    let text: String
    let sourceSummary: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(sourceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 320)
    }
}

/// App logo matching the adaptive SVG geometry from site-docs/images/logo.svg.
/// Uses .primary foreground so it adapts to light/dark mode automatically.
private struct OpenScribeLogo: View {
    let size: CGFloat

    // SVG viewBox is 18x18. Circle r=7.75 centered at (9,9), stroke 1.3.
    // Three bars at [0.45, 0.80, 0.45] of inner rect height.
    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 18.0
            let center = CGPoint(x: 9 * scale, y: 9 * scale)
            let radius = 7.75 * scale
            let strokeWidth = 1.3 * scale

            // Circle stroke
            let circlePath = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
            context.stroke(circlePath, with: .foreground, lineWidth: strokeWidth)

            // Bars: x positions 5.55, 8.55, 11.55; width 1.6; rx 0.9
            let bars: [(x: CGFloat, y: CGFloat, h: CGFloat)] = [
                (5.55, 7.357, 3.285),
                (8.55, 6.08,  5.84),
                (11.55, 7.357, 3.285),
            ]
            let barWidth = 1.6 * scale
            let cornerRadius = 0.9 * scale

            for bar in bars {
                let rect = CGRect(
                    x: bar.x * scale, y: bar.y * scale,
                    width: barWidth, height: bar.h * scale
                )
                let barPath = Path(roundedRect: rect, cornerRadius: cornerRadius)
                context.fill(barPath, with: .foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct SearchableModelSelector: View {
    let options: [RetryModelOption]
    @Binding var selectedID: String
    let disabled: Bool

    @State private var isOpen = false
    @State private var searchText = ""
    @FocusState private var isFocused: Bool

    private var selectedTitle: String {
        options.first(where: { $0.id == selectedID })?.title ?? "Select model"
    }

    var body: some View {
        if isOpen {
            TextField("Search model...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.system(size: NSFont.smallSystemFontSize))
                .focused($isFocused)
                .onExitCommand { closeDropdown() }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isFocused = true
                    }
                }
                .background(
                    DropdownAnchor(
                        isOpen: $isOpen,
                        searchText: $searchText,
                        selectedID: $selectedID,
                        options: options,
                        onClose: { closeDropdown() }
                    )
                )
        } else {
            Button {
                guard !disabled else { return }
                isOpen = true
                searchText = ""
            } label: {
                HStack(spacing: 4) {
                    Text(selectedTitle)
                        .font(.system(size: NSFont.smallSystemFontSize))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
    }

    private func closeDropdown() {
        isOpen = false
        searchText = ""
        isFocused = false
    }
}

/// Invisible NSView that anchors a floating NSPanel dropdown below the text field.
private struct DropdownAnchor: NSViewRepresentable {
    @Binding var isOpen: Bool
    @Binding var searchText: String
    @Binding var selectedID: String
    let options: [RetryModelOption]
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.applyState(
            options: options,
            searchText: searchText
        )

        if isOpen {
            context.coordinator.showPanel()
        } else {
            context.coordinator.hidePanel()
        }
    }

    func makeCoordinator() -> DropdownCoordinator {
        DropdownCoordinator(
            isOpen: $isOpen,
            selectedID: $selectedID,
            options: options,
            searchText: searchText,
            onClose: onClose
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: DropdownCoordinator) {
        coordinator.hidePanel()
    }

    @MainActor class DropdownCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var anchorView: NSView?
        var options: [RetryModelOption]
        var searchText: String
        @Binding var isOpen: Bool
        @Binding var selectedID: String
        let onClose: () -> Void

        private var panel: NSPanel?
        private var tableView: NSTableView?
        private var clickMonitor: Any?
        private var keyMonitor: Any?
        private var filteredOptions: [RetryModelOption] = []
        private var optionIDSignature: [String]

        init(
            isOpen: Binding<Bool>,
            selectedID: Binding<String>,
            options: [RetryModelOption],
            searchText: String,
            onClose: @escaping () -> Void
        ) {
            self._isOpen = isOpen
            self._selectedID = selectedID
            self.options = options
            self.searchText = searchText
            self.optionIDSignature = options.map(\.id)
            self.onClose = onClose
            super.init()
        }

        func applyState(options: [RetryModelOption], searchText: String) {
            let nextSignature = options.map(\.id)
            let optionsChanged = nextSignature != optionIDSignature
            let searchChanged = self.searchText != searchText

            self.options = options
            self.searchText = searchText
            self.optionIDSignature = nextSignature

            guard panel != nil, optionsChanged || searchChanged else { return }

            updateFilter()
            reloadTablePreservingSelection()
            repositionPanel()
        }

        func showPanel() {
            updateFilter()

            if let panel = panel {
                repositionPanel()
                panel.orderFront(nil)
                return
            }

            guard let anchor = anchorView, let window = anchor.window else { return }

            let table = NSTableView()
            table.headerView = nil
            table.style = .plain
            table.rowHeight = 24
            table.intercellSpacing = NSSize(width: 0, height: 0)
            table.selectionHighlightStyle = .regular
            table.dataSource = self
            table.delegate = self
            table.target = self
            table.action = #selector(rowClicked)

            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("model"))
            column.isEditable = false
            table.addTableColumn(column)

            let scroll = NSScrollView()
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false

            let dropdownPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            dropdownPanel.isFloatingPanel = true
            dropdownPanel.level = .popUpMenu
            dropdownPanel.hasShadow = true
            dropdownPanel.isOpaque = false
            dropdownPanel.backgroundColor = NSColor.controlBackgroundColor

            let container = NSVisualEffectView()
            container.material = .menu
            container.state = .active
            container.maskImage = roundedMask(size: NSSize(width: 280, height: 200), radius: 6)
            container.addSubview(scroll)
            scroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
                scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
                scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])

            dropdownPanel.contentView = container
            self.panel = dropdownPanel
            self.tableView = table

            reloadTablePreservingSelection()
            repositionPanel()
            window.addChildWindow(dropdownPanel, ordered: .above)

            installClickMonitor()
            installKeyMonitor()
        }

        func hidePanel() {
            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
                clickMonitor = nil
            }
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if let panel = panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            panel = nil
            tableView = nil
        }

        // MARK: Event Monitors

        private func installClickMonitor() {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self = self, self.isOpen else { return event }
                if event.window === self.panel {
                    return event
                }
                if let hitView = event.window?.contentView?.hitTest(
                    event.window?.contentView?.convert(event.locationInWindow, from: nil) ?? .zero
                ), self.isViewInsideTextField(hitView) {
                    return event
                }
                DispatchQueue.main.async { self.onClose() }
                return event
            }
        }

        private func isViewInsideTextField(_ view: NSView) -> Bool {
            var current: NSView? = view
            while let v = current {
                if v is NSTextField { return true }
                current = v.superview
            }
            return false
        }

        private func installKeyMonitor() {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isOpen, let table = self.tableView else { return event }
                guard !self.filteredOptions.isEmpty else { return event }

                switch event.keyCode {
                case 125: // arrow down
                    let next = table.selectedRow + 1
                    if next < self.filteredOptions.count {
                        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                        table.scrollRowToVisible(next)
                    }
                    return nil
                case 126: // arrow up
                    let prev = table.selectedRow - 1
                    if prev >= 0 {
                        table.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
                        table.scrollRowToVisible(prev)
                    }
                    return nil
                case 36: // return/enter
                    let row = table.selectedRow
                    if row >= 0, row < self.filteredOptions.count {
                        self.selectedID = self.filteredOptions[row].id
                    } else if let first = self.filteredOptions.first {
                        self.selectedID = first.id
                    }
                    DispatchQueue.main.async { self.onClose() }
                    return nil
                default:
                    return event
                }
            }
        }

        // MARK: Filtering & Layout

        private func updateFilter() {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if query.isEmpty {
                filteredOptions = options
            } else {
                filteredOptions = options.filter { $0.title.lowercased().contains(query) }
            }
        }

        private func repositionPanel() {
            guard let anchor = anchorView, let window = anchor.window, let panel = panel else { return }
            let anchorFrame = anchor.convert(anchor.bounds, to: nil)
            let screenFrame = window.convertToScreen(anchorFrame)
            let panelWidth: CGFloat = max(anchorFrame.width, 280)
            let rowCount = min(filteredOptions.count, 10)
            let panelHeight = CGFloat(max(rowCount, 1)) * 24 + 8
            let origin = NSPoint(
                x: screenFrame.maxX - panelWidth,
                y: screenFrame.minY - panelHeight - 2
            )
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)), display: true)
        }

        private func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
            let image = NSImage(size: size)
            image.lockFocus()
            let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: radius, yRadius: radius)
            NSColor.black.setFill()
            path.fill()
            image.unlockFocus()
            return image
        }

        private func reloadTablePreservingSelection() {
            guard let table = tableView else { return }

            let selectedIDBeforeReload: String? = {
                let row = table.selectedRow
                guard row >= 0, row < filteredOptions.count else { return selectedID }
                return filteredOptions[row].id
            }()

            table.reloadData()

            guard !filteredOptions.isEmpty else { return }

            if let selectedIDBeforeReload,
               let selectedIndex = filteredOptions.firstIndex(where: { $0.id == selectedIDBeforeReload }) {
                table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
                table.scrollRowToVisible(selectedIndex)
            }
        }

        // MARK: NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            return max(filteredOptions.count, 1)
        }

        // MARK: NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard !filteredOptions.isEmpty else {
                let cell = NSTextField(labelWithString: "No matching models")
                cell.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                cell.textColor = .secondaryLabelColor
                cell.lineBreakMode = .byTruncatingTail
                return cell
            }
            let option = filteredOptions[row]
            let cell = NSTextField(labelWithString: option.title)
            cell.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            cell.textColor = .labelColor
            cell.lineBreakMode = .byTruncatingTail
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            !filteredOptions.isEmpty
        }

        @objc private func rowClicked() {
            guard let table = tableView else { return }
            let row = table.clickedRow
            guard row >= 0, row < filteredOptions.count else { return }
            selectedID = filteredOptions[row].id
            onClose()
        }
    }
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
