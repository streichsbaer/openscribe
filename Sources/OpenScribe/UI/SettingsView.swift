import AppKit
import Carbon
import SwiftUI

enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    case general
    case providers
    case hotkeys
    case rules
    case data
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .providers:
            return "Providers"
        case .hotkeys:
            return "Hotkeys"
        case .rules:
            return "Rules"
        case .data:
            return "Data"
        case .about:
            return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general:
            return "gearshape"
        case .providers:
            return "square.grid.2x2"
        case .hotkeys:
            return "keyboard"
        case .rules:
            return "doc.text"
        case .data:
            return "externaldrive"
        case .about:
            return "info.circle"
        }
    }

    var preferredSize: CGSize {
        switch self {
        case .general:
            return CGSize(width: 760, height: 580)
        case .providers:
            return CGSize(width: 860, height: 700)
        case .hotkeys:
            return CGSize(width: 860, height: 700)
        case .rules:
            return CGSize(width: 920, height: 760)
        case .data:
            return CGSize(width: 920, height: 760)
        case .about:
            return CGSize(width: 760, height: 580)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var shell: AppShell
    @EnvironmentObject private var tabState: SettingsTabState
    @State private var contentWidth = SettingsTab.general.preferredSize.width
    @State private var contentHeight = SettingsTab.general.preferredSize.height
    @State private var pendingLocalModelAction: LocalModelAction?
    @State private var showDeleteAppSupportConfirmation = false
    @State private var sttModelFilter = ""
    @State private var polishModelFilter = ""
    @State private var transcriptionInstructionDraft = ""
    @State private var polishInstructionDraft = ""
    @State private var showTranscriptionInstructionEditor = false
    @State private var showPolishInstructionEditor = false
    @FocusState private var focusedInstructionEditor: InstructionEditorTarget?
    @AppStorage("ui.transcriptPanelsExpanded") private var transcriptPanelsExpanded = false
    private let onPreferredSizeChange: ((CGSize, Bool) -> Void)?
    private let providerPickerWidth: CGFloat = 240
    private let modelSelectorWidth: CGFloat = 360
    private let transcriptionDefaultInstruction = "No instruction set."
    private let polishDefaultInstruction = "No instruction set."

    private let sttProviders = [
        (id: "whispercpp", label: "Local whisper.cpp"),
        (id: "openai_whisper", label: "OpenAI Speech-to-Text"),
        (id: "groq_whisper", label: "Groq Whisper"),
        (id: "openrouter_transcribe", label: "OpenRouter Transcription"),
        (id: "gemini_transcribe", label: "Gemini Transcription")
    ]

    private let polishProviders = [
        (id: "openai_polish", label: "OpenAI"),
        (id: "groq_polish", label: "Groq"),
        (id: "openrouter_polish", label: "OpenRouter"),
        (id: "gemini_polish", label: "Gemini")
    ]
    private let authorGitHubURL = URL(string: "https://github.com/streichsbaer")!
    private let authorXURL = URL(string: "https://x.com/s_streichsbier")!
    private let repositoryURL = URL(string: "https://github.com/streichsbaer/openscribe")!
    private let soulGitHubURL = URL(string: "https://github.com/streichsbaer/openscribe/blob/main/SOUL.md")!
    private let agentsGitHubURL = URL(string: "https://github.com/streichsbaer/openscribe/blob/main/AGENTS.md")!

    init(onPreferredSizeChange: ((CGSize, Bool) -> Void)? = nil) {
        self.onPreferredSizeChange = onPreferredSizeChange
    }

    var body: some View {
        VStack(spacing: 0) {
            tabHeader
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()

            currentTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: contentWidth, height: contentHeight)
        .onAppear {
            updateLayout(for: tabState.selectedTab, animate: false)
        }
        .onChange(of: tabState.selectedTab) { _, newValue in
            updateLayout(for: newValue, animate: true)
        }
        .confirmationDialog(
            pendingLocalModelAction?.dialogTitle ?? "Confirm",
            isPresented: Binding(
                get: { pendingLocalModelAction != nil },
                set: { newValue in
                    if !newValue {
                        pendingLocalModelAction = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingLocalModelAction
        ) { action in
            switch action {
            case .download(let modelID, _):
                Button("Download") {
                    shell.installWhisperModel(modelID)
                    pendingLocalModelAction = nil
                }
            case .delete(let modelID, _):
                Button("Delete", role: .destructive) {
                    shell.removeWhisperModel(modelID)
                    pendingLocalModelAction = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingLocalModelAction = nil
            }
        } message: { action in
            Text(action.dialogMessage)
        }
        .confirmationDialog(
            "Delete App Support Data",
            isPresented: $showDeleteAppSupportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                shell.moveAppSupportToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves OpenScribe local sessions, models, rules, and settings to Trash.")
        }
    }

    private var tabHeader: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            ForEach(SettingsTab.allCases) { tab in
                Button {
                    tabState.selectedTab = tab
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tabState.selectedTab == tab ? Color.accentColor.opacity(0.13) : Color.clear)

                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 14, weight: .medium))
                            Text(tab.title)
                                .font(.caption)
                        }
                        .foregroundStyle(tabState.selectedTab == tab ? Color.accentColor : Color.secondary)
                    }
                    .frame(width: 98, height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var currentTabContent: some View {
        switch tabState.selectedTab {
        case .general:
            generalTab
        case .providers:
            providersTab
        case .hotkeys:
            hotkeysTab
        case .rules:
            rulesTab
        case .data:
            dataTab
        case .about:
            aboutTab
        }
    }

    private func updateLayout(for tab: SettingsTab, animate: Bool) {
        let preferred = tab.preferredSize
        let apply = {
            contentWidth = preferred.width
            contentHeight = preferred.height
            onPreferredSizeChange?(preferred, animate)
        }
        if animate {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                apply()
            }
        } else {
            apply()
        }
    }

    private var generalTab: some View {
        settingsPage {
            settingsCard("USAGE") {
                settingRow("Appearance") {
                    Picker("", selection: Binding(
                        get: { shell.settings.appearanceMode },
                        set: { newValue in
                            shell.updateSettings { settings in
                                settings.appearanceMode = newValue
                            }
                        }
                    )) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: providerPickerWidth, alignment: .trailing)
                }

                settingRow("Copy polished on completion") {
                    Toggle("", isOn: Binding(
                        get: { shell.settings.copyOnComplete },
                        set: { newValue in
                            shell.updateSettings { settings in
                                settings.copyOnComplete = newValue
                            }
                        }
                    ))
                    .labelsHidden()
                }

                settingRow("Auto-paste on completion") {
                    Toggle("", isOn: $shell.autoPasteOnComplete)
                        .labelsHidden()
                }

                if shell.autoPasteOnComplete {
                    Text(shell.accessibilityPermissionGranted
                         ? "Auto-paste enabled. Completed output will paste into the currently focused app."
                         : "Auto-paste enabled but Accessibility permission is missing. Open Accessibility Settings in Hotkeys.")
                        .font(.caption)
                        .foregroundColor(shell.accessibilityPermissionGranted ? .secondary : .orange)
                }

                settingRow("Expanded transcript panels by default") {
                    Toggle("", isOn: $transcriptPanelsExpanded)
                        .labelsHidden()
                }

                Text("Retention policy: keep all session artifacts until manually deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard("STATUS") {
                settingRow("Session state") {
                    Text(shell.sessionState.displayLabel)
                        .foregroundStyle(.secondary)
                }

                settingRow("Last message") {
                    Text(shell.statusMessage)
                        .foregroundStyle(.secondary)
                }

                if let hotkeyError = shell.hotkeyError {
                    Text(hotkeyError)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            settingsCard("MICROPHONE") {
                settingRow("System default") {
                    Text(shell.systemDefaultMicrophoneName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: providerPickerWidth, alignment: .trailing)
                }

                settingRow("Pinned default") {
                    Picker("Pinned default", selection: pinnedMicrophoneSelection) {
                        Text("System default (no pin)").tag("")
                        if let pinned = shell.settings.pinnedMicrophone,
                           !shell.isMicrophoneCurrentlyAvailable(pinned.id) {
                            Text("Pinned unavailable: \(pinned.name)").tag(pinned.id)
                        }
                        ForEach(shell.availableMicrophones) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: providerPickerWidth, alignment: .trailing)
                }

                if let pinned = shell.settings.pinnedMicrophone,
                   !shell.isMicrophoneCurrentlyAvailable(pinned.id) {
                    Text("Pinned microphone \"\(pinned.name)\" is currently unavailable.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text(microphonePermissionSummary)
                    .font(.caption)
                    .foregroundColor(shell.permissionState == .authorized ? .secondary : .orange)

                HStack(spacing: 8) {
                    Button("Open Microphone Settings") {
                        shell.openMicrophonePrivacySettings()
                    }
                    .buttonStyle(.bordered)

                    Button("Refresh") {
                        shell.refreshPermissionState()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var providersTab: some View {
        settingsPage {
            settingsCard("TRANSCRIPTION") {
                settingRow("Provider") {
                    Picker("", selection: Binding(
                        get: { shell.settings.transcriptionProviderID },
                        set: { newValue in
                            shell.updateSettings {
                                $0.transcriptionProviderID = newValue
                                let available = transcriptionModels(for: newValue)
                                if !available.contains($0.transcriptionModel) {
                                    $0.transcriptionModel = available.first ?? $0.transcriptionModel
                                }
                            }
                            shell.refreshModels(for: newValue)
                        }
                    )) {
                        ForEach(sttProviders, id: \.id) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: providerPickerWidth, alignment: .trailing)
                }

                settingRow("Models") {
                    FilterableModelSelector(
                        models: transcriptionModels(for: shell.settings.transcriptionProviderID),
                        selectedModel: shell.settings.transcriptionModel,
                        filterText: $sttModelFilter,
                        width: modelSelectorWidth,
                        isDisabled: false
                    ) { selected in
                        shell.updateSettings { settings in
                            settings.transcriptionModel = selected
                        }
                    }
                }

                settingRow("Provider status") {
                    HStack(spacing: 8) {
                        Button("Verify") {
                            shell.verifyProvider(for: shell.settings.transcriptionProviderID)
                        }
                        .buttonStyle(.bordered)

                        Button("Refresh models") {
                            shell.refreshModels(for: shell.settings.transcriptionProviderID)
                        }
                        .buttonStyle(.bordered)

                        Text(shell.providerConnectivityStatus(for: shell.settings.transcriptionProviderID).detail)
                            .font(.caption)
                            .foregroundColor(
                                connectivityColor(shell.providerConnectivityStatus(for: shell.settings.transcriptionProviderID))
                            )
                    }
                    .frame(width: providerPickerWidth, alignment: .trailing)
                }

                settingRow("Instruction") {
                    let providerID = shell.settings.transcriptionProviderID
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use custom instruction", isOn: Binding(
                            get: { shell.settings.transcriptionCustomInstructionEnabled == true },
                            set: { newValue in
                                if !newValue {
                                    focusedInstructionEditor = nil
                                    showTranscriptionInstructionEditor = false
                                }
                                shell.updateSettings { settings in
                                    settings.transcriptionCustomInstructionEnabled = newValue
                                }
                            }
                        ))

                        instructionPreviewRow(
                            text: resolvedInstructionText(
                                draftText: transcriptionInstructionDraft,
                                fallback: transcriptionDefaultInstruction
                            ),
                            isDefault: isUsingDefaultInstruction(
                                draftText: transcriptionInstructionDraft
                            ),
                            width: modelSelectorWidth
                        )

                        Button(showTranscriptionInstructionEditor ? "Done" : "Edit") {
                            toggleTranscriptionInstructionEditor()
                        }
                        .buttonStyle(.bordered)
                        .disabled(shell.settings.transcriptionCustomInstructionEnabled != true)

                        if showTranscriptionInstructionEditor, shell.settings.transcriptionCustomInstructionEnabled == true {
                            instructionEditor(
                                text: $transcriptionInstructionDraft,
                                placeholder: transcriptionDefaultInstruction,
                                width: modelSelectorWidth
                            )
                            .focused($focusedInstructionEditor, equals: .transcription)
                        }

                        if !supportsTranscriptionInstruction(providerID) {
                            Text("Current provider does not use this instruction. It applies when a provider-backed transcription model is selected.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: modelSelectorWidth, alignment: .leading)
                }

                settingRow("Language") {
                    Picker("", selection: Binding(
                        get: { shell.settings.languageMode },
                        set: { newValue in
                            shell.updateSettings { settings in
                                settings.languageMode = newValue
                            }
                        }
                    )) {
                        Text("auto").tag("auto")
                        Text("en").tag("en")
                        Text("de").tag("de")
                        Text("fr").tag("fr")
                        Text("es").tag("es")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: providerPickerWidth, alignment: .trailing)
                }
            }

            settingsCard("POLISH") {
                settingRow("Enable polish") {
                    Toggle("", isOn: Binding(
                        get: { shell.settings.polishEnabled },
                        set: { newValue in
                            shell.updateSettings { settings in
                                settings.polishEnabled = newValue
                            }
                        }
                    ))
                    .labelsHidden()
                }

                settingRow("Provider") {
                    Picker("", selection: Binding(
                        get: { shell.settings.polishProviderID },
                        set: { newValue in
                            shell.updateSettings {
                                $0.polishProviderID = newValue
                                let available = polishModels(for: newValue)
                                if !available.contains($0.polishModel) {
                                    $0.polishModel = available.first ?? $0.polishModel
                                }
                            }
                            shell.refreshModels(for: newValue)
                        }
                    )) {
                        ForEach(polishProviders, id: \.id) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: providerPickerWidth, alignment: .trailing)
                    .disabled(!shell.settings.polishEnabled)
                }

                settingRow("Models") {
                    FilterableModelSelector(
                        models: polishModels(for: shell.settings.polishProviderID),
                        selectedModel: shell.settings.polishModel,
                        filterText: $polishModelFilter,
                        width: modelSelectorWidth,
                        isDisabled: !shell.settings.polishEnabled
                    ) { selected in
                        shell.updateSettings { settings in
                            settings.polishModel = selected
                        }
                    }
                }

                settingRow("Provider status") {
                    HStack(spacing: 8) {
                        Button("Verify") {
                            shell.verifyProvider(for: shell.settings.polishProviderID)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!shell.settings.polishEnabled)

                        Button("Refresh models") {
                            shell.refreshModels(for: shell.settings.polishProviderID)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!shell.settings.polishEnabled)

                        Text(shell.providerConnectivityStatus(for: shell.settings.polishProviderID).detail)
                            .font(.caption)
                            .foregroundColor(
                                connectivityColor(shell.providerConnectivityStatus(for: shell.settings.polishProviderID))
                            )
                    }
                    .frame(width: providerPickerWidth, alignment: .trailing)
                }

                settingRow("Instruction") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use custom instruction", isOn: Binding(
                            get: { shell.settings.polishCustomInstructionEnabled == true },
                            set: { newValue in
                                if !newValue {
                                    focusedInstructionEditor = nil
                                    showPolishInstructionEditor = false
                                }
                                shell.updateSettings { settings in
                                    settings.polishCustomInstructionEnabled = newValue
                                }
                            }
                        ))
                        .disabled(!shell.settings.polishEnabled)

                        instructionPreviewRow(
                            text: resolvedInstructionText(
                                draftText: polishInstructionDraft,
                                fallback: polishDefaultInstruction
                            ),
                            isDefault: isUsingDefaultInstruction(
                                draftText: polishInstructionDraft
                            ),
                            width: modelSelectorWidth
                        )

                        HStack(spacing: 8) {
                            Button(showPolishInstructionEditor ? "Done" : "Edit") {
                                togglePolishInstructionEditor()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!shell.settings.polishEnabled || shell.settings.polishCustomInstructionEnabled != true)
                        }

                        if showPolishInstructionEditor, shell.settings.polishCustomInstructionEnabled == true {
                            instructionEditor(
                                text: $polishInstructionDraft,
                                placeholder: polishDefaultInstruction,
                                width: modelSelectorWidth
                            )
                            .disabled(!shell.settings.polishEnabled)
                            .focused($focusedInstructionEditor, equals: .polish)
                        }
                    }
                    .frame(width: modelSelectorWidth, alignment: .leading)
                }

                if !shell.settings.polishEnabled {
                    Text("Polish is disabled. Sessions will keep raw and polished files, with polished text set to raw transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard("API KEYS") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("OpenAI API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        SecureField("OpenAI API key", text: $shell.openAIKeyInput)
                        Button {
                            shell.clearAPIKey(.openAI)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .help("Clear OpenAI key")
                    }
                    Text(shell.openAIKeyStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    keyVerificationRow(for: "openai_polish")

                    Text("Groq API Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        SecureField("Groq API key", text: $shell.groqKeyInput)
                        Button {
                            shell.clearAPIKey(.groq)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .help("Clear Groq key")
                    }
                    Text(shell.groqKeyStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    keyVerificationRow(for: "groq_polish")

                    Text("OpenRouter API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        SecureField("OpenRouter API key", text: $shell.openRouterKeyInput)
                        Button {
                            shell.clearAPIKey(.openRouter)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .help("Clear OpenRouter key")
                    }
                    Text(shell.openRouterKeyStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    keyVerificationRow(for: "openrouter_polish")

                    Text("Gemini API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        SecureField("Gemini API key", text: $shell.geminiKeyInput)
                        Button {
                            shell.clearAPIKey(.gemini)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .help("Clear Gemini key")
                    }
                    Text(shell.geminiKeyStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    keyVerificationRow(for: "gemini_polish")

                    HStack(spacing: 8) {
                        Button("Save keys") {
                            shell.saveAPIKeys()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Clear keys") {
                            shell.clearAllAPIKeys()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .onAppear {
            transcriptionInstructionDraft = shell.settings.transcriptionInstruction ?? ""
            polishInstructionDraft = shell.settings.polishInstruction ?? ""
            shell.refreshModels(for: shell.settings.transcriptionProviderID)
            if shell.settings.polishEnabled {
                shell.refreshModels(for: shell.settings.polishProviderID)
            }
        }
        .onChange(of: focusedInstructionEditor) { oldValue, newValue in
            let changes = InstructionEditorPersistence.changesOnFocusChange(
                from: oldValue,
                to: newValue,
                transcriptionDraft: transcriptionInstructionDraft,
                storedTranscription: shell.settings.transcriptionInstruction,
                polishDraft: polishInstructionDraft,
                storedPolish: shell.settings.polishInstruction
            )
            for change in changes {
                applyInstructionPersistenceChange(change)
            }
        }
    }

    private var hotkeysTab: some View {
        settingsPage {
            settingsCard("START / STOP") {
                HotkeyEditor(
                    title: "Global toggle hotkey",
                    hotkey: Binding(
                        get: { shell.settings.startStopHotkey },
                        set: { value in shell.updateSettings { $0.startStopHotkey = value } }
                    )
                )
            }

            settingsCard("POPOVER") {
                HotkeyEditor(
                    title: "Toggle OpenScribe popover",
                    hotkey: Binding(
                        get: { shell.settings.togglePopoverHotkey },
                        set: { value in shell.updateSettings { $0.togglePopoverHotkey = value } }
                    )
                )
            }

            settingsCard("TAB NAVIGATION") {
                Text("Live tab: Ctrl + Option + L")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("History tab: Ctrl + Option + H")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard("SETTINGS") {
                HotkeyEditor(
                    title: "Open settings window",
                    hotkey: Binding(
                        get: { shell.settings.openSettingsHotkey },
                        set: { value in shell.updateSettings { $0.openSettingsHotkey = value } }
                    )
                )

                Text("Cmd+, still works when OpenScribe is focused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard("COPY LATEST") {
                HotkeyEditor(
                    title: "Copy latest polished transcript",
                    hotkey: Binding(
                        get: { shell.settings.copyHotkey },
                        set: { value in shell.updateSettings { $0.copyHotkey = value } }
                    )
                )
            }

            settingsCard("COPY RAW") {
                HotkeyEditor(
                    title: "Copy latest raw transcript",
                    hotkey: Binding(
                        get: { shell.settings.copyRawHotkey },
                        set: { value in shell.updateSettings { $0.copyRawHotkey = value } }
                    )
                )
            }

            settingsCard("PASTE LATEST") {
                HotkeyEditor(
                    title: "Paste latest polished transcript",
                    hotkey: Binding(
                        get: { shell.settings.pasteHotkey },
                        set: { value in shell.updateSettings { $0.pasteHotkey = value } }
                    )
                )

                Text("Paste hotkey works only when Accessibility permission is granted for OpenScribe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(shell.accessibilityPermissionGranted ? "Accessibility permission: granted" : "Accessibility permission: missing")
                        .font(.caption)
                        .foregroundColor(shell.accessibilityPermissionGranted ? .secondary : .orange)

                    Spacer(minLength: 0)

                    Button("Open Accessibility Settings") {
                        shell.openAccessibilityPrivacySettings()
                    }
                    .buttonStyle(.bordered)

                    Button("Refresh") {
                        shell.refreshPermissionState()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let hotkeyError = shell.hotkeyError {
                settingsCard("HOTKEY STATUS") {
                    Text(hotkeyError)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private var rulesTab: some View {
        settingsPage {
            settingsCard("RULES") {
                TextEditor(text: $shell.rulesDraft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 260)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 8) {
                    Button("Save") {
                        shell.saveRulesDraft()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Revert") {
                        shell.reloadRulesDraft()
                    }
                    .buttonStyle(.bordered)

                    Button("Open in external editor") {
                        shell.rulesStore.openInExternalEditor()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var dataTab: some View {
        settingsPage {
            settingsCard("LOCAL MODELS") {
                let modelCatalog = shell.modelManager.catalog

                Text("Total disk usage: \(formattedFileSize(shell.modelManager.totalInstalledSizeBytes()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let active = shell.modelManager.activeDownloadModelID {
                    ProgressView("Downloading \(active)", value: shell.modelManager.progress)
                }

                ForEach(modelCatalog, id: \ModelAsset.id) { (asset: ModelAsset) in
                    let isInstalled = shell.modelManager.isInstalled(modelID: asset.id)
                    let sizeBytes = isInstalled
                        ? shell.modelManager.installedSizeBytes(modelID: asset.id)
                        : asset.expectedSizeBytes

                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(isInstalled ? "Installed · \(formattedFileSize(sizeBytes))" : "Not installed · \(formattedFileSize(sizeBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        if isInstalled {
                            Button("Delete") {
                                pendingLocalModelAction = .delete(modelID: asset.id, sizeBytes: sizeBytes)
                            }
                            .buttonStyle(.bordered)
                            .disabled(shell.modelManager.activeDownloadModelID != nil)
                        } else {
                            Button("Download") {
                                pendingLocalModelAction = .download(modelID: asset.id, sizeBytes: sizeBytes)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(shell.modelManager.activeDownloadModelID != nil)
                        }
                    }
                }

                Text("If local transcription is selected and the model is missing, OpenScribe auto-downloads it before transcription starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard("STORAGE") {
                settingRow("App support") {
                    Text(shell.layout.appSupport.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .frame(width: 300, alignment: .trailing)
                }

                HStack {
                    Button("Open App Support Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([shell.layout.appSupport])
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 8)

                    Button("Delete") {
                        showDeleteAppSupportConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }

                Text("Moving App Support to Trash removes local sessions, models, rules, and settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aboutTab: some View {
        settingsPage {
            settingsCard("OPENSCRIBE") {
                settingRow("Version") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                settingRow("Build") {
                    Text(appBuild)
                        .foregroundStyle(.secondary)
                }

                settingRow("Default STT provider") {
                    Text(shell.settings.transcriptionProviderID)
                        .foregroundStyle(.secondary)
                }

                settingRow("Default polish provider") {
                    Text(shell.settings.polishProviderID)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard("CURRENT PURPOSE") {
                Text("Reliable dictation capture with durable session artifacts and clear two-step transcript processing.")
                    .foregroundStyle(.secondary)
            }

            settingsCard("ABOUT THE AUTHOR") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Created by Stefan Streichsbier.")
                        .foregroundStyle(.secondary)
                    Text("Built in collaboration with Scribe, the OpenScribe coding partner.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Link("Repository", destination: repositoryURL)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Link("SOUL.md", destination: soulGitHubURL)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Link("AGENTS.md", destination: agentsGitHubURL)
                    }
                    .font(.caption)
                }
            }

            settingsCard("AUTHOR LINKS") {
                HStack(spacing: 12) {
                    BrandLink(
                        title: "@streichsbaer",
                        assetName: "GitHubMark",
                        destination: authorGitHubURL
                    )
                    BrandLink(
                        title: "@s_streichsbier",
                        assetName: "XMark",
                        destination: authorXURL
                    )
                }
                .font(.subheadline)
            }
        }
    }

    private func settingsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.7)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .frame(minWidth: 180, alignment: .leading)

            Spacer(minLength: 12)

            control()
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func transcriptionModels(for provider: String) -> [String] {
        shell.availableModels(for: provider, usage: .transcription)
    }

    private func polishModels(for provider: String) -> [String] {
        shell.availableModels(for: provider, usage: .polish)
    }

    private func supportsTranscriptionInstruction(_ providerID: String) -> Bool {
        switch providerID {
        case "openai_whisper", "groq_whisper", "openrouter_transcribe", "gemini_transcribe":
            return true
        default:
            return false
        }
    }

    private func resolvedInstructionText(draftText: String?, fallback: String) -> String {
        resolvedInstruction(draftText, fallback: fallback)
    }

    private func isUsingDefaultInstruction(draftText: String?) -> Bool {
        (draftText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyInstructionPersistenceChange(_ change: InstructionPersistenceChange) {
        switch change {
        case .none:
            return
        case .setTranscription(let value):
            shell.updateSettings { settings in
                settings.transcriptionInstruction = value
            }
        case .setPolish(let value):
            shell.updateSettings { settings in
                settings.polishInstruction = value
            }
        }
    }

    private func toggleTranscriptionInstructionEditor() {
        guard shell.settings.transcriptionCustomInstructionEnabled == true else {
            return
        }
        if showTranscriptionInstructionEditor {
            let change = InstructionEditorPersistence.changeOnDone(
                target: .transcription,
                transcriptionDraft: transcriptionInstructionDraft,
                storedTranscription: shell.settings.transcriptionInstruction,
                polishDraft: polishInstructionDraft,
                storedPolish: shell.settings.polishInstruction
            )
            applyInstructionPersistenceChange(change)
            focusedInstructionEditor = nil
            showTranscriptionInstructionEditor = false
            return
        }

        showTranscriptionInstructionEditor = true
        DispatchQueue.main.async {
            focusedInstructionEditor = .transcription
        }
    }

    private func togglePolishInstructionEditor() {
        guard shell.settings.polishCustomInstructionEnabled == true else {
            return
        }
        if showPolishInstructionEditor {
            let change = InstructionEditorPersistence.changeOnDone(
                target: .polish,
                transcriptionDraft: transcriptionInstructionDraft,
                storedTranscription: shell.settings.transcriptionInstruction,
                polishDraft: polishInstructionDraft,
                storedPolish: shell.settings.polishInstruction
            )
            applyInstructionPersistenceChange(change)
            focusedInstructionEditor = nil
            showPolishInstructionEditor = false
            return
        }

        showPolishInstructionEditor = true
        DispatchQueue.main.async {
            focusedInstructionEditor = .polish
        }
    }

    @ViewBuilder
    private func instructionPreviewRow(text: String, isDefault: Bool, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if isDefault {
                Text("Default")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func instructionEditor(
        text: Binding<String>,
        placeholder: String,
        width: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: text)
                .font(.system(size: 12))
                .frame(height: 120)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            Text("Used as the system instruction for this stage. Clear text to use default behavior.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Reset to default") {
                    text.wrappedValue = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("\(text.wrappedValue.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    private var pinnedMicrophoneSelection: Binding<String> {
        Binding(
            get: { shell.settings.pinnedMicrophone?.id ?? "" },
            set: { newValue in
                shell.setPinnedMicrophone(newValue.isEmpty ? nil : newValue)
            }
        )
    }

    private var microphonePermissionSummary: String {
        switch shell.permissionState {
        case .authorized:
            return "Microphone permission: granted"
        case .denied:
            return "Microphone permission: denied"
        case .undetermined:
            return "Microphone permission: not requested"
        }
    }

    @ViewBuilder
    private func keyVerificationRow(for providerID: String) -> some View {
        HStack(spacing: 8) {
            Button("Verify") {
                shell.verifyProvider(for: providerID)
            }
            .buttonStyle(.bordered)

            let status = shell.providerConnectivityStatus(for: providerID)
            Text(status.detail)
                .font(.caption)
                .foregroundColor(connectivityColor(status))
        }
    }

    private func connectivityColor(_ status: ProviderConnectivityStatus) -> Color {
        switch status.state {
        case .idle:
            return .secondary
        case .verifying:
            return .orange
        case .verified:
            return .green
        case .failed:
            return .red
        }
    }
}

private enum LocalModelAction: Equatable {
    case download(modelID: String, sizeBytes: Int64)
    case delete(modelID: String, sizeBytes: Int64)

    var dialogTitle: String {
        switch self {
        case .download:
            return "Download Local Model"
        case .delete:
            return "Delete Local Model"
        }
    }

    var dialogMessage: String {
        switch self {
        case .download(let modelID, let sizeBytes):
            return "Download model \(modelID) (\(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)))?"
        case .delete(let modelID, let sizeBytes):
            return "Delete model \(modelID) (\(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)))?"
        }
    }
}

private struct BrandLink: View {
    let title: String
    let assetName: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 6) {
                if let image = BrandIconLoader.image(named: assetName) {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "link.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
                Text(title)
            }
        }
    }
}

private enum BrandIconLoader {
    static func image(named name: String) -> NSImage? {
        if let url = Bundle.module.url(forResource: name, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }

        return nil
    }
}

private struct FilterableModelSelector: View {
    let models: [String]
    let selectedModel: String
    @Binding var filterText: String
    let width: CGFloat
    let isDisabled: Bool
    let onSelect: (String) -> Void

    private var filteredModels: [String] {
        let filter = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if filter.isEmpty {
            return models
        }
        return models.filter { $0.lowercased().contains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Filter models", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled)

            modelList

            Text("Selected: \(selectedModel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: width, alignment: .trailing)
    }

    private var modelList: some View {
        ScrollView {
            if filteredModels.isEmpty {
                Text("No models match the filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(filteredModels, id: \.self, content: modelRow)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 118)
        .padding(4)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func modelRow(_ model: String) -> some View {
        Button {
            onSelect(model)
        } label: {
            HStack(spacing: 8) {
                Text(model)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if model == selectedModel {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(model == selectedModel ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct HotkeyEditor: View {
    let title: String
    @Binding var hotkey: HotkeySetting

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var recordingHint = "Click Record Shortcut, then press a key combination."
    private let modifierOnlyKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Text(HotkeyDisplay.string(for: hotkey))
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )

                Spacer()

                Button(isRecording ? "Recording..." : "Record Shortcut") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)

                if isRecording {
                    Button("Cancel") {
                        stopRecording()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(recordingHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording(resetHint: false)
        isRecording = true
        recordingHint = "Press your shortcut. Esc cancels. At least one modifier is required."
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecording(event)
        }
    }

    private func stopRecording(resetHint: Bool = true) {
        isRecording = false
        if resetHint {
            recordingHint = "Click Record Shortcut, then press a key combination."
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleRecording(_ event: NSEvent) -> NSEvent? {
        guard isRecording else {
            return event
        }

        let keyCode = UInt32(event.keyCode)

        if keyCode == 53 {
            stopRecording()
            return nil
        }

        if modifierOnlyKeyCodes.contains(keyCode) {
            return nil
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            recordingHint = "Shortcut must include a modifier key."
            return nil
        }

        hotkey = HotkeySetting(keyCode: keyCode, modifiers: modifiers).normalizedForCarbonHotkey()
        recordingHint = "Saved shortcut: \(HotkeyDisplay.string(for: hotkey))."
        stopRecording(resetHint: false)
        return nil
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.function) {
            result |= HotkeySetting.carbonFunctionMask
        }
        if flags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.command) {
            result |= UInt32(cmdKey)
        }
        if flags.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        return result
    }
}
