import AppKit
import Carbon
import SwiftUI

enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    case general
    case providers
    case transcribe
    case polish
    case hotkeys
    case rules
    case data
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .transcribe:
            return "Transcribe"
        case .polish:
            return "Polish"
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
        case .transcribe:
            return "waveform"
        case .polish:
            return "wand.and.stars"
        case .providers:
            return "key.horizontal"
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

    var preferredWidth: CGFloat {
        switch self {
        case .general:
            return 860
        case .transcribe:
            return 900
        case .polish:
            return 900
        case .providers:
            return 900
        case .hotkeys:
            return 900
        case .rules:
            return 920
        case .data:
            return 860
        case .about:
            return 760
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .general:
            return 620
        case .transcribe:
            return 600
        case .polish:
            return 600
        case .providers:
            return 640
        case .hotkeys:
            return 620
        case .rules:
            return 620
        case .data:
            return 540
        case .about:
            return 580
        }
    }

    var maxHeight: CGFloat {
        switch self {
        case .general:
            return 760
        case .transcribe:
            return 760
        case .polish:
            return 740
        case .providers:
            return 820
        case .hotkeys:
            return 800
        case .rules:
            return 760
        case .data:
            return 700
        case .about:
            return 620
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var shell: AppShell
    @EnvironmentObject private var tabState: SettingsTabState
    @EnvironmentObject private var setupAssistantState: SetupAssistantWindowState
    @State private var contentWidth = SettingsTab.general.preferredWidth
    @State private var contentHeight = SettingsTab.general.minHeight
    @State private var measuredPageHeights: [SettingsTab: CGFloat] = [:]
    @State private var pendingLocalModelAction: LocalModelAction?
    @State private var showDeleteAppSupportConfirmation = false
    @State private var showRulesSavedFeedback = false
    @State private var sttModelFilter = ""
    @State private var polishModelFilter = ""
    @State private var transcriptionInstructionDraft = ""
    @State private var polishInstructionDraft = ""
    @State private var showTranscriptionInstructionEditor = false
    @State private var showPolishInstructionEditor = false
    @FocusState private var focusedInstructionEditor: InstructionEditorTarget?
    private let onPreferredSizeChange: ((CGSize, Bool) -> Void)?
    private let compactControlMaxWidth: CGFloat = 320
    private let wideControlMaxWidth: CGFloat = 460
    private let settingsWindowChromeHeight: CGFloat = 104
    private let rulesActionRowHeight: CGFloat = 32
    private let rulesEditorMinimumHeight: CGFloat = 220
    private let transcriptionDefaultInstruction = "No instruction set."
    private let polishDefaultInstruction = "No instruction set."
    private let rulesSavedFeedbackDurationNs: UInt64 = 1_500_000_000

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
        (id: "gemini_polish", label: "Gemini"),
        (id: "cerebras_polish", label: "Cerebras")
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
            transcriptionInstructionDraft = shell.settings.transcriptionInstruction ?? ""
            polishInstructionDraft = shell.settings.polishInstruction ?? ""
            updateLayout(for: tabState.selectedTab, animate: false)
        }
        .onChange(of: tabState.selectedTab) { oldValue, newValue in
            persistInstructionEditorState(leaving: oldValue)
            updateLayout(for: newValue, animate: true)
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
        .sheet(isPresented: $setupAssistantState.isPresented) {
            SetupAssistantView()
                .environmentObject(shell)
                .environmentObject(setupAssistantState)
        }
    }

    private var tabHeader: some View {
        HStack(spacing: 8) {
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
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .foregroundStyle(tabState.selectedTab == tab ? Color.accentColor : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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
        case .transcribe:
            transcribeTab
        case .polish:
            polishTab
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
        let preferred = preferredSize(for: tab)
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

    private func preferredSize(for tab: SettingsTab) -> CGSize {
        let measuredHeight = measuredPageHeights[tab] ?? (tab.minHeight - settingsWindowChromeHeight)
        let clampedHeight = min(
            max(measuredHeight + settingsWindowChromeHeight, tab.minHeight),
            tab.maxHeight
        )
        return CGSize(width: tab.preferredWidth, height: clampedHeight)
    }

    private func recordMeasuredPageHeight(_ height: CGFloat, for tab: SettingsTab) {
        let roundedHeight = ceil(height)
        let currentHeight = measuredPageHeights[tab] ?? 0
        guard abs(currentHeight - roundedHeight) > 1 else {
            return
        }

        measuredPageHeights[tab] = roundedHeight
        if tabState.selectedTab == tab {
            updateLayout(for: tab, animate: true)
        }
    }

    private var generalTab: some View {
        settingsPage(for: .general) {
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
                    .frame(maxWidth: compactControlMaxWidth, alignment: .leading)
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
                         : "Auto-paste enabled but Accessibility permission is missing. Open Accessibility Settings in General.")
                        .font(.caption)
                        .foregroundColor(shell.accessibilityPermissionGranted ? .secondary : .orange)
                }

                Text("Retention policy: keep all session artifacts until manually deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard("ACCESSIBILITY") {
                Text(shell.accessibilityPermissionGranted ? "Accessibility permission: granted" : "Accessibility permission: missing")
                    .font(.caption)
                    .foregroundColor(shell.accessibilityPermissionGranted ? .secondary : .orange)

                Text("Paste latest and auto-paste require Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
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

            settingsCard("MICROPHONE") {
                settingRow("System default") {
                    Text(shell.systemDefaultMicrophoneName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: compactControlMaxWidth, alignment: .leading)
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
                    .frame(maxWidth: compactControlMaxWidth, alignment: .leading)
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

            settingsCard("SETUP") {
                Text("Use the setup assistant to validate the best Groq path or a local-only path with one short checklist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Open setup assistant") {
                        setupAssistantState.selectedTrack = shell.setupAssistantPreferredTrack
                        setupAssistantState.isPresented = true
                    }
                    .buttonStyle(.borderedProminent)

                    if shell.shouldAutoPresentSetupAssistantOnLaunch {
                        Button("Do not show on launch") {
                            shell.setSetupAssistantDoNotShowAgain(true)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var providersTab: some View {
        settingsPage(for: .providers) {
            settingsCard("API KEYS") {
                Text("Verify confirms the current token. Refresh models updates the shared model list used by Transcribe and Polish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                providerKeySection(
                    title: "OpenAI",
                    placeholder: "OpenAI API key",
                    keyText: $shell.openAIKeyInput,
                    statusDescription: shell.openAIKeyStatusDescription,
                    providerID: "openai_polish"
                ) {
                    shell.clearAPIKey(.openAI)
                }

                sectionDivider()

                providerKeySection(
                    title: "Groq",
                    placeholder: "Groq API key",
                    keyText: $shell.groqKeyInput,
                    statusDescription: shell.groqKeyStatusDescription,
                    providerID: "groq_polish"
                ) {
                    shell.clearAPIKey(.groq)
                }

                sectionDivider()

                providerKeySection(
                    title: "OpenRouter",
                    placeholder: "OpenRouter API key",
                    keyText: $shell.openRouterKeyInput,
                    statusDescription: shell.openRouterKeyStatusDescription,
                    providerID: "openrouter_polish"
                ) {
                    shell.clearAPIKey(.openRouter)
                }

                sectionDivider()

                providerKeySection(
                    title: "Gemini",
                    placeholder: "Gemini API key",
                    keyText: $shell.geminiKeyInput,
                    statusDescription: shell.geminiKeyStatusDescription,
                    providerID: "gemini_polish"
                ) {
                    shell.clearAPIKey(.gemini)
                }

                sectionDivider()

                providerKeySection(
                    title: "Cerebras",
                    placeholder: "Cerebras API key",
                    keyText: $shell.cerebrasKeyInput,
                    statusDescription: shell.cerebrasKeyStatusDescription,
                    providerID: "cerebras_polish"
                ) {
                    shell.clearAPIKey(.cerebras)
                }

                HStack(spacing: 8) {
                    Button("Save keys") {
                        shell.saveAPIKeys()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear all keys") {
                        shell.clearAllAPIKeys()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
        }
    }

    private var transcribeTab: some View {
        settingsPage(for: .transcribe) {
            settingsCard("TRANSCRIBE") {
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
                        }
                    )) {
                        ForEach(sttProviders, id: \.id) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: compactControlMaxWidth, alignment: .leading)
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
                    .frame(maxWidth: compactControlMaxWidth, alignment: .leading)
                }
            }

            settingsCard("MODEL") {
                FilterableModelSelector(
                    models: transcriptionModels(for: shell.settings.transcriptionProviderID),
                    selectedModel: shell.settings.transcriptionModel,
                    filterText: $sttModelFilter,
                    isDisabled: false
                ) { selected in
                    shell.updateSettings { settings in
                        settings.transcriptionModel = selected
                    }
                }
            }

            settingsCard("INSTRUCTION") {
                let providerID = shell.settings.transcriptionProviderID

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
                    )
                )

                Button(showTranscriptionInstructionEditor ? "Done" : "Edit") {
                    toggleTranscriptionInstructionEditor()
                }
                .buttonStyle(.bordered)
                .disabled(shell.settings.transcriptionCustomInstructionEnabled != true)

                if showTranscriptionInstructionEditor, shell.settings.transcriptionCustomInstructionEnabled == true {
                    instructionEditor(
                        text: $transcriptionInstructionDraft,
                        placeholder: transcriptionDefaultInstruction
                    )
                    .focused($focusedInstructionEditor, equals: .transcription)
                }

                if !supportsTranscriptionInstruction(providerID) {
                    Text("Current provider does not use this instruction. It applies when a provider-backed transcription model is selected.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var polishTab: some View {
        settingsPage(for: .polish) {
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
                        }
                    )) {
                        ForEach(polishProviders, id: \.id) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: compactControlMaxWidth, alignment: .leading)
                    .disabled(!shell.settings.polishEnabled)
                }

                if !shell.settings.polishEnabled {
                    Text("Polish is disabled. Sessions will keep raw and polished files, with polished text set to raw transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard("MODEL") {
                FilterableModelSelector(
                    models: polishModels(for: shell.settings.polishProviderID),
                    selectedModel: shell.settings.polishModel,
                    filterText: $polishModelFilter,
                    isDisabled: !shell.settings.polishEnabled
                ) { selected in
                    shell.updateSettings { settings in
                        settings.polishModel = selected
                    }
                }
            }

            settingsCard("INSTRUCTION") {
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
                    )
                )

                Button(showPolishInstructionEditor ? "Done" : "Edit") {
                    togglePolishInstructionEditor()
                }
                .buttonStyle(.bordered)
                .disabled(!shell.settings.polishEnabled || shell.settings.polishCustomInstructionEnabled != true)

                if showPolishInstructionEditor, shell.settings.polishCustomInstructionEnabled == true {
                    instructionEditor(
                        text: $polishInstructionDraft,
                        placeholder: polishDefaultInstruction
                    )
                    .disabled(!shell.settings.polishEnabled)
                    .focused($focusedInstructionEditor, equals: .polish)
                }
            }
        }
    }

    private var hotkeysTab: some View {
        settingsPage(for: .hotkeys) {
            settingsCard("CORE") {
                HotkeyEditor(
                    title: "Start or stop recording",
                    hotkey: Binding(
                        get: { shell.settings.startStopHotkey },
                        set: { value in shell.updateSettings { $0.startStopHotkey = value } }
                    )
                )

                sectionDivider()

                HotkeyEditor(
                    title: "Open or close the popover",
                    hotkey: Binding(
                        get: { shell.settings.togglePopoverHotkey },
                        set: { value in shell.updateSettings { $0.togglePopoverHotkey = value } }
                    )
                )

                sectionDivider()

                HotkeyEditor(
                    title: "Open the settings window",
                    hotkey: Binding(
                        get: { shell.settings.openSettingsHotkey },
                        set: { value in shell.updateSettings { $0.openSettingsHotkey = value } }
                    )
                )

                Text("Cmd+, still works when OpenScribe is focused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsCard("CLIPBOARD") {
                HotkeyEditor(
                    title: "Copy the latest polished transcript",
                    hotkey: Binding(
                        get: { shell.settings.copyHotkey },
                        set: { value in shell.updateSettings { $0.copyHotkey = value } }
                    )
                )

                sectionDivider()

                HotkeyEditor(
                    title: "Copy the latest raw transcript",
                    hotkey: Binding(
                        get: { shell.settings.copyRawHotkey },
                        set: { value in shell.updateSettings { $0.copyRawHotkey = value } }
                    )
                )

                sectionDivider()

                HotkeyEditor(
                    title: "Paste the latest polished transcript",
                    hotkey: Binding(
                        get: { shell.settings.pasteHotkey },
                        set: { value in shell.updateSettings { $0.pasteHotkey = value } }
                    )
                )

                Text(
                    shell.accessibilityPermissionGranted
                    ? "Accessibility permission is granted. Adjust the permission from General."
                    : "Accessibility permission is missing. Adjust it from General."
                )
                    .font(.caption)
                    .foregroundColor(shell.accessibilityPermissionGranted ? .secondary : .orange)
            }

            settingsCard("POPOVER TABS") {
                Text("Live tab: Ctrl + Option + L")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("History tab: Ctrl + Option + H")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 18) {
            settingsCard("RULES", fillsHeight: true) {
                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $shell.rulesDraft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: rulesEditorMinimumHeight, maxHeight: .infinity)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 8) {
                        Button("Save") {
                            if shell.saveRulesDraft() {
                                showTransientRulesSavedFeedback()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Revert") {
                            shell.reloadRulesDraft()
                            showRulesSavedFeedback = false
                        }
                        .buttonStyle(.bordered)

                        Button("Open in external editor") {
                            shell.rulesStore.openInExternalEditor()
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)

                        if showRulesSavedFeedback {
                            Text("Saved")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        }
                    }
                    .frame(height: rulesActionRowHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dataTab: some View {
        settingsPage(for: .data) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        settingsPage(for: .about) {
            settingsCard("OPENSCRIBE") {
                settingRow("Version") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                settingRow("Build") {
                    Text(appBuild)
                        .foregroundStyle(.secondary)
                }
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

    private func settingsPage<Content: View>(for tab: SettingsTab, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: SettingsPageHeightPreferenceKey.self, value: geometry.size.height)
                }
            )
        }
        .onPreferenceChange(SettingsPageHeightPreferenceKey.self) { height in
            recordMeasuredPageHeight(height, for: tab)
        }
    }

    private func settingsCard<Content: View>(
        _ title: String,
        fillsHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.7)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: .topLeading
        )
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                Text(title)
                    .font(.subheadline)
                    .frame(width: 170, alignment: .leading)
                    .padding(.top, 6)

                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline)

                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sectionDivider() -> some View {
        Divider()
            .overlay(Color.primary.opacity(0.06))
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    private func providerKeySection(
        title: String,
        placeholder: String,
        keyText: Binding<String>,
        statusDescription: String,
        providerID: String,
        onClear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            SecureField(placeholder, text: keyText)

            Text(statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            keyVerificationRow(for: providerID, onClear: onClear)
        }
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

    private func persistInstructionEditorState(leaving tab: SettingsTab) {
        switch tab {
        case .transcribe:
            if showTranscriptionInstructionEditor {
                let change = InstructionEditorPersistence.changeOnDone(
                    target: .transcription,
                    transcriptionDraft: transcriptionInstructionDraft,
                    storedTranscription: shell.settings.transcriptionInstruction,
                    polishDraft: polishInstructionDraft,
                    storedPolish: shell.settings.polishInstruction
                )
                applyInstructionPersistenceChange(change)
                showTranscriptionInstructionEditor = false
            }
        case .polish:
            if showPolishInstructionEditor {
                let change = InstructionEditorPersistence.changeOnDone(
                    target: .polish,
                    transcriptionDraft: transcriptionInstructionDraft,
                    storedTranscription: shell.settings.transcriptionInstruction,
                    polishDraft: polishInstructionDraft,
                    storedPolish: shell.settings.polishInstruction
                )
                applyInstructionPersistenceChange(change)
                showPolishInstructionEditor = false
            }
        default:
            break
        }

        if tab == .transcribe, focusedInstructionEditor == .transcription {
            focusedInstructionEditor = nil
        }
        if tab == .polish, focusedInstructionEditor == .polish {
            focusedInstructionEditor = nil
        }
    }

    private func showTransientRulesSavedFeedback() {
        showRulesSavedFeedback = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: rulesSavedFeedbackDurationNs)
            showRulesSavedFeedback = false
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
    private func instructionPreviewRow(text: String, isDefault: Bool) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        placeholder: String
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
    private func keyVerificationRow(for providerID: String, onClear: @escaping () -> Void) -> some View {
        let status = shell.providerConnectivityStatus(for: providerID)

        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    providerActionButtons(providerID: providerID, onClear: onClear)
                }

                VStack(alignment: .leading, spacing: 8) {
                    providerActionButtons(providerID: providerID, onClear: onClear)
                }
            }

            Text(status.detail)
                .font(.caption)
                .foregroundColor(connectivityColor(status))
        }
    }

    @ViewBuilder
    private func providerActionButtons(providerID: String, onClear: @escaping () -> Void) -> some View {
        Button("Verify") {
            shell.verifyProvider(for: providerID)
        }
        .buttonStyle(.bordered)

        Button("Refresh models") {
            shell.refreshModels(for: providerID)
        }
        .buttonStyle(.bordered)

        Button("Clear key") {
            onClear()
        }
        .buttonStyle(.bordered)
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

private struct SettingsPageHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    hotkeySummary
                    Spacer(minLength: 12)
                    actionButtons
                }

                VStack(alignment: .leading, spacing: 8) {
                    hotkeySummary
                    actionButtons
                }
            }

            Text(recordingHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var hotkeySummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(HotkeyDisplay.string(for: hotkey))
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
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
