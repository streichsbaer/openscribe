import AppKit
import Foundation

enum ProviderModelUsage {
    case transcription
    case polish
}

enum ProviderBackend: String {
    case whispercpp
    case openai
    case groq
    case openrouter
    case gemini

    var displayName: String {
        switch self {
        case .whispercpp:
            return "Local whisper.cpp"
        case .openai:
            return "OpenAI"
        case .groq:
            return "Groq"
        case .openrouter:
            return "OpenRouter"
        case .gemini:
            return "Gemini"
        }
    }

    var statusID: String { rawValue }
}

struct ProviderConnectivityStatus: Equatable {
    enum State: Equatable {
        case idle
        case verifying
        case verified
        case failed
    }

    var state: State
    var detail: String

    static let idle = ProviderConnectivityStatus(state: .idle, detail: "Not verified")
}

@MainActor
final class AppShell: ObservableObject {
    @Published var meterLevel: Float = 0
    @Published var permissionState: MicrophonePermissionState = .undetermined
    @Published var sessionState: SessionState = .idle

    @Published var currentSession: SessionContext?
    @Published var rawTranscript: String = ""
    @Published var polishedTranscript: String = ""
    @Published var rawTranscriptProviderID: String = ""
    @Published var rawTranscriptModel: String = ""
    @Published var polishedTranscriptProviderID: String = ""
    @Published var polishedTranscriptModel: String = ""
    @Published var statusMessage: String = "Ready"
    @Published var lastError: String?

    @Published var hotkeyError: String?

    @Published var rulesDraft: String

    @Published var openAIKeyInput: String = ""
    @Published var groqKeyInput: String = ""
    @Published var openRouterKeyInput: String = ""
    @Published var geminiKeyInput: String = ""
    @Published var latestPolishedTranscript: String = ""
    @Published var menubarIconDebug: String = "icon=idle"
    @Published var transcribeElapsedSeconds: Int = 0
    @Published var polishElapsedSeconds: Int = 0
    @Published private(set) var providerModelsByBackend: [String: [String]] = [:]
    @Published private(set) var providerConnectivityByBackend: [String: ProviderConnectivityStatus] = [:]

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
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("OpenScribe", isDirectory: true)
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
        self.openRouterKeyInput = keychainStore.load(.openRouter) ?? ""
        self.geminiKeyInput = keychainStore.load(.gemini) ?? ""

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
        applyAppearanceMode()
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

    var openRouterKeyStatusDescription: String {
        apiKeyStatusDescription(for: .openRouter)
    }

    var geminiKeyStatusDescription: String {
        apiKeyStatusDescription(for: .gemini)
    }

    var accessibilityPermissionGranted: Bool {
        AccessibilityInputInjector.isTrusted(promptIfNeeded: false)
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        settingsStore.update(mutate)
        registerHotkeys()
        applyAppearanceMode()
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

        let openRouter = openRouterKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if openRouter.isEmpty {
            keychainStore.delete(.openRouter)
        } else {
            try? keychainStore.save(openRouter, for: .openRouter)
        }

        let gemini = geminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if gemini.isEmpty {
            keychainStore.delete(.gemini)
        } else {
            try? keychainStore.save(gemini, for: .gemini)
        }

        statusMessage = "API keys saved"
    }

    func clearAPIKey(_ entry: KeychainEntry) {
        switch entry {
        case .openAI:
            openAIKeyInput = ""
        case .groq:
            groqKeyInput = ""
        case .openRouter:
            openRouterKeyInput = ""
        case .gemini:
            geminiKeyInput = ""
        }
        saveAPIKeys()
    }

    func clearAllAPIKeys() {
        openAIKeyInput = ""
        groqKeyInput = ""
        openRouterKeyInput = ""
        geminiKeyInput = ""
        saveAPIKeys()
        statusMessage = "API keys cleared"
    }

