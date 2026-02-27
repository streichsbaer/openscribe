import AppKit
import Carbon
import SwiftUI

private enum SettingsTab: Hashable {
    case general
    case providers
    case hotkeys
    case rulesData
    case about
}

struct SettingsView: View {
    @EnvironmentObject private var shell: AppShell
    @State private var selectedTab: SettingsTab = .general
    @AppStorage("ui.transcriptPanelsExpanded") private var transcriptPanelsExpanded = false

    private let sttProviders = [
        (id: "whispercpp", label: "Local whisper.cpp"),
        (id: "openai_whisper", label: "OpenAI Speech-to-Text"),
        (id: "groq_whisper", label: "Groq Whisper")
    ]

    private let polishProviders = [
        (id: "openai_polish", label: "OpenAI"),
        (id: "groq_polish", label: "Groq")
    ]
    private let authorGitHubURL = URL(string: "https://github.com/streichsbaer")!
    private let authorXURL = URL(string: "https://x.com/s_streichsbier")!
    private let repositoryRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            providersTab
                .tabItem { Label("Providers", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.providers)

            hotkeysTab
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                .tag(SettingsTab.hotkeys)

            rulesAndDataTab
                .tabItem { Label("Rules & Data", systemImage: "doc.text") }
                .tag(SettingsTab.rulesData)

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 940, minHeight: 760)
    }

    private var generalTab: some View {
        settingsPage {
            settingsCard("USAGE") {
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
                    Text(shell.sessionState.rawValue.capitalized)
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
                        }
                    )) {
                        ForEach(sttProviders, id: \.id) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 300)
                }

                settingRow("Model") {
                    Picker("", selection: Binding(
                        get: { shell.settings.transcriptionModel },
                        set: { newValue in
                            shell.updateSettings { settings in
                                settings.transcriptionModel = newValue
                            }
                        }
                    )) {
                        ForEach(transcriptionModels(for: shell.settings.transcriptionProviderID), id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 300)
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
                    .frame(width: 300)
                }
            }

            settingsCard("POLISH") {
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
                    .frame(width: 300)
                }

                settingRow("Model") {
                    Picker("", selection: Binding(
                        get: { shell.settings.polishModel },
                        set: { newValue in
                            shell.updateSettings { settings in
                                settings.polishModel = newValue
                            }
                        }
                    )) {
                        ForEach(polishModels(for: shell.settings.polishProviderID), id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 300)
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

            settingsCard("PASTE LATEST") {
                HotkeyEditor(
                    title: "Paste latest polished transcript",
                    hotkey: Binding(
                        get: { shell.settings.copyHotkey },
                        set: { value in shell.updateSettings { $0.copyHotkey = value } }
                    )
                )

                Text("This hotkey copies latest polished text and triggers Cmd+V when Accessibility permission is granted.")
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

    private var rulesAndDataTab: some View {
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

            settingsCard("LOCAL MODELS") {
                Text("Installed: \(shell.modelManager.installedModels().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let active = shell.modelManager.activeDownloadModelID {
                    ProgressView("Downloading \(active)", value: shell.modelManager.progress)
                }

                HStack(spacing: 8) {
                    Button("Install selected model") {
                        shell.downloadDefaultModelIfNeeded()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Remove selected model") {
                        let modelID = shell.settings.transcriptionModel
                        try? shell.modelManager.remove(modelID: modelID)
                        shell.objectWillChange.send()
                    }
                    .buttonStyle(.bordered)
                }
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
                }
            }
        }
    }

    private var aboutTab: some View {
        settingsPage {
            settingsCard("SMARTTRANSCRIPT") {
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
                    Text("Built in collaboration with Scribe, the SmartTranscript coding partner.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.open(soulDocURL)
                        } label: {
                            Label("SOUL.md", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!FileManager.default.fileExists(atPath: soulDocURL.path))
                        .help("Open SOUL.md in your default app")

                        Button {
                            NSWorkspace.shared.open(agentsDocURL)
                        } label: {
                            Label("AGENTS.md", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!FileManager.default.fileExists(atPath: agentsDocURL.path))
                        .help("Open AGENTS.md in your default app")
                    }
                }
            }

            settingsCard("AUTHOR LINKS") {
                HStack(spacing: 12) {
                    Link(destination: authorGitHubURL) {
                        Label("streichsbaer", systemImage: "chevron.left.forwardslash.chevron.right")
                    }

                    Link(destination: authorXURL) {
                        Label("@s_streichsbier", systemImage: "at")
                    }
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
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
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
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline)

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

    private var soulDocURL: URL {
        repositoryRootURL.appendingPathComponent("SOUL.md")
    }

    private var agentsDocURL: URL {
        repositoryRootURL.appendingPathComponent("AGENTS.md")
    }

    private func transcriptionModels(for provider: String) -> [String] {
        switch provider {
        case "whispercpp":
            return ["tiny", "base", "small", "medium"]
        case "openai_whisper":
            return ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"]
        case "groq_whisper":
            return ["whisper-large-v3", "whisper-large-v3-turbo"]
        default:
            return ["base"]
        }
    }

    private func polishModels(for provider: String) -> [String] {
        switch provider {
        case "openai_polish":
            return ["gpt-5-mini"]
        case "groq_polish":
            return ["llama-3.3-70b-versatile", "mixtral-8x7b-32768"]
        default:
            return ["gpt-5-mini"]
        }
    }
}

struct HotkeyEditor: View {
    let title: String
    @Binding var hotkey: HotkeySetting

    private var functionMask: UInt32 { UInt32(kEventKeyModifierFnMask) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Stepper("Key code: \(hotkey.keyCode)", value: Binding(
                    get: { Int(hotkey.keyCode) },
                    set: { hotkey.keyCode = UInt32(max(0, $0)) }
                ), in: 0...127)

                Spacer()

                Text("Current: key \(hotkey.keyCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                modifierChip("Fn", mask: functionMask)
                modifierChip("Ctrl", mask: UInt32(controlKey))
                modifierChip("Option", mask: UInt32(optionKey))
                modifierChip("Cmd", mask: UInt32(cmdKey))
                modifierChip("Shift", mask: UInt32(shiftKey))
            }
        }
    }

    private func modifierChip(_ label: String, mask: UInt32) -> some View {
        let enabled = (hotkey.modifiers & mask) != 0
        return Button {
            if enabled {
                hotkey.modifiers &= ~mask
            } else {
                hotkey.modifiers |= mask
            }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(enabled ? Color.accentColor.opacity(0.20) : Color.gray.opacity(0.16))
                )
                .overlay(
                    Capsule()
                        .stroke(enabled ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
