import AVFoundation
import Foundation
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var shell: AppShell
    @StateObject private var playbackManager = AudioPlaybackManager()
    @AppStorage("ui.transcriptPanelsExpanded") private var expandedTextPanels = false
    @State private var selectedRetryApproachID = "whispercpp-base"
    @State private var selectedRetryPolishModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            inputSection
            sessionSection
            textSection

            footerSection
        }
        .padding(12)
        .frame(width: popoverWidth, height: popoverHeight)
        .onAppear {
            shell.updatePopoverSize(expandedTextPanels: expandedTextPanels)
            syncRetryPolishSelection()
            syncRetryTranscriptionSelection()
        }
        .onChange(of: expandedTextPanels) { _, newValue in
            shell.updatePopoverSize(expandedTextPanels: newValue)
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
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Label("SmartTranscript", systemImage: "waveform.badge.mic")
                .font(.headline)

            Spacer()

            stateChip
        }
    }

    private var inputSection: some View {
        card(title: "Input") {
            VStack(alignment: .leading, spacing: 8) {
                keyValueRow("Device", shell.currentSession?.metadata.inputDeviceName ?? AVAudioSessionBridge.defaultInputName)

                HStack(spacing: 10) {
                    Text("Level")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.18))
                            .frame(height: 9)

                        Capsule()
                            .fill(shell.microphoneIndicatorColorName == "green" ? Color.green : Color.gray)
                            .frame(width: max(8, CGFloat(shell.meterLevel) * 240), height: 9)
                    }
                    .frame(width: 240)
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
                keyValueRow("State", shell.sessionState.rawValue)

                HStack(spacing: 8) {
                    Button(shell.sessionState == .recording ? "Stop (Fn+Space)" : "Start (Fn+Space)") {
                        shell.toggleRecording()
                    }
                    .buttonStyle(.borderedProminent)

                    if let audioURL = shell.currentSession?.paths.audioURL,
                       FileManager.default.fileExists(atPath: audioURL.path) {
                        Button(playbackManager.isPlaying ? "Stop Audio" : "Play Audio") {
                            playbackManager.toggle(url: audioURL)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Reveal") {
                        shell.revealCurrentSessionInFinder()
                    }
                    .buttonStyle(.bordered)
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
                        .help("Copy session path")
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
            .help(expandedTextPanels ? "Compact transcript panels" : "Expand transcript panels")
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Raw transcript")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(rawSourceSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 8)

                    HStack(alignment: .center, spacing: 8) {
                        Picker("Transcriber", selection: $selectedRetryApproachID) {
                            ForEach(retryApproaches) { approach in
                                Text(approach.title)
                                    .tag(approach.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize(horizontal: true, vertical: false)

                        Button("Re-Transcribe") {
                            shell.retryTranscription(
                                temporaryProviderID: selectedRetryApproach.providerID,
                                temporaryModel: selectedRetryApproach.model
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!canRetryTranscription)

                        Button {
                            shell.copyRawTranscript()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy raw transcript")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                rawTranscriptPanel

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Polished transcript")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(polishedSourceSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 8)

                    HStack(alignment: .center, spacing: 8) {
                        Picker("Polish retry model", selection: $selectedRetryPolishModel) {
                            ForEach(retryPolishModels, id: \.self) { model in
                                Text(model)
                                    .tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize(horizontal: true, vertical: false)
                        .disabled(!shell.settings.polishEnabled)

                        Button("Re-Polish") {
                            shell.retryPolish(temporaryModel: selectedRetryPolishModel)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(shell.rawTranscript.isEmpty || !shell.settings.polishEnabled)

                        Button {
                            shell.copyLatestPolished()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy polished transcript")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                ScrollView {
                    Text(polishedBodyText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: textPanelHeight)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let hotkeyError = shell.hotkeyError {
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
            stateChipLabel("Polishing \(formattedDuration(shell.polishElapsedSeconds))", color: .pink)
        default:
            stateChipLabel(shell.sessionState.rawValue.capitalized, color: stateChipColor)
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
            return .pink
        case .failed:
            return .red
        case .completed:
            return .blue
        case .idle:
            return .gray
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

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

    private var textPanelHeight: CGFloat {
        expandedTextPanels ? 220 : 120
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
        .frame(height: textPanelHeight)
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

    private var retryApproaches: [RetryTranscriptionApproach] {
        return [
            RetryTranscriptionApproach(id: "whispercpp-base", title: "Local whisper.cpp / base", providerID: "whispercpp", model: "base"),
            RetryTranscriptionApproach(id: "whispercpp-tiny", title: "Local whisper.cpp / tiny", providerID: "whispercpp", model: "tiny"),
            RetryTranscriptionApproach(id: "whispercpp-small", title: "Local whisper.cpp / small", providerID: "whispercpp", model: "small"),
            RetryTranscriptionApproach(id: "whispercpp-medium", title: "Local whisper.cpp / medium", providerID: "whispercpp", model: "medium"),
            RetryTranscriptionApproach(id: "openai-gpt-4o-mini-transcribe", title: "OpenAI / gpt-4o-mini-transcribe", providerID: "openai_whisper", model: "gpt-4o-mini-transcribe"),
            RetryTranscriptionApproach(id: "openai-gpt-4o-transcribe", title: "OpenAI / gpt-4o-transcribe", providerID: "openai_whisper", model: "gpt-4o-transcribe"),
            RetryTranscriptionApproach(id: "openai-whisper-1", title: "OpenAI / whisper-1", providerID: "openai_whisper", model: "whisper-1"),
            RetryTranscriptionApproach(id: "groq-whisper-large-v3", title: "Groq / whisper-large-v3", providerID: "groq_whisper", model: "whisper-large-v3"),
            RetryTranscriptionApproach(id: "groq-whisper-large-v3-turbo", title: "Groq / whisper-large-v3-turbo", providerID: "groq_whisper", model: "whisper-large-v3-turbo")
        ]
    }

    private var selectedRetryApproach: RetryTranscriptionApproach {
        retryApproaches.first(where: { $0.id == selectedRetryApproachID }) ?? retryApproaches[0]
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

    private var retryPolishModels: [String] {
        if !shell.settings.polishEnabled {
            return [shell.settings.polishModel]
        }
        switch shell.settings.polishProviderID {
        case "openai_polish":
            return ["gpt-5-mini"]
        case "groq_polish":
            return ["llama-3.3-70b-versatile", "mixtral-8x7b-32768"]
        default:
            return [shell.settings.polishModel]
        }
    }

    private func syncRetryPolishSelection() {
        if retryPolishModels.contains(selectedRetryPolishModel) {
            return
        }
        if retryPolishModels.contains(shell.settings.polishModel) {
            selectedRetryPolishModel = shell.settings.polishModel
            return
        }
        selectedRetryPolishModel = retryPolishModels.first ?? shell.settings.polishModel
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

    private func providerDisplayName(for providerID: String) -> String {
        switch providerID {
        case "whispercpp":
            return "Local whisper.cpp"
        case "openai_whisper":
            return "OpenAI"
        case "groq_whisper":
            return "Groq"
        case "openai_polish":
            return "OpenAI"
        case "groq_polish":
            return "Groq"
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

    private var popoverWidth: CGFloat {
        expandedTextPanels ? 620 : 540
    }

    private var popoverHeight: CGFloat {
        expandedTextPanels ? 980 : 760
    }
}

private struct RetryTranscriptionApproach: Identifiable {
    let id: String
    let title: String
    let providerID: String?
    let model: String?
}

enum AVAudioSessionBridge {
    static var defaultInputName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "Unknown input"
    }
}
