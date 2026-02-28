import AVFoundation
import Foundation
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var shell: AppShell
    @StateObject private var playbackManager = AudioPlaybackManager()
    @AppStorage("ui.transcriptPanelsExpanded") private var expandedTextPanels = false
    @State private var selectedRetryApproachID = "current"

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
        }
        .onChange(of: expandedTextPanels) { _, newValue in
            shell.updatePopoverSize(expandedTextPanels: newValue)
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
        card(title: "Text") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Raw transcript")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button("Copy Raw") {
                        shell.copyRawTranscript()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Picker("Transcriber", selection: $selectedRetryApproachID) {
                        ForEach(retryApproaches) { approach in
                            Text(approach.title)
                                .tag(approach.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 220)

                    Button("Re-Transcribe") {
                        shell.retryTranscription(
                            temporaryProviderID: selectedRetryApproach.providerID,
                            temporaryModel: selectedRetryApproach.model
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canRetryTranscription)

                    Button(expandedTextPanels ? "Compact" : "Expand") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandedTextPanels.toggle()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                rawTranscriptPanel

                HStack(alignment: .center, spacing: 8) {
                    Text("Polished transcript")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Copy Polished") {
                        shell.copyLatestPolished()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Retry Polish") {
                        shell.retryPolish()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(shell.rawTranscript.isEmpty)
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
            stateChipLabel("Polishing \(formattedDuration(shell.polishElapsedSeconds))", color: .orange)
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
        case .transcribing, .polishing, .finalizingAudio:
            return .orange
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
        let current = RetryTranscriptionApproach(
            id: "current",
            title: "Current (\(transcriberDisplayName(for: shell.settings.transcriptionProviderID)) / \(shell.settings.transcriptionModel))",
            providerID: nil,
            model: nil
        )

        return [
            current,
            RetryTranscriptionApproach(id: "whispercpp-base", title: "Local whisper.cpp / base", providerID: "whispercpp", model: "base"),
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

    private func transcriberDisplayName(for providerID: String) -> String {
        switch providerID {
        case "whispercpp":
            return "Local whisper.cpp"
        case "openai_whisper":
            return "OpenAI"
        case "groq_whisper":
            return "Groq"
        default:
            return providerID
        }
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
