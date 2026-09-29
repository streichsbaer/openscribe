import AppKit
import SwiftUI

struct LiveTabView: View {
    @EnvironmentObject private var shell: AppShell
    @ObservedObject var playback: AudioPlaybackManager
    @Binding var hoverHint: String?

    @State private var mode: TranscriptMode = .polished
    @State private var selectedTranscriptionOptionID = ""
    @State private var selectedPolishOptionID = ""

    enum TranscriptMode: String, CaseIterable, Identifiable {
        case polished = "Polished"
        case raw = "Raw"
        case changes = "Changes"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 12) {
            captureCard
            routeCard
            transcriptCard
        }
        .onAppear {
            syncTranscriptionOption()
            syncPolishOption()
        }
        .onChange(of: shell.settings.transcriptionProviderID) { _, _ in syncTranscriptionOption() }
        .onChange(of: shell.settings.transcriptionModel) { _, _ in syncTranscriptionOption() }
        .onChange(of: shell.rawTranscriptModel) { _, _ in syncTranscriptionOption() }
        .onChange(of: shell.settings.polishProviderID) { _, _ in syncPolishOption() }
        .onChange(of: shell.settings.polishModel) { _, _ in syncPolishOption() }
    }

    // MARK: Session state

    private var state: SessionState { shell.sessionState }

    private var isRecording: Bool { state == .recording }

    private var isProcessing: Bool {
        state == .finalizingAudio || state == .transcribing || state == .polishing
    }

    private var hasSession: Bool { shell.currentSession != nil }

    private var sessionHadNoSpeech: Bool {
        shell.currentSession?.metadata.audioActivity?.hasUsableSpeech == false
    }

    private var rawText: String {
        shell.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var polishedText: String {
        shell.polishedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Polish is part of this session's route when the session was recorded with polish on.
    /// With polish off the app still saves a polished file equal to the raw text, so the text alone
    /// does not tell whether polish ran.
    private var polishInRoute: Bool {
        if let metadata = shell.currentSession?.metadata {
            return metadata.polishProvider != "disabled" && !metadata.polishProvider.isEmpty
        }
        return shell.settings.polishEnabled
    }

    private var effectiveMode: TranscriptMode {
        polishInRoute ? mode : .raw
    }

    private var displayedText: String {
        switch effectiveMode {
        case .polished:
            return polishedText.isEmpty ? rawText : polishedText
        case .raw, .changes:
            return rawText
        }
    }

    // MARK: Capture card

    private var captureCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                recordButton

                if !isRecording, hasAudioFile {
                    Button {
                        if let url = shell.currentSession?.paths.audioURL {
                            playback.toggle(url: url)
                        }
                    } label: {
                        Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(PopoverIconButtonStyle(circular: true))
                    .accessibilityLabel(playback.isPlaying ? "Stop playback" : "Play recording")
                    .instantHint(playback.isPlaying ? "Stop playback" : "Play this recording", hoverHint: $hoverHint)
                }

                Group {
                    if isRecording {
                        LiveWaveform()
                    } else {
                        WaveformBars(
                            levels: shell.sessionWaveform,
                            barCount: AppShell.waveformBarCount,
                            maxHeight: 44,
                            color: { _, _ in Color.primary.opacity(0.28) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .accessibilityHidden(true)

                timerLabel
            }

            HStack(spacing: 8) {
                microphoneMenu
                Spacer(minLength: 8)
                LiveCaptureHint(
                    manager: shell.modelManager,
                    text: captureHint,
                    isWarning: shell.permissionState != .authorized
                )
            }
        }
        .padding(16)
        .popoverCard()
    }

    private var hasAudioFile: Bool {
        guard let url = shell.currentSession?.paths.audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var recordButton: some View {
        Button {
            shell.toggleRecording()
        } label: {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(PopoverPalette.record)
                        .shadow(color: PopoverPalette.record.opacity(0.35), radius: 8, y: 6)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                } else {
                    Circle()
                        .fill(PopoverPalette.control)
                        .overlay(Circle().strokeBorder(PopoverPalette.record.opacity(0.25), lineWidth: 1))
                        .shadow(color: PopoverPalette.cardShadow, radius: 6, y: 4)
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Circle()
                            .fill(PopoverPalette.record)
                            .frame(width: 22, height: 22)
                    }
                }
            }
            .frame(width: 60, height: 60)
            .background(
                Circle()
                    .fill(PopoverPalette.record.opacity(isRecording ? 0.14 : 0))
                    .frame(width: 72, height: 72)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel(isRecording ? "Stop recording" : (isProcessing ? "Processing the recording" : "Start recording"))
        .instantHint(recordHint, hoverHint: $hoverHint)
    }

    private var recordHint: String {
        let hotkey = HotkeyDisplay.string(for: shell.settings.startStopHotkey)
        if isRecording {
            return "Stop recording (\(hotkey))"
        }
        if isProcessing {
            return "Processing the last recording"
        }
        return "Start recording (\(hotkey))"
    }

    @ViewBuilder
    private var timerLabel: some View {
        if isRecording, let createdAt = shell.currentSession?.metadata.createdAt {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(PopoverFormat.clock(seconds: timeline.date.timeIntervalSince(createdAt)))
                    .font(.system(size: 26, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 60, alignment: .trailing)
            }
        } else if let seconds = sessionDurationSeconds {
            Text(PopoverFormat.clock(seconds: seconds))
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(PopoverPalette.muted)
        }
    }

    private var sessionDurationSeconds: Double? {
        guard let metadata = shell.currentSession?.metadata else { return nil }
        if let durationMs = metadata.durationMs {
            return Double(durationMs) / 1000
        }
        if let stoppedAt = metadata.stoppedAt {
            return stoppedAt.timeIntervalSince(metadata.createdAt)
        }
        return nil
    }

    private var microphoneMenu: some View {
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
            Divider()
            Button("Sound Input Settings…") {
                shell.openSoundInputSettings()
            }
        } label: {
            Label(microphoneName, systemImage: "mic")
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PopoverPalette.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(PopoverPalette.controlStroke, lineWidth: 1)
        )
        .accessibilityLabel("Microphone: \(microphoneName)")
        .instantHint("Choose the microphone for the next recording", hoverHint: $hoverHint)
    }

    private var microphoneName: String {
        if let overrideID = shell.sessionMicrophoneOverrideID,
           let name = shell.microphoneName(for: overrideID) {
            return name
        }
        if isRecording, let name = shell.currentSession?.metadata.inputDeviceName {
            return name
        }
        return shell.systemDefaultMicrophoneName
    }

    private var captureHint: String {
        switch shell.permissionState {
        case .denied:
            return "Microphone access is off"
        case .undetermined:
            return "OpenScribe will ask for the microphone"
        case .authorized:
            break
        }
        switch state {
        case .recording:
            return shell.audioMeter.snapshot.isActive ? "Hearing you clearly" : "Waiting for speech"
        case .finalizingAudio:
            return "Saving the recording"
        case .transcribing:
            return route.transcription.isLocal
                ? "Transcribing on this Mac"
                : "Sending audio to \(ProviderNames.display(transcriptionProviderID))"
        case .polishing:
            return "Polishing with \(ProviderNames.display(polishProviderID))"
        case .completed, .failed:
            return "Ready for the next one"
        case .idle:
            return hasSession ? "Ready for the next one" : "Ready"
        }
    }

    // MARK: Route card

    private var transcriptionProviderID: String {
        if !shell.rawTranscriptProviderID.isEmpty {
            return shell.rawTranscriptProviderID
        }
        return shell.currentSession?.metadata.sttProvider ?? shell.settings.transcriptionProviderID
    }

    private var transcriptionModelID: String {
        if !shell.rawTranscriptModel.isEmpty {
            return shell.rawTranscriptModel
        }
        return shell.currentSession?.metadata.sttModel ?? shell.settings.transcriptionModel
    }

    private var polishProviderID: String {
        if !shell.polishedTranscriptProviderID.isEmpty {
            return shell.polishedTranscriptProviderID
        }
        return shell.currentSession?.metadata.polishProvider ?? shell.settings.polishProviderID
    }

    private var polishModelID: String {
        if !shell.polishedTranscriptModel.isEmpty {
            return shell.polishedTranscriptModel
        }
        return shell.currentSession?.metadata.polishModel ?? shell.settings.polishModel
    }

    private var isFinished: Bool {
        hasSession && (state == .completed || state == .failed || state == .idle) && !rawText.isEmpty
    }

    private var delivery: PopoverRoute.Delivery {
        if shell.autoPasteOnComplete {
            return .paste
        }
        return shell.settings.copyOnComplete ? .copy : .none
    }

    private var route: PopoverRoute {
        PopoverRoute(
            transcriptionProvider: transcriptionProviderID,
            transcriptionModelName: shell.modelManager.asset(for: transcriptionModelID)?.displayName ?? transcriptionModelID,
            polishProvider: polishInRoute ? polishProviderID : nil,
            polishModel: polishInRoute ? polishModelID : nil,
            delivery: delivery,
            isFinished: isFinished,
            transcriptionMs: isFinished || state == .polishing ? shell.lastTranscriptionDurationMs : nil,
            polishMs: isFinished ? shell.lastPolishDurationMs : nil
        )
    }

    private var routeCard: some View {
        let route = route
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RouteNode(
                    systemImage: route.transcription.isLocal ? "cpu" : "cloud",
                    tone: route.transcription.isLocal ? .local : .cloud,
                    title: route.transcription.title,
                    detail: route.transcription.detail
                )
                RouteConnector()
                if let polish = route.polish {
                    RouteNode(systemImage: "cloud", tone: .cloud, title: polish.title, detail: polish.detail)
                } else {
                    Button {
                        shell.openSettingsTab(.polish)
                    } label: {
                        Label("Polish off", systemImage: "wand.and.stars")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PopoverPalette.muted)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .overlay(
                                Capsule()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                    .foregroundStyle(PopoverPalette.muted.opacity(0.6))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .instantHint("Polish is off. Open Polish settings to turn it on.", hoverHint: $hoverHint)
                }
                RouteConnector()
                RouteNode(
                    systemImage: route.isFinished ? "checkmark" : "doc.on.clipboard",
                    tone: .neutral,
                    title: deliveryTitle(route),
                    detail: deliveryDetail(route)
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: route.transcription.isLocal && route.polish == nil ? "lock.fill" : "cloud.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(route.staysOnMac ? PopoverPalette.local : PopoverPalette.cloud)
                (Text(route.lead)
                    .fontWeight(.semibold)
                    .foregroundColor(route.staysOnMac ? PopoverPalette.local : PopoverPalette.cloud)
                    + Text(route.rest.isEmpty ? "" : " " + route.rest)
                    .foregroundColor(.primary.opacity(0.8)))
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(PopoverPalette.hairline).frame(height: 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .popoverCard(radius: 16, elevated: false)
    }

    private func deliveryTitle(_ route: PopoverRoute) -> String {
        switch route.delivery {
        case .paste:
            return route.isFinished ? (shell.accessibilityPermissionGranted ? "Pasted" : "Copied") : "Paste"
        case .copy:
            return route.isFinished ? "Copied" : "Copy"
        case .none:
            return route.isFinished ? "Ready" : "Show here"
        }
    }

    private func deliveryDetail(_ route: PopoverRoute) -> String {
        switch route.delivery {
        case .paste:
            if route.isFinished {
                return shell.accessibilityPermissionGranted ? "And copied" : "Paste needs access"
            }
            return "Focused app"
        case .copy:
            return "Clipboard"
        case .none:
            return "In this popover"
        }
    }

    // MARK: Transcript card

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            transcriptHeader
            transcriptBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if effectiveMode != .changes, let note = vocabularyNote {
                vocabularyNoteView(note)
            }
            actionRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .popoverCard()
    }

    private var transcriptHeader: some View {
        HStack(spacing: 8) {
            if polishInRoute {
                Picker("Transcript", selection: $mode) {
                    ForEach(TranscriptMode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } else {
                Text("Transcript")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer(minLength: 8)
            if state == .polishing {
                ProgressView()
                    .controlSize(.mini)
                Text("Polishing")
                    .font(.system(size: 12))
                    .foregroundStyle(PopoverPalette.muted)
            } else if !displayedText.isEmpty {
                Text("\(PopoverFormat.wordCount(displayedText)) words")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(PopoverPalette.muted)
            }
        }
        .frame(minHeight: 28)
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if displayedText.isEmpty {
            placeholder
        } else {
            ScrollView {
                Text(attributedTranscript)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var attributedTranscript: AttributedString {
        if effectiveMode == .changes, !polishedText.isEmpty {
            return TranscriptHighlight.diff(from: rawText, to: polishedText)
        }
        return TranscriptHighlight.vocabulary(displayedText, terms: shell.rawTranscriptVocabularyFixes.map(\.term))
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: state == .failed ? "exclamationmark.triangle" : "text.alignleft")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PopoverPalette.muted)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PopoverPalette.subtle))
            }
            Text(placeholderText)
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderText: String {
        switch state {
        case .recording:
            switch delivery {
            case .paste:
                return "Keep talking. Your words land here the moment you stop, then paste into the app you are in."
            case .copy:
                return "Keep talking. Your words land here the moment you stop, and go to your clipboard."
            case .none:
                return "Keep talking. Your words land here the moment you stop."
            }
        case .finalizingAudio, .transcribing:
            return captureHint
        case .polishing:
            return "Polishing with \(ProviderNames.display(polishProviderID))"
        case .failed:
            return shell.lastError ?? "Something went wrong. Try transcribing again."
        case .completed, .idle:
            if sessionHadNoSpeech {
                return shell.currentSession?.metadata.audioActivity?.userGuidance ?? "No speech detected."
            }
            let hotkey = HotkeyDisplay.string(for: shell.settings.startStopHotkey)
            return "Press \(hotkey) to start. Your words land here."
        }
    }

    private var vocabularyNote: String? {
        let fixes = shell.rawTranscriptVocabularyFixes
        guard !fixes.isEmpty else { return nil }
        let listed = fixes.prefix(3).map { "“\($0.heard)” became \($0.term)" }
        var sentence = ListFormatter.localizedString(byJoining: Array(listed))
        if fixes.count > 3 {
            sentence += ", and \(fixes.count - 3) more"
        }
        let count = Set(fixes.map(\.term)).count
        let lead = count == 1 ? "1 word from your vocabulary." : "\(count) words from your vocabulary."
        return lead + "\n" + sentence + "."
    }

    private func vocabularyNoteView(_ note: String) -> some View {
        let parts = note.split(separator: "\n", maxSplits: 1).map(String.init)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PopoverPalette.local)
            (Text(parts.first ?? "").fontWeight(.semibold).foregroundColor(PopoverPalette.local)
                + Text(parts.count > 1 ? " " + parts[1] : ""))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PopoverPalette.localTint.opacity(0.6)))
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            Button {
                shell.copyText(displayedText, message: "Copied")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(PopoverButtonStyle(kind: .primary))
            .disabled(displayedText.isEmpty)
            .instantHint("Copy this text", hoverHint: $hoverHint)

            Spacer(minLength: 6)

            againControls

            Menu {
                Button("Reveal in Finder") {
                    shell.revealCurrentSessionInFinder()
                }
                Button("Copy Session Path") {
                    shell.copyCurrentSessionPath()
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .popoverMenuButton()
            .disabled(!hasSession)
            .accessibilityLabel("More actions")
        }
    }

    @ViewBuilder
    private var againControls: some View {
        if polishInRoute, effectiveMode != .raw {
            HStack(spacing: 4) {
                Button {
                    shell.retryPolish(
                        temporaryProviderID: selectedPolishOption?.providerID,
                        temporaryModel: selectedPolishOption?.model
                    )
                } label: {
                    Label("Polish again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PopoverButtonStyle())
                .disabled(rawText.isEmpty || isProcessing || isRecording || !shell.settings.polishEnabled)
                .instantHint("Polish this transcript again with the chosen model", hoverHint: $hoverHint)

                SearchableModelSelector(options: polishOptions, selectedID: $selectedPolishOptionID, disabled: !shell.settings.polishEnabled)
                    .frame(maxWidth: 130)
            }
        } else {
            HStack(spacing: 4) {
                Button {
                    shell.retryTranscription(
                        temporaryProviderID: selectedTranscriptionOption?.providerID,
                        temporaryModel: selectedTranscriptionOption?.model
                    )
                } label: {
                    Label("Transcribe again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PopoverButtonStyle())
                .disabled(!canTranscribeAgain)
                .instantHint("Transcribe this recording again with the chosen model", hoverHint: $hoverHint)

                SearchableModelSelector(options: transcriptionOptions, selectedID: $selectedTranscriptionOptionID, disabled: false)
                    .frame(maxWidth: 130)
            }
        }
    }

    private var canTranscribeAgain: Bool {
        hasAudioFile && !isRecording && !isProcessing
    }

    // MARK: Model options for running again

    private var transcriptionOptions: [RetryModelOption] {
        let manager = shell.modelManager
        var assets = manager.catalog.filter { $0.isTranscriptionModel && manager.isInstalled(modelID: $0.id) }
        if assets.isEmpty, let current = manager.asset(for: shell.settings.transcriptionModel) {
            assets = [current]
        }
        var options = assets.map { asset in
            RetryModelOption(
                id: "\(asset.kind.providerID)|\(asset.id)",
                title: asset.displayName,
                providerID: asset.kind.providerID,
                model: asset.id
            )
        }
        for providerID in ["openai_whisper", "openai_realtime_transcription", "groq_whisper", "openrouter_transcribe", "gemini_transcribe"] {
            options.append(contentsOf: verifiedOptions(providerID: providerID, usage: .transcription))
        }
        return options
    }

    private var polishOptions: [RetryModelOption] {
        var options: [RetryModelOption] = []
        for providerID in ["groq_polish", "openai_polish", "openrouter_polish", "gemini_polish", "cerebras_polish"] {
            options.append(contentsOf: verifiedOptions(providerID: providerID, usage: .polish))
        }
        if options.isEmpty {
            options = [RetryModelOption(
                id: "\(shell.settings.polishProviderID)|\(shell.settings.polishModel)",
                title: "\(ProviderNames.display(shell.settings.polishProviderID)) · \(ProviderNames.shortModel(shell.settings.polishModel))",
                providerID: shell.settings.polishProviderID,
                model: shell.settings.polishModel
            )]
        }
        return options
    }

    private func verifiedOptions(providerID: String, usage: ProviderModelUsage) -> [RetryModelOption] {
        guard shell.providerConnectivityStatus(for: providerID).state == .verified else {
            return []
        }
        return shell.availableModels(for: providerID, usage: usage).map { model in
            RetryModelOption(
                id: "\(providerID)|\(model)",
                title: "\(ProviderNames.display(providerID)) · \(ProviderNames.shortModel(model))",
                providerID: providerID,
                model: model
            )
        }
    }

    private var selectedTranscriptionOption: RetryModelOption? {
        transcriptionOptions.first(where: { $0.id == selectedTranscriptionOptionID }) ?? transcriptionOptions.first
    }

    private var selectedPolishOption: RetryModelOption? {
        polishOptions.first(where: { $0.id == selectedPolishOptionID }) ?? polishOptions.first
    }

    private func syncTranscriptionOption() {
        let preferred = "\(transcriptionProviderID)|\(transcriptionModelID)"
        if transcriptionOptions.contains(where: { $0.id == preferred }) {
            selectedTranscriptionOptionID = preferred
        } else if !transcriptionOptions.contains(where: { $0.id == selectedTranscriptionOptionID }) {
            selectedTranscriptionOptionID = transcriptionOptions.first?.id ?? ""
        }
    }

    private func syncPolishOption() {
        let preferred = "\(shell.settings.polishProviderID)|\(shell.settings.polishModel)"
        if polishOptions.contains(where: { $0.id == preferred }) {
            selectedPolishOptionID = preferred
        } else if !polishOptions.contains(where: { $0.id == selectedPolishOptionID }) {
            selectedPolishOptionID = polishOptions.first?.id ?? ""
        }
    }
}

// MARK: - Pieces

struct RouteNode: View {
    enum Tone {
        case local
        case cloud
        case neutral
    }

    let systemImage: String
    let tone: Tone
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(background))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(PopoverPalette.muted)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch tone {
        case .local:
            return PopoverPalette.local
        case .cloud:
            return PopoverPalette.cloud
        case .neutral:
            return .primary
        }
    }

    private var background: Color {
        switch tone {
        case .local:
            return PopoverPalette.localTint
        case .cloud:
            return PopoverPalette.cloudTint
        case .neutral:
            return PopoverPalette.subtle
        }
    }
}

struct RouteConnector: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(minWidth: 6, maxWidth: .infinity)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct WaveformBars: View {
    let levels: [Float]
    let barCount: Int
    let maxHeight: CGFloat
    let color: (_ index: Int, _ count: Int) -> Color

    var body: some View {
        let bars = paddedLevels
        HStack(alignment: .center, spacing: 3) {
            ForEach(bars.indices, id: \.self) { index in
                Capsule()
                    .fill(color(index, bars.count))
                    .frame(width: 3, height: max(4, CGFloat(bars[index]) * maxHeight))
            }
        }
        .frame(height: maxHeight)
    }

    /// Pads quiet bars on the left so the newest level sits at the right edge.
    private var paddedLevels: [Float] {
        let recent = Array(levels.suffix(barCount))
        return [Float](repeating: 0, count: max(0, barCount - recent.count)) + recent
    }
}

/// The waveform while recording; it reads the meter directly so only it redraws on each level.
/// Older levels fade toward the left, so the live edge on the right reads as the newest sound.
struct LiveWaveform: View {
    @EnvironmentObject private var meter: AudioMeterState

    var body: some View {
        WaveformBars(
            levels: meter.recentLevels,
            barCount: AudioMeterState.liveLevelCount,
            maxHeight: 56,
            color: { index, count in
                let age = Double(index) / Double(max(count - 1, 1))
                return Color.primary.opacity(0.18 + 0.72 * age * age)
            }
        )
    }
}

enum TranscriptHighlight {
    /// Marks each vocabulary term in the text.
    static func vocabulary(_ text: String, terms: [String]) -> AttributedString {
        var attributed = AttributedString(text)
        for term in Set(terms) where !term.isEmpty {
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: term, options: [.caseInsensitive]) {
                if isWholeWord(range, in: attributed) {
                    attributed[range].backgroundColor = PopoverPalette.localTint
                    attributed[range].foregroundColor = PopoverPalette.local
                }
                searchStart = range.upperBound
            }
        }
        return attributed
    }

    /// The polished text with removed words struck through and added words marked.
    static func diff(from raw: String, to polished: String) -> AttributedString {
        var result = AttributedString()
        for (index, token) in TranscriptDiff.words(from: raw, to: polished).enumerated() {
            var piece = AttributedString((index > 0 ? " " : "") + token.text)
            switch token.kind {
            case .same:
                break
            case .removed:
                piece.strikethroughStyle = .single
                piece.foregroundColor = PopoverPalette.muted
            case .added:
                piece.backgroundColor = PopoverPalette.cloudTint
                piece.foregroundColor = PopoverPalette.cloud
            }
            result += piece
        }
        return result
    }

    private static func isWholeWord(_ range: Range<AttributedString.Index>, in text: AttributedString) -> Bool {
        let characters = text.characters
        let before = range.lowerBound == characters.startIndex ? nil : characters[characters.index(before: range.lowerBound)]
        let after = range.upperBound == characters.endIndex ? nil : characters[range.upperBound]
        let isWordCharacter: (Character?) -> Bool = { $0.map { $0.isLetter || $0.isNumber } ?? false }
        return !isWordCharacter(before) && !isWordCharacter(after)
    }
}
