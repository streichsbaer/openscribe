import SwiftUI

struct SetupAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shell: AppShell
    @EnvironmentObject private var state: SetupAssistantWindowState

    private var checklistContext: SetupAssistantChecklistContext {
        shell.setupAssistantContext(selectedLocalModel: state.selectedLocalModel)
    }

    private var checklistItems: [SetupAssistantChecklistItem] {
        SetupAssistantChecklist.items(for: state.selectedTrack, context: checklistContext)
    }

    private var isComplete: Bool {
        SetupAssistantChecklist.isComplete(for: state.selectedTrack, context: checklistContext)
    }

    private var localModelOption: SetupAssistantLocalModelOption {
        SetupAssistantChecklist.localModelOptions.first(where: { $0.id == state.selectedLocalModel })
            ?? SetupAssistantChecklist.localModelOptions[0]
    }

    private var isGroqInputEmpty: Bool {
        shell.groqKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recordingButtonTitle: String {
        shell.sessionState == .recording ? "Stop test recording" : "Start test recording"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Picker("Track", selection: Binding(
                get: { state.selectedTrack },
                set: { newValue in
                    state.selectedTrack = newValue
                    shell.setupAssistantPreferredTrack = newValue
                }
            )) {
                ForEach(SetupAssistantTrack.allCases) { track in
                    Text(track.title).tag(track)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch state.selectedTrack {
                case .recommended:
                    recommendedSetupCard
                case .local:
                    localSetupCard
                }
            }

            checklistCard

            footer
        }
        .padding(22)
        .frame(width: 720)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setup Assistant")
                .font(.system(size: 24, weight: .semibold))

            Text(state.selectedTrack.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isComplete {
                Text("This setup path is complete. You can close this and start using OpenScribe.")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("Follow the checklist until every item is complete, then make one short test recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recommendedSetupCard: some View {
        setupCard("GROQ KEY") {
            SecureField("Groq API key", text: $shell.groqKeyInput)

            Text("Create a Groq key, paste it here, then save and verify it inside OpenScribe.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Link("Create Groq key", destination: URL(string: "https://console.groq.com/keys")!)
                    .buttonStyle(.link)

                Spacer()

                Button("Save key") {
                    shell.saveAPIKeys()
                }
                .buttonStyle(.bordered)
                .disabled(isGroqInputEmpty)

                Button("Save and verify") {
                    shell.saveAPIKeysAndVerifyProvider(for: "groq_polish")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGroqInputEmpty)
            }

            HStack(spacing: 8) {
                Button("Apply recommended setup") {
                    shell.applyRecommendedHostedSetup()
                }
                .buttonStyle(.borderedProminent)

                Button(recordingButtonTitle) {
                    shell.toggleRecording()
                }
                .buttonStyle(.bordered)

                if shell.permissionState != .authorized {
                    Button("Open Microphone Settings") {
                        shell.openMicrophonePrivacySettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var localSetupCard: some View {
        setupCard("LOCAL MODEL") {
            Picker("Model", selection: $state.selectedLocalModel) {
                ForEach(SetupAssistantChecklist.localModelOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: state.selectedLocalModel) { _, newValue in
                if SetupAssistantChecklist.localModelOptions.contains(where: { $0.id == newValue }) {
                    shell.setupAssistantPreferredTrack = .local
                }
            }

            Text(localModelOption.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Apply local setup") {
                    shell.applyLocalOnlySetup(modelID: state.selectedLocalModel)
                }
                .buttonStyle(.borderedProminent)

                Button("Download model") {
                    shell.installWhisperModel(state.selectedLocalModel)
                }
                .buttonStyle(.bordered)

                Button(recordingButtonTitle) {
                    shell.toggleRecording()
                }
                .buttonStyle(.bordered)

                if shell.permissionState != .authorized {
                    Button("Open Microphone Settings") {
                        shell.openMicrophonePrivacySettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var checklistCard: some View {
        setupCard("CHECKLIST") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(checklistItems) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isComplete ? Color.green : Color.secondary)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))

                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }

            if !shell.statusMessage.isEmpty {
                Text(shell.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(isComplete ? "Close" : "Skip for now") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)

            Button("Do not show again") {
                shell.setSetupAssistantDoNotShowAgain(true)
                dismiss()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Refresh status") {
                shell.refreshPermissionState()
            }
            .buttonStyle(.bordered)
        }
    }

    private func setupCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.7)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}