    func toggleRecording() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch self.sessionState {
            case .recording:
                await self.stopRecordingAndProcess()
            case .idle, .completed, .failed:
                await self.startRecording()
            case .finalizingAudio, .transcribing, .polishing:
                self.statusMessage = "\(self.sessionState.displayLabel) in progress"
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
        guard canStartRecording else {
            statusMessage = "\(sessionState.displayLabel) in progress"
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
            rawTranscriptProviderID = ""
            rawTranscriptModel = ""
            polishedTranscriptProviderID = ""
            polishedTranscriptModel = ""
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

    private var canStartRecording: Bool {
        switch sessionState {
        case .idle, .completed, .failed:
            return true
        case .recording, .finalizingAudio, .transcribing, .polishing:
            return false
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

            try await ensureLocalModelInstalledIfNeeded(using: settings)
            sessionState = .transcribing
            beginTranscribeProgressTracking()
            try sessionManager.transition(&session, to: .transcribing, details: "Running transcription")

            let transcript = try await transcriptionPipeline.run(audioFileURL: session.paths.audioURL, settings: settings)
            endTranscribeProgressTracking()
            rawTranscript = transcript.text
            rawTranscriptProviderID = transcript.providerId
            rawTranscriptModel = transcript.model
            try sessionManager.writeRaw(transcript.text, for: &session)

            if settings.polishEnabled {
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
                    polishedTranscriptProviderID = polished.providerId
                    polishedTranscriptModel = polished.model
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
                    polishedTranscriptProviderID = ""
                    polishedTranscriptModel = ""
                    statusMessage = "Raw transcript ready. Polish failed or needs API key."
                    lastError = error.localizedDescription
                    endPolishProgressTracking()
                }
            } else {
                try completeWithoutPolish(
                    rawText: transcript.text,
                    session: &session,
                    copyOnComplete: settings.copyOnComplete,
                    completionMessage: "Transcription complete",
                    copiedMessage: "Transcript copied (polish disabled)"
                )
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

    func retryPolish(temporaryModel: String? = nil) {
        Task { @MainActor [weak self] in
            guard let self,
                  var session = self.currentSession,
                  !self.rawTranscript.isEmpty else {
                return
            }

            guard self.settings.polishEnabled else {
                self.statusMessage = "Polish is disabled in Settings."
                return
            }

            do {
                let effectiveModel = temporaryModel ?? self.settings.polishModel
                var retrySettings = self.settings
                retrySettings.polishModel = effectiveModel

                session.metadata.polishProvider = self.settings.polishProviderID
                session.metadata.polishModel = effectiveModel
                self.sessionState = .polishing
                self.beginPolishProgressTracking()
                try self.sessionManager.transition(&session, to: .polishing, details: "Retry polish")
                let rules = try self.rulesStore.load()
                let polished = try await self.polishPipeline.run(
                    rawText: self.rawTranscript,
                    rulesMarkdown: rules,
                    settings: retrySettings
                )

                self.polishedTranscript = polished.markdown
                self.latestPolishedTranscript = polished.markdown
                self.polishedTranscriptProviderID = polished.providerId
                self.polishedTranscriptModel = polished.model
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
                session.metadata.polishProvider = self.settings.polishEnabled ? self.settings.polishProviderID : "disabled"
                session.metadata.polishModel = self.settings.polishEnabled ? self.settings.polishModel : "passthrough"
                session.metadata.languageMode = self.settings.languageMode
                try await self.ensureLocalModelInstalledIfNeeded(using: retrySettings)
                self.sessionState = .transcribing
                self.beginTranscribeProgressTracking()
                try self.sessionManager.transition(&session, to: .transcribing, details: "Retry transcription")

                let transcript = try await self.transcriptionPipeline.run(audioFileURL: session.paths.audioURL, settings: retrySettings)
                self.endTranscribeProgressTracking()
                self.rawTranscript = transcript.text
                self.rawTranscriptProviderID = transcript.providerId
                self.rawTranscriptModel = transcript.model
                try self.sessionManager.writeRaw(transcript.text, for: &session)

                if self.settings.polishEnabled {
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
                        self.polishedTranscriptProviderID = polished.providerId
                        self.polishedTranscriptModel = polished.model
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
                        self.polishedTranscriptProviderID = ""
                        self.polishedTranscriptModel = ""
                        self.lastError = error.localizedDescription
                        self.statusMessage = "Re-transcription complete. Polish failed."
                        self.endPolishProgressTracking()
                    }
                } else {
                    try self.completeWithoutPolish(
                        rawText: transcript.text,
                        session: &session,
                        copyOnComplete: self.settings.copyOnComplete,
                        completionMessage: "Re-transcription complete",
                        copiedMessage: "Transcript copied (polish disabled)"
                    )
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

    func installWhisperModel(_ modelID: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await self.modelManager.ensureInstalled(modelID: modelID)
                self.statusMessage = "Model \(modelID) installed"
            } catch {
                self.lastError = error.localizedDescription
                self.statusMessage = "Failed to download model"
            }
        }
    }

    func removeWhisperModel(_ modelID: String) {
        do {
            try modelManager.remove(modelID: modelID)
            objectWillChange.send()
            statusMessage = "Model \(modelID) removed"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed to remove model"
        }
    }

    func moveAppSupportToTrash() {
        let fileManager = FileManager.default
        let appSupportURL = layout.appSupport
        guard fileManager.fileExists(atPath: appSupportURL.path) else {
            statusMessage = "App Support folder is already missing"
            return
        }

        do {
            _ = try fileManager.trashItem(at: appSupportURL, resultingItemURL: nil)
            statusMessage = "App Support moved to Trash"
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Failed to move App Support to Trash"
        }
    }

    func revealCurrentSessionInFinder() {
        guard let session = currentSession else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([session.paths.folderURL])
    }

    func availableModels(
        for providerID: String,
        usage: ProviderModelUsage,
        fallback: [String]
    ) -> [String] {
        let backend = backend(for: providerID)
        guard let backend else { return fallback }

        let fetched = providerModelsByBackend[backend.statusID] ?? []
        guard !fetched.isEmpty else {
            return fallback
        }

        let filtered = filterModels(fetched, backend: backend, usage: usage)
        if filtered.isEmpty {
            return fallback
        }

        return filtered
    }

    func providerConnectivityStatus(for providerID: String) -> ProviderConnectivityStatus {
        guard let backend = backend(for: providerID) else {
            return .idle
        }
        return providerConnectivityByBackend[backend.statusID] ?? .idle
    }

    func verifyProvider(for providerID: String) {
        guard let backend = backend(for: providerID) else {
            return
        }

        providerConnectivityByBackend[backend.statusID] = .init(state: .verifying, detail: "Verifying...")

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let models = try await self.fetchModels(for: backend)
                self.providerModelsByBackend[backend.statusID] = models
                self.providerConnectivityByBackend[backend.statusID] = .init(
                    state: .verified,
                    detail: "Verified (\(models.count) models)"
                )
                self.statusMessage = "\(backend.displayName) verified"
            } catch {
                self.providerConnectivityByBackend[backend.statusID] = .init(
                    state: .failed,
                    detail: "Failed: \(error.localizedDescription)"
                )
                self.statusMessage = "\(backend.displayName) verification failed"
            }
        }
    }

    func refreshModels(for providerID: String) {
        verifyProvider(for: providerID)
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

    private func backend(for providerID: String) -> ProviderBackend? {
        switch providerID {
        case "whispercpp":
            return .whispercpp
        case "openai_whisper", "openai_polish":
            return .openai
        case "groq_whisper", "groq_polish":
            return .groq
        case "openrouter_transcribe", "openrouter_polish":
            return .openrouter
        case "gemini_transcribe", "gemini_polish":
            return .gemini
        default:
            return nil
        }
    }

    private func filterModels(
        _ models: [String],
        backend: ProviderBackend,
        usage: ProviderModelUsage
    ) -> [String] {
        switch (backend, usage) {
        case (.openai, .transcription):
            let filtered = models.filter { id in
                let value = id.lowercased()
                return value.contains("transcribe") || value.contains("whisper")
            }
            return filtered.sorted()
        case (.openai, .polish):
            let filtered = models.filter { id in
                let value = id.lowercased()
                return !value.contains("transcribe")
            }
            return filtered.sorted()
        case (.groq, .transcription):
            let filtered = models.filter { $0.lowercased().contains("whisper") }
            return filtered.sorted()
        case (.groq, .polish):
            let filtered = models.filter { !$0.lowercased().contains("whisper") }
            return filtered.sorted()
        case (.whispercpp, _), (.openrouter, _), (.gemini, _):
            return models.sorted()
        }
    }

    private func fetchModels(for backend: ProviderBackend) async throws -> [String] {
        switch backend {
        case .whispercpp:
            return modelManager.catalog.map(\.id).sorted()
        case .openai:
            let key = apiKeyResolver.resolve(.openAI).value
            guard let key else { throw ProviderError.missingAPIKey("OpenAI") }
            return try await fetchOpenAICompatibleModels(
                endpoint: URL(string: "https://api.openai.com/v1/models")!,
                apiKey: key
            )
        case .groq:
            let key = apiKeyResolver.resolve(.groq).value
            guard let key else { throw ProviderError.missingAPIKey("Groq") }
            return try await fetchOpenAICompatibleModels(
                endpoint: URL(string: "https://api.groq.com/openai/v1/models")!,
                apiKey: key
            )
        case .openrouter:
            let key = apiKeyResolver.resolve(.openRouter).value
            guard let key else { throw ProviderError.missingAPIKey("OpenRouter") }
            return try await fetchOpenAICompatibleModels(
                endpoint: URL(string: "https://openrouter.ai/api/v1/models")!,
                apiKey: key
            )
        case .gemini:
            let key = apiKeyResolver.resolve(.gemini).value
            guard let key else { throw ProviderError.missingAPIKey("Gemini") }
            return try await fetchGeminiModels(apiKey: key)
        }
    }

    private func fetchOpenAICompatibleModels(endpoint: URL, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAICompatibleError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return extractModelIDs(from: data)
    }

    private func fetchGeminiModels(apiKey: String) async throws -> [String] {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let endpoint = components.url else {
            throw ProviderError.invalidResponse
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAICompatibleError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return extractModelIDs(from: data)
    }

    private func extractModelIDs(from data: Data) -> [String] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var modelIDs: [String] = []

        if let entries = raw["data"] as? [[String: Any]] {
            modelIDs.append(contentsOf: entries.compactMap { entry in
                (entry["id"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            })
        }

        if let entries = raw["models"] as? [[String: Any]] {
            modelIDs.append(contentsOf: entries.compactMap { entry in
                let name = (entry["name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if name.hasPrefix("models/") {
                    return String(name.dropFirst("models/".count))
                }
                return name.isEmpty ? nil : name
            })
        }

        let unique = Array(Set(modelIDs.filter { !$0.isEmpty }))
        return unique.sorted()
    }

    private func apiKeyStatusDescription(for entry: KeychainEntry) -> String {
        let resolution = apiKeyResolver.resolve(entry)
        let environmentSummary = entry.environmentVariableNames.joined(separator: " or ")

        switch resolution.source {
        case .keychain:
            if resolution.environmentPresent {
                if let matched = resolution.environmentVariableNameUsed {
                    return "\(entry.providerDisplayName): using saved Keychain key (overrides \(matched))."
                }
                return "\(entry.providerDisplayName): using saved Keychain key (overrides environment key)."
            }
            return "\(entry.providerDisplayName): using saved Keychain key."
        case .environment:
            let matched = resolution.environmentVariableNameUsed ?? environmentSummary
            return "\(entry.providerDisplayName): using \(matched) from environment. Save a key above to override."
        case .missing:
            return "\(entry.providerDisplayName): no API key in Keychain or \(environmentSummary)."
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
            statusMessage = "Paste hotkey requires Accessibility permission for OpenScribe."
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

    private func applyAppearanceMode() {
        let mode = AppearanceMode(rawValue: settings.appearanceMode) ?? .system
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func ensureLocalModelInstalledIfNeeded(using settings: AppSettings) async throws {
        guard settings.transcriptionProviderID == "whispercpp" else {
            return
        }
        let modelID = settings.transcriptionModel
        guard !modelManager.isInstalled(modelID: modelID) else {
            return
        }

        statusMessage = "Downloading local model \(modelID)..."
        _ = try await modelManager.ensureInstalled(modelID: modelID)
    }

    private func completeWithoutPolish(
        rawText: String,
        session: inout SessionContext,
        copyOnComplete: Bool,
        completionMessage: String,
        copiedMessage: String
    ) throws {
        polishedTranscript = rawText
        latestPolishedTranscript = rawText
        polishedTranscriptProviderID = "disabled"
        polishedTranscriptModel = "passthrough"
        session.metadata.polishProvider = "disabled"
        session.metadata.polishModel = "passthrough"
        try sessionManager.writePolished(rawText, for: &session)

        if copyOnComplete {
            let clipboardText = normalizedClipboardText(rawText)
            if !clipboardText.isEmpty {
                Clipboard.copy(text: clipboardText)
            }
            statusMessage = copiedMessage
        } else {
            statusMessage = completionMessage
        }
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
