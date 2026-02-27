import AVFoundation
import SwiftUI

struct PopoverView: View {
    enum TranscriptTab: String, CaseIterable {
        case raw = "Raw"
        case polished = "Polished"
    }

    @EnvironmentObject private var shell: AppShell
    @StateObject private var playbackManager = AudioPlaybackManager()
    @State private var selectedTab: TranscriptTab = .polished
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputSection
            Divider()
            sessionSection
            Divider()
            textSection
            Divider()
            feedbackSection

            if let hotkeyError = shell.hotkeyError {
                Text("Hotkey issue: \(hotkeyError)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let lastError = shell.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            HStack {
                Text(shell.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(width: 500)
        .sheet(isPresented: Binding(get: { shell.pendingProposal != nil }, set: { _ in })) {
            if let proposal = shell.pendingProposal {
                RulesDiffSheet(diff: proposal.diffResult.unifiedDiff) {
                    shell.rejectRulesProposal()
                } onApprove: {
                    shell.approveRulesProposal()
                }
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Input")
                .font(.headline)

            Text(shell.currentSession?.metadata.inputDeviceName ?? "Device: \(AVAudioSessionBridge.defaultInputName)")
                .font(.subheadline)

            HStack(spacing: 8) {
                Text("Level")
                    .font(.caption)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 10)
                    Capsule()
                        .fill(shell.microphoneIndicatorColorName == "green" ? Color.green : Color.gray)
                        .frame(width: max(6, CGFloat(shell.meterLevel) * 220), height: 10)
                }
                .frame(width: 220)
            }

            Text(permissionText)
                .font(.caption)
                .foregroundColor(shell.permissionState == .authorized ? .secondary : .orange)
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session")
                .font(.headline)

            Text("State: \(shell.sessionState.rawValue)")
                .font(.subheadline)

            HStack {
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
                Text(session.paths.folderURL.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text")
                .font(.headline)

            Picker("Tab", selection: $selectedTab) {
                ForEach(TranscriptTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                if selectedTab == .raw {
                    TextEditor(text: Binding(
                        get: { shell.rawTranscript },
                        set: { shell.updateRawTranscriptFromEditor($0) }
                    ))
                    .font(.system(.body, design: .monospaced))
                } else {
                    ScrollView {
                        Text(shell.polishedTranscript.isEmpty ? "Polished transcript will appear here." : shell.polishedTranscript)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(minHeight: 120)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Copy Latest") {
                    shell.copyLatestPolished()
                }
                .buttonStyle(.bordered)

                Button("Retry Polish") {
                    shell.retryPolish()
                }
                .buttonStyle(.bordered)
                .disabled(shell.rawTranscript.isEmpty)
            }
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feedback")
                .font(.headline)

            TextEditor(text: $shell.feedbackText)
                .frame(height: 80)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Propose Rules Update") {
                shell.proposeRulesUpdateFromFeedback()
            }
            .buttonStyle(.bordered)
            .disabled(shell.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
}

struct RulesDiffSheet: View {
    let diff: String
    let onReject: () -> Void
    let onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposed Rules Diff")
                .font(.title3)

            ScrollView {
                Text(diff)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Reject") {
                    onReject()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Approve") {
                    onApprove()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 700, height: 520)
    }
}

enum AVAudioSessionBridge {
    static var defaultInputName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "Unknown input"
    }
}
