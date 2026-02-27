import Carbon
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var shell: AppShell

    private let sttProviders = [
        (id: "whispercpp", label: "Local whisper.cpp"),
        (id: "openai_whisper", label: "OpenAI Speech-to-Text"),
        (id: "groq_whisper", label: "Groq Whisper")
    ]

    private let polishProviders = [
        (id: "openai_polish", label: "OpenAI"),
        (id: "groq_polish", label: "Groq")
    ]

    var body: some View {
        Form {
            providerSection
            hotkeySection
            behaviorSection
            apiSection
            rulesSection
            modelSection
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 680)
    }

    private var providerSection: some View {
        Section("Providers") {
            Picker("Transcription provider", selection: Binding(
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

            Picker("Transcription model", selection: Binding(
                get: { shell.settings.transcriptionModel },
                set: { newValue in
                    shell.updateSettings { $0.transcriptionModel = newValue }
                }
            )) {
                ForEach(transcriptionModels(for: shell.settings.transcriptionProviderID), id: \.self) {
                    Text($0).tag($0)
                }
            }

            Picker("Polish provider", selection: Binding(
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

            Picker("Polish model", selection: Binding(
                get: { shell.settings.polishModel },
                set: { newValue in
                    shell.updateSettings { $0.polishModel = newValue }
                }
            )) {
                ForEach(polishModels(for: shell.settings.polishProviderID), id: \.self) {
                    Text($0).tag($0)
                }
            }

            Picker("Language", selection: Binding(
                get: { shell.settings.languageMode },
                set: { newValue in
                    shell.updateSettings { $0.languageMode = newValue }
                }
            )) {
                Text("auto").tag("auto")
                Text("en").tag("en")
                Text("de").tag("de")
                Text("fr").tag("fr")
                Text("es").tag("es")
            }
        }
    }

    private var hotkeySection: some View {
        Section("Hotkeys") {
            HotkeyEditor(
                title: "Start/Stop",
                hotkey: Binding(
                    get: { shell.settings.startStopHotkey },
                    set: { value in
                        shell.updateSettings { $0.startStopHotkey = value }
                    }
                )
            )

            HotkeyEditor(
                title: "Paste latest polished",
                hotkey: Binding(
                    get: { shell.settings.copyHotkey },
                    set: { value in
                        shell.updateSettings { $0.copyHotkey = value }
                    }
                )
            )

            if let hotkeyError = shell.hotkeyError {
                Text(hotkeyError)
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Copy polished transcript on completion", isOn: Binding(
                get: { shell.settings.copyOnComplete },
                set: { newValue in
                    shell.updateSettings { $0.copyOnComplete = newValue }
                }
            ))

            Text("Retention policy: keep all session artifacts until manually deleted")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var apiSection: some View {
        Section("API Keys") {
            SecureField("OpenAI API key", text: $shell.openAIKeyInput)
            Text(shell.openAIKeyStatusDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            SecureField("Groq API key", text: $shell.groqKeyInput)
            Text(shell.groqKeyStatusDescription)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Save keys") {
                    shell.saveAPIKeys()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear OpenAI") {
                    shell.openAIKeyInput = ""
                    shell.saveAPIKeys()
                }
                .buttonStyle(.bordered)

                Button("Clear Groq") {
                    shell.groqKeyInput = ""
                    shell.saveAPIKeys()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var rulesSection: some View {
        Section("Rules") {
            TextEditor(text: $shell.rulesDraft)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)

            HStack {
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

    private var modelSection: some View {
        Section("Local whisper.cpp models") {
            Text("Installed: \(shell.modelManager.installedModels().joined(separator: ", "))")
                .font(.caption)
                .foregroundColor(.secondary)

            if let active = shell.modelManager.activeDownloadModelID {
                ProgressView("Downloading \(active)", value: shell.modelManager.progress)
            }

            HStack {
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
    }

    private func transcriptionModels(for provider: String) -> [String] {
        switch provider {
        case "whispercpp":
            return ["tiny", "base", "small", "medium"]
        case "openai_whisper":
            return ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]
        case "groq_whisper":
            return ["whisper-large-v3", "whisper-large-v3-turbo"]
        default:
            return ["base"]
        }
    }

    private func polishModels(for provider: String) -> [String] {
        switch provider {
        case "openai_polish":
            return ["gpt-4.1-mini", "gpt-4o-mini"]
        case "groq_polish":
            return ["llama-3.3-70b-versatile", "mixtral-8x7b-32768"]
        default:
            return ["gpt-4.1-mini"]
        }
    }
}

struct HotkeyEditor: View {
    let title: String
    @Binding var hotkey: HotkeySetting

    private var functionMask: UInt32 { UInt32(kEventKeyModifierFnMask) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)

            HStack {
                Stepper("Key code: \(hotkey.keyCode)", value: Binding(
                    get: { Int(hotkey.keyCode) },
                    set: { hotkey.keyCode = UInt32(max(0, $0)) }
                ), in: 0...127)

                Toggle("Fn", isOn: modifierBinding(functionMask))
                Toggle("Ctrl", isOn: modifierBinding(UInt32(controlKey)))
                Toggle("Option", isOn: modifierBinding(UInt32(optionKey)))
                Toggle("Cmd", isOn: modifierBinding(UInt32(cmdKey)))
                Toggle("Shift", isOn: modifierBinding(UInt32(shiftKey)))
            }
        }
    }

    private func modifierBinding(_ mask: UInt32) -> Binding<Bool> {
        Binding(
            get: { (hotkey.modifiers & mask) != 0 },
            set: { enabled in
                if enabled {
                    hotkey.modifiers |= mask
                } else {
                    hotkey.modifiers &= ~mask
                }
            }
        )
    }
}
