import AppKit
import Foundation

@MainActor
final class AppShell: ObservableObject {
    @Published var meterLevel: Float = 0
    @Published var permissionState: MicrophonePermissionState = .undetermined
    @Published var sessionState: SessionState = .idle

    @Published var currentSession: SessionContext?
    @Published var rawTranscript: String = ""
    @Published var polishedTranscript: String = ""
    @Published var statusMessage: String = "Ready"
    @Published var lastError: String?

    @Published var hotkeyError: String?

    @Published var rulesDraft: String

    @Published var openAIKeyInput: String = ""
    @Published var groqKeyInput: String = ""
    @Published var latestPolishedTranscript: String = ""
    @Published var menubarIconDebug: String = "icon=idle"
    @Published var transcribeElapsedSeconds: Int = 0
    @Published var polishElapsedSeconds: Int = 0

    var openSettingsWindowHandler: (() -> Void)?
    var updatePopoverSizeHandler: ((CGSize) -> Void)?

    let layout: DirectoryLayout
    let settingsStore: SettingsStore
    let rulesStore: RulesStore
    let modelManager: ModelDownloadManager

    private let keychainStore: KeychainStore
    private let apiKeyResolver: APIKeyResolver
    private let sessionManager: SessionManager
    private let audioCapture: AudioCaptureManager
    private let hotkeyManager: HotkeyManager
    private let providerFactory: ProviderFactory
    private let transcriptionPipeline: TranscriptionPipeline
    private let polishPipeline: PolishPipeline
    private var transcribeTimer: Timer?
    private var transcribeStartedAt: Date?
    private var polishTimer: Timer?
    private var polishStartedAt: Date?

