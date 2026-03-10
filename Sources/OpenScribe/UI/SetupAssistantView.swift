import AppKit
import SwiftUI

private enum SetupAssistantFocusTarget: Hashable {
    case pasteTarget
}

struct SetupAssistantView: View {
    private static let contentWidth: CGFloat = 780
    private static let minSheetHeight: CGFloat = 440
    private static let preferredSheetHeight: CGFloat = 680
    private static let bottomSpacing: CGFloat = 20
    private static let pasteFieldHeight: CGFloat = 56

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shell: AppShell
    @EnvironmentObject private var state: SetupAssistantWindowState
    @State private var pasteTargetText = ""
    @FocusState private var focusedField: SetupAssistantFocusTarget?

    private var expectedOutputText: String {
        shell.latestSetupAssistantOutputText(
            for: state.selectedTrack,
            selectedLocalModel: state.selectedLocalModel
        )
    }

    private var testFieldContainsOutput: Bool {
        let expected = expectedOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = pasteTargetText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !expected.isEmpty && actual == expected
    }

    private var checklistContext: SetupAssistantChecklistContext {
        var context = shell.setupAssistantContext(
            track: state.selectedTrack,
            selectedLocalModel: state.selectedLocalModel
        )
        context.testFieldContainsOutput = testFieldContainsOutput
        return context
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

    private var canPreparePasteTarget: Bool {
        switch state.selectedTrack {
        case .recommended:
            return checklistContext.groqKeySaved &&
                checklistContext.groqVerified &&
                checklistContext.transcriptionProviderID == SetupAssistantChecklist.recommendedTranscriptionProviderID &&
                checklistContext.transcriptionModel == SetupAssistantChecklist.recommendedTranscriptionModel &&
                checklistContext.languageMode == "auto" &&
                checklistContext.polishEnabled &&
                checklistContext.polishProviderID == SetupAssistantChecklist.recommendedPolishProviderID &&
                checklistContext.polishModel == SetupAssistantChecklist.recommendedPolishModel &&
                checklistContext.accessibilityPermissionGranted &&
                checklistContext.autoPasteEnabled
        case .local:
            return checklistContext.transcriptionProviderID == "whispercpp" &&
                checklistContext.transcriptionModel == state.selectedLocalModel &&
                checklistContext.languageMode == "auto" &&
                !checklistContext.polishEnabled &&
                checklistContext.localModelInstalled &&
                checklistContext.accessibilityPermissionGranted &&
                checklistContext.autoPasteEnabled
        }
    }

    private var recordingButtonTitle: String {
        shell.sessionState == .recording ? "Stop recording" : "Start recording"
    }

    private var recordingHotkeyDisplay: String {
        HotkeyDisplay.string(for: shell.settings.startStopHotkey)
    }

    private var maxSheetHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? Self.preferredSheetHeight
        return max(Self.minSheetHeight, min(Self.preferredSheetHeight, visibleHeight - 140))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
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

                    trackDetailsCard
                    checklistCard
                }
                .padding(22)
                .padding(.bottom, Self.bottomSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            footer
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
        }
        .frame(width: Self.contentWidth)
        .frame(minHeight: Self.minSheetHeight, maxHeight: maxSheetHeight)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            focusPasteTargetIfNeeded()
        }
        .onChange(of: canPreparePasteTarget) { _, _ in
            focusPasteTargetIfNeeded()
        }
        .onChange(of: state.selectedTrack) { _, _ in
            resetPasteTarget()
            focusPasteTargetIfNeeded()
        }
        .onChange(of: state.selectedLocalModel) { _, _ in
            resetPasteTarget()
            focusPasteTargetIfNeeded()
        }
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
                Text("Follow the checklist in order. Each row includes the action that completes it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trackDetailsCard: some View {
        setupCard(state.selectedTrack == .recommended ? "GROQ KEY" : "LOCAL MODEL") {
            switch state.selectedTrack {
            case .recommended:
                SecureField("Groq API key", text: $shell.groqKeyInput)

                Text("Paste your Groq key here, then use the checklist rows to save and verify it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .local:
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
            }
        }
    }

    private var checklistCard: some View {
        setupCard("CHECKLIST") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(checklistItems.enumerated()), id: \.element.id) { index, item in
                    checklistRow(item, isUnlocked: isUnlocked(itemAt: index))
                }
            }

            if !shell.statusMessage.isEmpty {
                Text(shell.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isUnlocked(itemAt index: Int) -> Bool {
        let item = checklistItems[index]
        if item.id.hasSuffix("pasteTest") {
            return canPreparePasteTarget
        }
        guard index > 0 else {
            return true
        }
        return checklistItems[..<index].allSatisfy(\.isComplete)
    }

    @ViewBuilder
    private func checklistRow(_ item: SetupAssistantChecklistItem, isUnlocked: Bool) -> some View {
        Group {
            if item.id.hasSuffix("pasteTest") {
                VStack(alignment: .leading, spacing: 10) {
                    checklistSummary(item, isUnlocked: isUnlocked)
                    checklistActions(for: item, isUnlocked: isUnlocked)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        checklistSummary(item, isUnlocked: isUnlocked)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        checklistActions(for: item, isUnlocked: isUnlocked)
                            .frame(width: 300, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        checklistSummary(item, isUnlocked: isUnlocked)
                        checklistActions(for: item, isUnlocked: isUnlocked)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(isUnlocked || item.isComplete ? 1 : 0.65)
    }

    private func checklistSummary(_ item: SetupAssistantChecklistItem, isUnlocked: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isComplete ? Color.green : (isUnlocked ? Color.secondary : Color.secondary.opacity(0.55)))
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func checklistActions(for item: SetupAssistantChecklistItem, isUnlocked: Bool) -> some View {
        switch item.id {
        case "recommended.keySaved":
            actionGroup {
                Link("Create Groq key", destination: URL(string: "https://console.groq.com/keys")!)
                    .buttonStyle(.link)

                Button("Save key") {
                    shell.saveAPIKeys()
                }
                .buttonStyle(.bordered)
                .disabled(!isUnlocked || isGroqInputEmpty)
            }
        case "recommended.keyVerified":
            actionGroup {
                Button("Verify") {
                    shell.verifyProvider(for: "groq_polish")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isUnlocked || isGroqInputEmpty)

                Button("Save and verify") {
                    shell.saveAPIKeysAndVerifyProvider(for: "groq_polish")
                }
                .buttonStyle(.bordered)
                .disabled(!isUnlocked || isGroqInputEmpty)
            }
        case "recommended.setup":
            actionGroup {
                Button("Set recommended setup") {
                    shell.applyRecommendedHostedSetup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isUnlocked)
            }
        case "local.setup":
            actionGroup {
                Button("Apply local setup") {
                    shell.applyLocalOnlySetup(modelID: state.selectedLocalModel)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isUnlocked)
            }
        case "local.model":
            actionGroup {
                Button("Download model") {
                    shell.installWhisperModel(state.selectedLocalModel)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isUnlocked)
            }
        case "recommended.recording", "local.recording":
            actionGroup {
                Button(recordingButtonTitle) {
                    preparePasteTargetForRecording()
                    shell.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isUnlocked)
            }
        case "recommended.accessibility", "local.accessibility":
            actionGroup {
                Button("Open Accessibility Settings") {
                    shell.openAccessibilityPrivacySettings()
                }
                .buttonStyle(.bordered)
                .disabled(!isUnlocked)

                Button("Refresh") {
                    shell.refreshPermissionState()
                }
                .buttonStyle(.bordered)
                .disabled(!isUnlocked)
            }
        case "recommended.autopaste", "local.autopaste":
            Toggle("Auto-paste", isOn: $shell.autoPasteOnComplete)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!isUnlocked)
        case "recommended.pasteTest", "local.pasteTest":
            VStack(alignment: .leading, spacing: 8) {
                actionGroup {
                    Button("Focus test field") {
                        focusedField = .pasteTarget
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isUnlocked)

                    Button("Paste latest transcript") {
                        focusedField = .pasteTarget
                        shell.pasteLatestTranscript(
                            for: state.selectedTrack,
                            selectedLocalModel: state.selectedLocalModel
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isUnlocked || expectedOutputText.isEmpty)

                    Button("Clear") {
                        pasteTargetText = ""
                        focusedField = .pasteTarget
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isUnlocked)
                }

                TextEditor(text: $pasteTargetText)
                    .font(.system(size: 12))
                    .frame(minHeight: Self.pasteFieldHeight)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .focused($focusedField, equals: .pasteTarget)
                    .disabled(!isUnlocked)
            }
        default:
            EmptyView()
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

    private func actionGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                content()
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }

    private func preparePasteTargetForRecording() {
        focusPasteTarget()
    }

    private func focusPasteTargetIfNeeded() {
        guard canPreparePasteTarget && !testFieldContainsOutput else {
            return
        }
        focusPasteTarget()
    }

    private func focusPasteTarget() {
        DispatchQueue.main.async {
            focusedField = .pasteTarget
        }
    }

    private func resetPasteTarget() {
        pasteTargetText = ""
        focusedField = nil
    }
}
