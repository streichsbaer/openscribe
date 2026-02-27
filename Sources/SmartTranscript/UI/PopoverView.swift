import AVFoundation
import Foundation
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var shell: AppShell
    @StateObject private var playbackManager = AudioPlaybackManager()
    @AppStorage("ui.transcriptPanelsExpanded") private var expandedTextPanels = false

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

            VStack(alignment: .trailing, spacing: 4) {
                stateChip

                if shell.sessionState == .recording,
                   let createdAt = shell.currentSession?.metadata.createdAt {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text("Recording \(formattedDuration(Int(timeline.date.timeIntervalSince(createdAt))))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else if shell.sessionState == .polishing {
                    Text("Polishing \(formattedDuration(shell.polishElapsedSeconds))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
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

                    Spacer()

                    Button(expandedTextPanels ? "Compact" : "Expand") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandedTextPanels.toggle()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                TextEditor(text: Binding(
                    get: { shell.rawTranscript },
                    set: { shell.updateRawTranscriptFromEditor($0) }
                ))
                .font(.body)
                .frame(height: textPanelHeight)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("Polished transcript")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if shell.sessionState == .polishing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Polishing in progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                HStack(spacing: 8) {
                    Button("Copy Path") {
                        shell.copyCurrentSessionPath()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Raw") {
                        shell.copyRawTranscript()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Polished") {
                        shell.copyLatestPolished()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Retry Polish") {
                        shell.retryPolish()
                    }
                    .buttonStyle(.bordered)
                    .disabled(shell.rawTranscript.isEmpty)
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

    private var stateChip: some View {
        Text(shell.sessionState.rawValue.capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(stateChipColor.opacity(0.15))
            .foregroundColor(stateChipColor)
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

    private var popoverWidth: CGFloat {
        expandedTextPanels ? 620 : 540
    }

    private var popoverHeight: CGFloat {
        expandedTextPanels ? 980 : 760
    }
}

enum AVAudioSessionBridge {
    static var defaultInputName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "Unknown input"
    }
}