    init() {
        let resolvedLayout = (try? DirectoryLayout.resolve()) ?? {
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SmartTranscript", isDirectory: true)
            return DirectoryLayout(
                appSupport: fallback,
                recordings: fallback.appendingPathComponent("Recordings", isDirectory: true),
                rules: fallback.appendingPathComponent("Rules", isDirectory: true),
                models: fallback.appendingPathComponent("Models/whisper", isDirectory: true),
                config: fallback.appendingPathComponent("Config", isDirectory: true),
                rulesFile: fallback.appendingPathComponent("Rules/rules.md"),
                rulesHistory: fallback.appendingPathComponent("Rules/rules.history.jsonl"),
                settingsFile: fallback.appendingPathComponent("Config/settings.json")
            )
        }()

        self.layout = resolvedLayout
        self.settingsStore = SettingsStore(layout: resolvedLayout)
        self.rulesStore = RulesStore(layout: resolvedLayout)
        self.modelManager = ModelDownloadManager(layout: resolvedLayout)
        self.keychainStore = KeychainStore()
        self.apiKeyResolver = APIKeyResolver(keychain: keychainStore)
        self.sessionManager = SessionManager(layout: resolvedLayout)
        self.audioCapture = AudioCaptureManager()
        self.hotkeyManager = HotkeyManager()

        let factory = ProviderFactory(keychain: keychainStore, modelManager: modelManager)
        self.providerFactory = factory
        self.transcriptionPipeline = TranscriptionPipeline(providerFactory: factory)
        self.polishPipeline = PolishPipeline(providerFactory: factory)

        self.rulesDraft = rulesStore.currentRules
        self.permissionState = audioCapture.permissionState()

        self.openAIKeyInput = keychainStore.load(.openAI) ?? ""
        self.groqKeyInput = keychainStore.load(.groq) ?? ""

        audioCapture.onLevelUpdate = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.meterLevel = level
            }
        }

        let dangling = sessionManager.recoverDanglingRecordings()
        if !dangling.isEmpty {
            statusMessage = "Found \(dangling.count) unfinished recording file(s)."
        }

        latestPolishedTranscript = sessionManager.loadLatestPolishedTranscript() ?? ""

        registerHotkeys()
    }

    var settings: AppSettings {
        settingsStore.settings
    }

    var microphoneIndicatorColorName: String {
        switch permissionState {
        case .denied:
            return "gray"
        case .authorized:
            return meterLevel > 0.01 ? "green" : "gray"
        case .undetermined:
            return "gray"
        }
    }

    var openAIKeyStatusDescription: String {
        apiKeyStatusDescription(for: .openAI)
    }

    var groqKeyStatusDescription: String {
        apiKeyStatusDescription(for: .groq)
    }

    var accessibilityPermissionGranted: Bool {
        AccessibilityInputInjector.isTrusted(promptIfNeeded: false)
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        settingsStore.update(mutate)
        registerHotkeys()
    }

    func saveAPIKeys() {
        let openAI = openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if openAI.isEmpty {
            keychainStore.delete(.openAI)
        } else {
            try? keychainStore.save(openAI, for: .openAI)
        }

        let groq = groqKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if groq.isEmpty {
            keychainStore.delete(.groq)
        } else {
            try? keychainStore.save(groq, for: .groq)
        }

        statusMessage = "API keys saved"
    }

    func clearAPIKey(_ entry: KeychainEntry) {
        switch entry {
        case .openAI:
            openAIKeyInput = ""
        case .groq:
            groqKeyInput = ""
        }
        saveAPIKeys()
    }

    func clearAllAPIKeys() {
        openAIKeyInput = ""
        groqKeyInput = ""
        saveAPIKeys()
        statusMessage = "API keys cleared"
    }

    func toggleRecording() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.sessionState == .recording {
                await self.stopRecordingAndProcess()
            } else {
                await self.startRecording()
            }
        }
    }

    func copyLatestPolished() {
        let candidate = latestPolishedCandidate()
        guard !candidate.isEmpty else {
            statusMessage = "No polished transcript available yet"
            return
        }

        Clipboard.copy(text: candidate)
        statusMessage = "Latest polished transcript copied"
    }

    func copyRawTranscript() {
        let candidate = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            statusMessage = "No raw transcript available yet"
            return
        }
        Clipboard.copy(text: candidate)
        statusMessage = "Raw transcript copied"
    }

    func copyCurrentSessionPath() {
        guard let path = currentSession?.paths.folderURL.path else {
            statusMessage = "No session path available yet"
            return
        }
        Clipboard.copy(text: path)
        statusMessage = "Session path copied"
    }

    func openSettingsWindow() {
        openSettingsWindowHandler?()
    }

    func openAccessibilityPrivacySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    func openMicrophonePrivacySettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    func refreshPermissionState() {
        permissionState = audioCapture.permissionState()
        registerHotkeys()
    }

    func updatePopoverSize(expandedTextPanels: Bool) {
        let size = expandedTextPanels
            ? CGSize(width: 620, height: 980)
            : CGSize(width: 540, height: 760)
        updatePopoverSizeHandler?(size)
    }

    func updateRawTranscriptFromEditor(_ text: String) {
        rawTranscript = text
        guard var session = currentSession else {
            return
        }
        try? sessionManager.writeRaw(text, for: &session)
        currentSession = session
    }

    func startRecording() async {
        if sessionState == .recording {
            return
        }

        endPolishProgressTracking()
        endTranscribeProgressTracking()

        permissionState = audioCapture.permissionState()
        if permissionState == .undetermined {
            let granted = await audioCapture.requestPermission()
            permissionState = granted ? .authorized : .denied
        }

        guard permissionState == .authorized else {
            lastError = "Microphone permission is required."
            statusMessage = "Microphone permission missing"
            return
        }

        do {
            rawTranscript = ""
            polishedTranscript = ""
            lastError = nil

            var session = try sessionManager.startSession(
                settings: settings,
                inputDeviceName: audioCapture.currentInputDeviceName
            )
            try sessionManager.transition(&session, to: .recording, details: "Audio capture started")
            try audioCapture.startRecording(to: session.paths.audioTempURL)
            currentSession = session

            sessionState = .recording
            statusMessage = "Recording"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed to start recording"
            sessionState = .failed
        }
    }

    func stopRecordingAndProcess() async {
        guard var session = currentSession else {
            return
        }

        do {
            sessionState = .finalizingAudio
            try sessionManager.transition(&session, to: .finalizingAudio, details: "Stopping audio capture")

            audioCapture.stopRecording()
            try sessionManager.finalizeAudioFile(&session)
            try sessionManager.stopSession(&session)

            sessionState = .transcribing
            beginTranscribeProgressTracking()
            try sessionManager.transition(&session, to: .transcribing, details: "Running transcription")

            let transcript = try await transcriptionPipeline.run(audioFileURL: session.paths.audioURL, settings: settings)
            endTranscribeProgressTracking()
            rawTranscript = transcript.text
            try sessionManager.writeRaw(transcript.text, for: &session)

            do {
                sessionState = .polishing
                beginPolishProgressTracking()
                try sessionManager.transition(&session, to: .polishing, details: "Running polish")

                let rules = try rulesStore.load()
                let polished = try await polishPipeline.run(
                    rawText: transcript.text,
                    rulesMarkdown: rules,
                    settings: settings
                )

                polishedTranscript = polished.markdown
                latestPolishedTranscript = polished.markdown
                try sessionManager.writePolished(polished.markdown, for: &session)

                if settings.copyOnComplete {
                    let clipboardText = normalizedClipboardText(polished.markdown)
                    if !clipboardText.isEmpty {
                        Clipboard.copy(text: clipboardText)
                    }
                    statusMessage = "Polished transcript copied"
                } else {
                    statusMessage = "Transcription complete"
                }
                endPolishProgressTracking()
            } catch {
                polishedTranscript = ""
                statusMessage = "Raw transcript ready. Polish failed or needs API key."
                lastError = error.localizedDescription
                endPolishProgressTracking()
            }

            try sessionManager.transition(&session, to: .completed, details: "Session complete")
            sessionState = .completed
            currentSession = session
        } catch {
            sessionManager.recordFailure(&session, error: error.localizedDescription)
            currentSession = session
            lastError = error.localizedDescription
            sessionState = .failed
            statusMessage = "Session failed"
            endPolishProgressTracking()
            endTranscribeProgressTracking()
        }
    }

    func retryPolish() {
        Task { @MainActor [weak self] in
            guard let self,
                  var session = self.currentSession,
                  !self.rawTranscript.isEmpty else {
                return
            }

            do {
                session.metadata.polishProvider = self.settings.polishProviderID
                session.metadata.polishModel = self.settings.polishModel
                self.sessionState = .polishing
                self.beginPolishProgressTracking()
                try self.sessionManager.transition(&session, to: .polishing, details: "Retry polish")
                let rules = try self.rulesStore.load()
                let polished = try await self.polishPipeline.run(
                    rawText: self.rawTranscript,
                    rulesMarkdown: rules,
                    settings: self.settings
                )

                self.polishedTranscript = polished.markdown
                self.latestPolishedTranscript = polished.markdown
                try self.sessionManager.writePolished(polished.markdown, for: &session)
                try self.sessionManager.transition(&session, to: .completed, details: "Polish retry complete")
                self.sessionState = .completed
                self.currentSession = session

                if self.settings.copyOnComplete {
                    let clipboardText = self.normalizedClipboardText(polished.markdown)
                    if !clipboardText.isEmpty {
                        Clipboard.copy(text: clipboardText)
                    }
                }
                self.statusMessage = "Polish retry complete"
                self.endPolishProgressTracking()
            } catch {
                self.lastError = error.localizedDescription
                self.statusMessage = "Polish retry failed"
                self.currentSession = session
                self.endPolishProgressTracking()
            }
        }
    }

    func retryTranscription(temporaryProviderID: String? = nil, temporaryModel: String? = nil) {
        Task { @MainActor [weak self] in
            guard let self,
                  var session = self.currentSession else {
                return
            }

            guard FileManager.default.fileExists(atPath: session.paths.audioURL.path) else {
                self.statusMessage = "No recorded audio available for re-transcription."
                return
            }

            do {
                self.lastError = nil
                let effectiveProviderID = temporaryProviderID ?? self.settings.transcriptionProviderID
                let effectiveModel = temporaryModel ?? self.settings.transcriptionModel
                var retrySettings = self.settings
                retrySettings.transcriptionProviderID = effectiveProviderID
                retrySettings.transcriptionModel = effectiveModel

                session.metadata.sttProvider = effectiveProviderID
                session.metadata.sttModel = effectiveModel
                session.metadata.polishProvider = self.settings.polishProviderID
                session.metadata.polishModel = self.settings.polishModel
                session.metadata.languageMode = self.settings.languageMode
                self.sessionState = .transcribing
                self.beginTranscribeProgressTracking()
                try self.sessionManager.transition(&session, to: .transcribing, details: "Retry transcription")

                let transcript = try await self.transcriptionPipeline.run(audioFileURL: session.paths.audioURL, settings: retrySettings)
                self.endTranscribeProgressTracking()
                self.rawTranscript = transcript.text
                try self.sessionManager.writeRaw(transcript.text, for: &session)

                do {
                    self.sessionState = .polishing
                    self.beginPolishProgressTracking()
                    try self.sessionManager.transition(&session, to: .polishing, details: "Polish after re-transcription")

                    let rules = try self.rulesStore.load()
                    let polished = try await self.polishPipeline.run(
                        rawText: transcript.text,
                        rulesMarkdown: rules,
                        settings: self.settings
                    )

                    self.polishedTranscript = polished.markdown
                    self.latestPolishedTranscript = polished.markdown
                    try self.sessionManager.writePolished(polished.markdown, for: &session)

                    if self.settings.copyOnComplete {
                        let clipboardText = self.normalizedClipboardText(polished.markdown)
                        if !clipboardText.isEmpty {
                            Clipboard.copy(text: clipboardText)
                        }
                    }
                    self.endPolishProgressTracking()
                } catch {
                    self.polishedTranscript = ""
                    self.lastError = error.localizedDescription
                    self.statusMessage = "Re-transcription complete. Polish failed."
                    self.endPolishProgressTracking()
                }

                try self.sessionManager.transition(&session, to: .completed, details: "Re-transcription complete")
                self.sessionState = .completed
                self.currentSession = session
                if self.lastError == nil {
                    self.statusMessage = "Re-transcription complete"
                }
            } catch {
                self.sessionManager.recordFailure(&session, error: error.localizedDescription)
                self.currentSession = session
                self.lastError = error.localizedDescription
                self.sessionState = .failed
                self.statusMessage = "Re-transcription failed"
                self.endPolishProgressTracking()
                self.endTranscribeProgressTracking()
            }
        }
    }

    func saveRulesDraft() {
        do {
            try rulesStore.save(rulesDraft)
            statusMessage = "Rules saved"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed to save rules"
        }
    }

    func reloadRulesDraft() {
        rulesStore.reload()
        rulesDraft = rulesStore.currentRules
        statusMessage = "Rules reloaded"
    }

    func downloadDefaultModelIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.modelManager.ensureInstalled(modelID: self.settings.transcriptionModel)
                self.statusMessage = "Model \(self.settings.transcriptionModel) installed"
            } catch {
                self.lastError = error.localizedDescription
                self.statusMessage = "Failed to download model"
            }
        }
    }

    func revealCurrentSessionInFinder() {
        guard let session = currentSession else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([session.paths.folderURL])
    }

    private func registerHotkeys() {
        do {
            try hotkeyManager.register(action: .startStop, setting: settings.startStopHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.toggleRecording()
                }
            }

            try hotkeyManager.register(action: .copyLatest, setting: settings.copyHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.copyLatestPolished()
                }
            }

            if settings.copyHotkey.normalizedForCarbonHotkey() == settings.pasteHotkey.normalizedForCarbonHotkey() {
                throw HotkeyError.registrationFailed(
                    "Paste hotkey cannot match copy hotkey. Choose a different shortcut."
                )
            }

            try hotkeyManager.register(action: .pasteLatest, setting: settings.pasteHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.pasteLatestPolishedViaHotkey()
                }
            }

            hotkeyError = nil
        } catch {
            hotkeyError = error.localizedDescription
            statusMessage = "Hotkey registration failed. Change hotkey in Settings."
        }
    }

    private func apiKeyStatusDescription(for entry: KeychainEntry) -> String {
        let resolution = apiKeyResolver.resolve(entry)

        switch resolution.source {
        case .keychain:
            if resolution.environmentPresent {
                return "\(entry.providerDisplayName): using saved Keychain key (overrides \(entry.environmentVariableName))."
            }
            return "\(entry.providerDisplayName): using saved Keychain key."
        case .environment:
            return "\(entry.providerDisplayName): using \(entry.environmentVariableName) from environment. Save a key above to override."
        case .missing:
            return "\(entry.providerDisplayName): no API key in Keychain or \(entry.environmentVariableName)."
        }
    }

    private func latestPolishedCandidate() -> String {
        let source = !polishedTranscript.isEmpty ? polishedTranscript : latestPolishedTranscript
        return normalizedClipboardText(source)
    }

    private func normalizedClipboardText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pasteLatestPolishedViaHotkey() {
        guard AccessibilityInputInjector.isTrusted(promptIfNeeded: false) else {
            statusMessage = "Paste hotkey requires Accessibility permission for SmartTranscript."
            return
        }

        let candidate = latestPolishedCandidate()
        guard !candidate.isEmpty else {
            statusMessage = "No polished transcript available yet"
            return
        }

        Clipboard.copy(text: candidate)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            if AccessibilityInputInjector.triggerPasteShortcut() {
                self.statusMessage = "Latest polished transcript pasted"
            } else {
                self.statusMessage = "Latest polished transcript copied"
            }
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func beginPolishProgressTracking() {
        polishTimer?.invalidate()
        polishStartedAt = Date()
        polishElapsedSeconds = 0

        polishTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePolishElapsedSeconds()
            }
        }
        if let polishTimer {
            RunLoop.main.add(polishTimer, forMode: .common)
        }
    }

    private func endPolishProgressTracking() {
        polishTimer?.invalidate()
        polishTimer = nil
        polishStartedAt = nil
        polishElapsedSeconds = 0
    }

    private func updatePolishElapsedSeconds() {
        guard let started = polishStartedAt else {
            polishElapsedSeconds = 0
            return
        }
        polishElapsedSeconds = max(0, Int(Date().timeIntervalSince(started)))
    }

    private func beginTranscribeProgressTracking() {
        transcribeTimer?.invalidate()
        transcribeStartedAt = Date()
        transcribeElapsedSeconds = 0

        transcribeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTranscribeElapsedSeconds()
            }
        }
        if let transcribeTimer {
            RunLoop.main.add(transcribeTimer, forMode: .common)
        }
    }

    private func endTranscribeProgressTracking() {
        transcribeTimer?.invalidate()
        transcribeTimer = nil
        transcribeStartedAt = nil
        transcribeElapsedSeconds = 0
    }

    private func updateTranscribeElapsedSeconds() {
        guard let started = transcribeStartedAt else {
            transcribeElapsedSeconds = 0
            return
        }
        transcribeElapsedSeconds = max(0, Int(Date().timeIntervalSince(started)))
    }
}
