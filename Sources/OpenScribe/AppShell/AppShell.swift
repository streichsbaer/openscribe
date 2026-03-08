import AppKit
import Carbon
import Foundation

enum ProviderModelUsage {
    case transcription
    case polish
}

enum PopoverTabSelection: String {
    case live
    case history
    case stats
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
    private static let autoPasteOnCompleteDefaultsKey = "behavior.autoPasteOnComplete"
    private static let historyDefaultInitialLoad = 10
    private static let livePopoverSize = CGSize(width: 540, height: 620)
    private static let historyPopoverSize = CGSize(width: 620, height: 700)
    private static let statsPopoverSize = CGSize(width: 620, height: 700)
    private static let showLiveTabHotkey = HotkeySetting(
        keyCode: 37, // ANSI L
        modifiers: UInt32(controlKey | optionKey)
    )
    private static let showHistoryTabHotkey = HotkeySetting(
        keyCode: 4, // ANSI H
        modifiers: UInt32(controlKey | optionKey)
    )
    private static let showStatsTabHotkey = HotkeySetting(
        keyCode: 1, // ANSI S
        modifiers: UInt32(controlKey | optionKey)
    )
    private static let openRulesTabHotkey = HotkeySetting(
        keyCode: 15, // ANSI R
        modifiers: UInt32(controlKey | optionKey)
    )

    enum HistoryLoadMoreMode: String, CaseIterable, Identifiable {
        case next10
        case next25
        case next50
        case whole

        var id: String { rawValue }

        var actionLabel: String {
            switch self {
            case .next10:
                return "Load next 10"
            case .next25:
                return "Load next 25"
            case .next50:
                return "Load next 50"
            case .whole:
                return "Load whole"
            }
        }

        var increment: Int? {
            switch self {
            case .next10:
                return 10
            case .next25:
                return 25
            case .next50:
                return 50
            case .whole:
                return nil
            }
        }
    }

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
    @Published var selectedPopoverTab: PopoverTabSelection = .live

    @Published var openAIKeyInput: String = ""
    @Published var groqKeyInput: String = ""
    @Published var openRouterKeyInput: String = ""
    @Published var geminiKeyInput: String = ""
    @Published var latestPolishedTranscript: String = ""
    @Published var transcribeElapsedSeconds: Int = 0
    @Published var polishElapsedSeconds: Int = 0
    @Published private(set) var availableMicrophones: [MicrophoneDevice] = []
    @Published private(set) var systemDefaultMicrophoneName: String = "Unknown input"
    @Published private(set) var systemDefaultMicrophoneID: String?
    @Published var sessionMicrophoneOverrideID: String?
    @Published private(set) var historySessions: [SessionHistoryEntry] = []
    @Published private(set) var historyHasMoreSessions: Bool = false
    @Published private(set) var historyIsLoading: Bool = false
    @Published private(set) var statsSummary: StatsSummary = .empty
    @Published private(set) var providerModelsByBackend: [String: [String]] = [:]
    @Published private(set) var providerConnectivityByBackend: [String: ProviderConnectivityStatus] = [:]
    @Published var autoPasteOnComplete: Bool {
        didSet {
            userDefaults.set(autoPasteOnComplete, forKey: Self.autoPasteOnCompleteDefaultsKey)
        }
    }

    var openSettingsWindowHandler: (() -> Void)?
    var openRulesWindowHandler: (() -> Void)?
    var togglePopoverHandler: (() -> Void)?
    var showPopoverHandler: (() -> Void)?
    var updatePopoverSizeHandler: ((CGSize) -> Void)?

    let layout: DirectoryLayout
    let settingsStore: SettingsStore
    let rulesStore: RulesStore
    let modelManager: ModelDownloadManager
    let audioMeter = AudioMeterState()

    private let keychainStore: KeychainStore
    private let apiKeyResolver: APIKeyResolver
    private let sessionManager: SessionManager
    private let statsStore: StatsStore
    private let audioCapture: AudioCaptureManager
    private let microphoneCatalog: MicrophoneDeviceCatalogProtocol
    private let hotkeyManager: HotkeyManager
    private let providerFactory: ProviderFactory
    private let transcriptionPipeline: TranscriptionPipeline
    private let polishPipeline: PolishPipeline
    private let userDefaults: UserDefaults
    private var transcribeTimer: Timer?
    private var transcribeStartedAt: Date?
    private var polishTimer: Timer?
    private var polishStartedAt: Date?

    init() {
        let resolvedLayout: DirectoryLayout
        do {
            resolvedLayout = try DirectoryLayout.resolve()
        } catch {
            preconditionFailure("Failed to resolve OpenScribe directories: \(error.localizedDescription)")
        }

        self.layout = resolvedLayout
        self.settingsStore = SettingsStore(layout: resolvedLayout)
        self.rulesStore = RulesStore(layout: resolvedLayout)
        self.modelManager = ModelDownloadManager(layout: resolvedLayout)
        self.keychainStore = KeychainStore()
        self.apiKeyResolver = APIKeyResolver(keychain: keychainStore)
        self.sessionManager = SessionManager(layout: resolvedLayout)
        self.statsStore = StatsStore(layout: resolvedLayout)
        self.audioCapture = AudioCaptureManager()
        self.microphoneCatalog = MicrophoneDeviceCatalog()
        self.hotkeyManager = HotkeyManager()

        let factory = ProviderFactory(keychain: keychainStore, modelManager: modelManager)
        self.providerFactory = factory
        self.transcriptionPipeline = TranscriptionPipeline(providerFactory: factory)
        self.polishPipeline = PolishPipeline(providerFactory: factory)
        self.userDefaults = .standard
        self.autoPasteOnComplete = userDefaults.object(forKey: Self.autoPasteOnCompleteDefaultsKey) as? Bool ?? false

        self.rulesDraft = rulesStore.currentRules
        self.permissionState = audioCapture.permissionState()
        applyMicrophoneSnapshot(microphoneCatalog.currentSnapshot())

        self.openAIKeyInput = keychainStore.load(.openAI) ?? ""
        self.groqKeyInput = keychainStore.load(.groq) ?? ""
        self.openRouterKeyInput = keychainStore.load(.openRouter) ?? ""
        self.geminiKeyInput = keychainStore.load(.gemini) ?? ""

        audioCapture.onLevelUpdate = { [audioMeter] level in
            Task { @MainActor in
                audioMeter.level = level
            }
        }
        microphoneCatalog.onSnapshotChange = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.applyMicrophoneSnapshot(snapshot)
            }
        }

        let dangling = sessionManager.recoverDanglingRecordings()
        if !dangling.isEmpty {
            statusMessage = "Found \(dangling.count) unfinished recording file(s)."
        }

        latestPolishedTranscript = sessionManager.loadLatestPolishedTranscript() ?? ""
        refreshHistorySessions()
        refreshStatsSummary()

        normalizeReservedHotkeyConflicts()
        registerHotkeys()
        applyAppearanceMode()
        prefetchProviderCatalogsOnLaunch()
    }

    var settings: AppSettings {
        settingsStore.settings
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

    func setSessionMicrophoneOverride(_ id: String?) {
        if let id, !id.isEmpty {
            sessionMicrophoneOverrideID = id
        } else {
            sessionMicrophoneOverrideID = nil
        }
    }

    func setPinnedMicrophone(_ id: String?) {
        let normalizedID = id?.isEmpty == true ? nil : id
        let devicesByID = Dictionary(uniqueKeysWithValues: availableMicrophones.map { ($0.id, $0) })

        updateSettings { settings in
            guard let normalizedID else {
                settings.pinnedMicrophone = nil
                return
            }

            if let device = devicesByID[normalizedID] {
                settings.pinnedMicrophone = PinnedMicrophone(id: device.id, name: device.name)
                return
            }

            let retainedName = settings.pinnedMicrophone?.name ?? "Pinned microphone"
            settings.pinnedMicrophone = PinnedMicrophone(id: normalizedID, name: retainedName)
        }
    }

    func microphoneName(for id: String) -> String? {
        availableMicrophones.first(where: { $0.id == id })?.name
    }

    func isMicrophoneCurrentlyAvailable(_ id: String) -> Bool {
        availableMicrophones.contains(where: { $0.id == id })
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

    func openRulesWindow() {
        openRulesWindowHandler?()
    }

    func togglePopoverWindow() {
        togglePopoverHandler?()
    }

    func showPopoverWindow() {
        showPopoverHandler?()
    }

    func openAccessibilityPrivacySettings() {
        openSystemSettings(path: "com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophonePrivacySettings() {
        openSystemSettings(path: "com.apple.preference.security?Privacy_Microphone")
    }

    func openSoundInputSettings() {
        openSystemSettings(path: "com.apple.Sound-Settings.extension?input")
    }

    func refreshPermissionState() {
        permissionState = audioCapture.permissionState()
        applyMicrophoneSnapshot(microphoneCatalog.currentSnapshot())
        registerHotkeys()
    }

    func updatePopoverSize(selectedTab: PopoverTabSelection) {
        updatePopoverSizeHandler?(preferredPopoverSize(selectedTab: selectedTab))
    }

    func selectPopoverTab(_ tab: PopoverTabSelection, revealPopover: Bool = false) {
        selectedPopoverTab = tab
        if tab == .history {
            refreshHistorySessions(preserveLoadedCount: true)
        } else if tab == .stats {
            refreshStatsSummary()
        }
        updatePopoverSize(selectedTab: tab)
        if revealPopover {
            showPopoverWindow()
        }
    }

    func preferredPopoverSizeForCurrentState() -> CGSize {
        preferredPopoverSize(selectedTab: selectedPopoverTab)
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

        let microphoneResolution = resolveMicrophoneForNextRecording()
        guard microphoneResolution.source != .unavailable else {
            lastError = microphoneResolution.statusMessage ?? "No microphone input is currently available."
            statusMessage = microphoneResolution.statusMessage ?? "No microphone input is currently available."
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
                inputDeviceName: microphoneResolution.device?.name ?? systemDefaultMicrophoneName
            )
            try sessionManager.transition(&session, to: .recording, details: "Audio capture started")
            let inputDeviceID = MicrophoneCaptureRouting.inputDeviceIDForCapture(
                resolution: microphoneResolution,
                systemDefaultDeviceID: systemDefaultMicrophoneID
            )
            try audioCapture.startRecording(
                to: session.paths.audioTempURL,
                inputDeviceID: inputDeviceID
            )
            currentSession = session
            sessionMicrophoneOverrideID = nil

            sessionState = .recording
            statusMessage = microphoneResolution.statusMessage ?? "Recording"
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

    private func applyMicrophoneSnapshot(_ snapshot: MicrophoneDeviceSnapshot) {
        availableMicrophones = snapshot.devices
        systemDefaultMicrophoneID = snapshot.systemDefaultDeviceID
        systemDefaultMicrophoneName = snapshot.systemDefaultDeviceName
            ?? snapshot.devices.first?.name
            ?? "Unknown input"

        if let sessionMicrophoneOverrideID,
           !snapshot.devices.contains(where: { $0.id == sessionMicrophoneOverrideID }) {
            self.sessionMicrophoneOverrideID = nil
        }
    }

    private func resolveMicrophoneForNextRecording() -> MicrophoneResolutionResult {
        let snapshot = microphoneCatalog.currentSnapshot()
        applyMicrophoneSnapshot(snapshot)
        return MicrophoneSelectionResolver.resolve(
            snapshot: snapshot,
            pinnedMicrophone: settings.pinnedMicrophone,
            sessionOverrideID: sessionMicrophoneOverrideID
        )
    }

    func stopRecordingAndProcess() async {
        guard var session = currentSession else {
            return
        }

        do {
            sessionState = .finalizingAudio
            try sessionManager.transition(&session, to: .finalizingAudio, details: "Stopping audio capture")

            let audioActivity = audioCapture.stopRecording()
            try sessionManager.finalizeAudioFile(&session)
            try sessionManager.stopSession(&session)
            session.metadata.audioActivity = audioActivity

            if !audioActivity.hasUsableSpeech {
                try completeWithoutUsableAudio(session: &session, reason: audioActivity.reason)
                currentSession = session
                return
            }

            try await ensureLocalModelInstalledIfNeeded(using: settings)
            sessionState = .transcribing
            beginTranscribeProgressTracking()
            try sessionManager.transition(&session, to: .transcribing, details: "Running transcription")

            let transcript = try await runTranscriptionWithRetry(audioFileURL: session.paths.audioURL, settings: settings)
            let transcribeProcessingMs = transcribeElapsedMs()
            endTranscribeProgressTracking()
            rawTranscript = transcript.text
            rawTranscriptProviderID = transcript.providerId
            rawTranscriptModel = transcript.model
            try sessionManager.writeRaw(transcript.text, for: &session)
            recordTranscriptionStats(session: session, transcript: transcript, rawText: transcript.text, processingDurationMs: transcribeProcessingMs)

            if settings.polishEnabled {
                sessionState = .polishing
                beginPolishProgressTracking()
                try sessionManager.transition(&session, to: .polishing, details: "Running polish")

                let rules = try rulesStore.load()
                let polished = try await runPolishWithRetry(
                    rawText: transcript.text,
                    rulesMarkdown: rules,
                    settings: settings
                )

                polishedTranscript = polished.markdown
                latestPolishedTranscript = polished.markdown
                polishedTranscriptProviderID = polished.providerId
                polishedTranscriptModel = polished.model
                try sessionManager.writePolished(polished.markdown, for: &session)
                recordPolishStats(
                    session: session,
                    polish: polished,
                    rawText: transcript.text,
                    polishedText: polished.markdown,
                    processingDurationMs: polishElapsedMs()
                )

                deliverOutput(
                    polished.markdown,
                    completionMessage: "Transcription complete",
                    copiedMessage: "Polished transcript copied",
                    pastedMessage: "Polished transcript pasted"
                )
                endPolishProgressTracking()
            } else {
                try completeWithoutPolish(
                    rawText: transcript.text,
                    session: &session,
                    completionMessage: "Transcription complete",
                    copiedMessage: "Transcript copied (polish disabled)",
                    pastedMessage: "Transcript pasted (polish disabled)"
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
            if ProviderRetryPolicy.isProviderRelatedError(error) {
                statusMessage = "Session failed. Check API key or switch provider/model, then retry."
            } else {
                statusMessage = "Session failed"
            }
            endPolishProgressTracking()
            endTranscribeProgressTracking()
        }
    }

    func retryPolish(temporaryProviderID: String? = nil, temporaryModel: String? = nil) {
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
                let effectiveProviderID = temporaryProviderID ?? self.settings.polishProviderID
                let effectiveModel = temporaryModel ?? self.settings.polishModel
                var retrySettings = self.settings
                retrySettings.polishProviderID = effectiveProviderID
                retrySettings.polishModel = effectiveModel

                session.metadata.polishProvider = effectiveProviderID
                session.metadata.polishModel = effectiveModel
                self.sessionState = .polishing
                self.beginPolishProgressTracking()
                try self.sessionManager.transition(&session, to: .polishing, details: "Retry polish")
                let rules = try self.rulesStore.load()
                let polished = try await self.runPolishWithRetry(
                    rawText: self.rawTranscript,
                    rulesMarkdown: rules,
                    settings: retrySettings
                )

                self.polishedTranscript = polished.markdown
                self.latestPolishedTranscript = polished.markdown
                self.polishedTranscriptProviderID = polished.providerId
                self.polishedTranscriptModel = polished.model
                try self.sessionManager.writePolished(polished.markdown, for: &session)
                self.recordPolishStats(
                    session: session,
                    polish: polished,
                    rawText: self.rawTranscript,
                    polishedText: polished.markdown,
                    processingDurationMs: self.polishElapsedMs()
                )
                try self.sessionManager.transition(&session, to: .completed, details: "Polish retry complete")
                self.sessionState = .completed
                self.currentSession = session

                self.deliverOutput(
                    polished.markdown,
                    completionMessage: "Polish retry complete",
                    copiedMessage: "Polished transcript copied",
                    pastedMessage: "Polished transcript pasted"
                )
                self.endPolishProgressTracking()
            } catch {
                self.lastError = error.localizedDescription
                if ProviderRetryPolicy.isProviderRelatedError(error) {
                    self.statusMessage = "Polish failed. Check API key or switch provider/model, then retry."
                } else {
                    self.statusMessage = "Polish retry failed"
                }
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

            if let audioActivity = session.metadata.audioActivity, !audioActivity.hasUsableSpeech {
                self.rawTranscript = ""
                self.polishedTranscript = ""
                self.rawTranscriptProviderID = ""
                self.rawTranscriptModel = ""
                self.polishedTranscriptProviderID = ""
                self.polishedTranscriptModel = ""
                self.statusMessage = "No audio captured. Speak clearly and try again."
                return
            }

            var didWriteFreshRawTranscript = false

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

                let transcript = try await self.runTranscriptionWithRetry(audioFileURL: session.paths.audioURL, settings: retrySettings)
                let transcribeProcessingMs = self.transcribeElapsedMs()
                self.endTranscribeProgressTracking()
                self.rawTranscript = transcript.text
                self.rawTranscriptProviderID = transcript.providerId
                self.rawTranscriptModel = transcript.model
                try self.sessionManager.writeRaw(transcript.text, for: &session)
                didWriteFreshRawTranscript = true
                self.recordTranscriptionStats(session: session, transcript: transcript, rawText: transcript.text, processingDurationMs: transcribeProcessingMs)

                if self.settings.polishEnabled {
                    self.sessionState = .polishing
                    self.beginPolishProgressTracking()
                    try self.sessionManager.transition(&session, to: .polishing, details: "Polish after re-transcription")

                    let rules = try self.rulesStore.load()
                    let polished = try await self.runPolishWithRetry(
                        rawText: transcript.text,
                        rulesMarkdown: rules,
                        settings: self.settings
                    )

                    self.polishedTranscript = polished.markdown
                    self.latestPolishedTranscript = polished.markdown
                    self.polishedTranscriptProviderID = polished.providerId
                    self.polishedTranscriptModel = polished.model
                    try self.sessionManager.writePolished(polished.markdown, for: &session)
                    self.recordPolishStats(
                        session: session,
                        polish: polished,
                        rawText: transcript.text,
                        polishedText: polished.markdown,
                        processingDurationMs: self.polishElapsedMs()
                    )

                    self.deliverOutput(
                        polished.markdown,
                        completionMessage: "Re-transcription complete",
                        copiedMessage: "Polished transcript copied",
                        pastedMessage: "Polished transcript pasted"
                    )
                    self.endPolishProgressTracking()
                } else {
                    try self.completeWithoutPolish(
                        rawText: transcript.text,
                        session: &session,
                        completionMessage: "Re-transcription complete",
                        copiedMessage: "Transcript copied (polish disabled)",
                        pastedMessage: "Transcript pasted (polish disabled)"
                    )
                }

                try self.sessionManager.transition(&session, to: .completed, details: "Re-transcription complete")
                self.sessionState = .completed
                self.currentSession = session
            } catch {
                RetryTranscriptionFailureStateReset.apply(
                    didWriteFreshRawTranscript: didWriteFreshRawTranscript,
                    polishEnabled: self.settings.polishEnabled,
                    session: &session,
                    sessionManager: self.sessionManager,
                    polishedTranscript: &self.polishedTranscript,
                    polishedTranscriptProviderID: &self.polishedTranscriptProviderID,
                    polishedTranscriptModel: &self.polishedTranscriptModel,
                    latestPolishedTranscript: &self.latestPolishedTranscript
                )

                self.sessionManager.recordFailure(&session, error: error.localizedDescription)
                self.currentSession = session
                self.lastError = error.localizedDescription
                self.sessionState = .failed
                if ProviderRetryPolicy.isProviderRelatedError(error) {
                    self.statusMessage = "Processing failed. Check API key or switch provider/model, then retry."
                } else {
                    self.statusMessage = "Re-transcription failed"
                }
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

    var canRunHistoryProcessingActions: Bool {
        !isSessionPipelineBusy
    }

    @discardableResult
    func openHistorySession(_ entry: SessionHistoryEntry) -> Bool {
        guard canRunHistoryProcessingActions else {
            statusMessage = "\(sessionState.displayLabel) in progress"
            return false
        }

        guard let loaded = sessionManager.loadSessionContext(folderURL: entry.folderURL) else {
            statusMessage = "Unable to open selected history session."
            return false
        }

        currentSession = loaded
        sessionState = loaded.metadata.state

        rawTranscript = readTextFile(at: loaded.paths.rawURL) ?? ""
        polishedTranscript = readTextFile(at: loaded.paths.polishedURL) ?? ""

        rawTranscriptProviderID = rawTranscript.isEmpty ? "" : loaded.metadata.sttProvider
        rawTranscriptModel = rawTranscript.isEmpty ? "" : loaded.metadata.sttModel
        polishedTranscriptProviderID = polishedTranscript.isEmpty ? "" : loaded.metadata.polishProvider
        polishedTranscriptModel = polishedTranscript.isEmpty ? "" : loaded.metadata.polishModel

        if !polishedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            latestPolishedTranscript = polishedTranscript
        }

        lastError = nil
        statusMessage = "Loaded history session"
        return true
    }

    func revealHistorySessionInFinder(_ entry: SessionHistoryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.folderURL])
    }

    func deleteHistorySessions(_ entries: [SessionHistoryEntry]) {
        guard !entries.isEmpty else {
            return
        }

        let fileManager = FileManager.default
        let unique = Dictionary(uniqueKeysWithValues: entries.map { ($0.folderURL.standardizedFileURL.path, $0.folderURL.standardizedFileURL) })
        var deletedCount = 0
        var failedCount = 0
        var firstFailure: String?

        for folderURL in unique.values {
            if isCurrentSession(folderURL: folderURL), isSessionPipelineBusy {
                failedCount += 1
                firstFailure = firstFailure ?? "Cannot delete an active processing session."
                continue
            }

            do {
                _ = try fileManager.trashItem(at: folderURL, resultingItemURL: nil)
                deletedCount += 1
                if isCurrentSession(folderURL: folderURL) {
                    clearLoadedSessionAfterDelete()
                }
            } catch {
                failedCount += 1
                if firstFailure == nil {
                    firstFailure = error.localizedDescription
                }
            }
        }

        refreshHistorySessions(preserveLoadedCount: true)
        latestPolishedTranscript = sessionManager.loadLatestPolishedTranscript() ?? ""

        if deletedCount > 0, failedCount == 0 {
            statusMessage = deletedCount == 1 ? "Deleted 1 session" : "Deleted \(deletedCount) sessions"
            return
        }

        if deletedCount > 0, failedCount > 0 {
            statusMessage = "Deleted \(deletedCount) sessions. Failed to delete \(failedCount)."
            lastError = firstFailure
            return
        }

        statusMessage = "Failed to delete selected sessions."
        lastError = firstFailure
    }

    var visibleHistorySessions: [SessionHistoryEntry] {
        historySessions
    }

    var historyCanLoadMore: Bool {
        historyHasMoreSessions
    }

    var historyLoadMoreModes: [HistoryLoadMoreMode] {
        HistoryLoadMoreMode.allCases
    }

    func refreshHistorySessions(preserveLoadedCount: Bool = false) {
        historyIsLoading = true
        let targetLimit: Int
        if preserveLoadedCount {
            targetLimit = max(Self.historyDefaultInitialLoad, historySessions.count)
        } else {
            targetLimit = Self.historyDefaultInitialLoad
        }
        let result = sessionManager.loadSessionHistoryPage(limit: targetLimit)
        historySessions = result.entries
        historyHasMoreSessions = result.hasMore
        historyIsLoading = false
    }

    func refreshStatsSummary() {
        statsSummary = statsStore.loadSummary()
    }

    func showLiveTabFromHotkey() {
        selectPopoverTab(.live, revealPopover: true)
    }

    func showHistoryTabFromHotkey() {
        selectPopoverTab(.history, revealPopover: true)
    }

    func showStatsTabFromHotkey() {
        selectPopoverTab(.stats, revealPopover: true)
    }

    func openRulesFromHotkey() {
        openRulesWindow()
    }

    func loadMoreHistorySessions(mode: HistoryLoadMoreMode) {
        guard historyCanLoadMore, !historyIsLoading else {
            return
        }

        historyIsLoading = true
        let nextLimit: Int
        if let increment = mode.increment {
            nextLimit = historySessions.count + increment
        } else {
            nextLimit = Int.max
        }

        let result = sessionManager.loadSessionHistoryPage(limit: nextLimit)
        historySessions = result.entries
        historyHasMoreSessions = result.hasMore
        historyIsLoading = false
    }

    private var isSessionPipelineBusy: Bool {
        switch sessionState {
        case .recording, .finalizingAudio, .transcribing, .polishing:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }

    private func isCurrentSession(folderURL: URL) -> Bool {
        guard let current = currentSession?.paths.folderURL else {
            return false
        }
        return current.standardizedFileURL == folderURL.standardizedFileURL
    }

    private func clearLoadedSessionAfterDelete() {
        currentSession = nil
        rawTranscript = ""
        polishedTranscript = ""
        rawTranscriptProviderID = ""
        rawTranscriptModel = ""
        polishedTranscriptProviderID = ""
        polishedTranscriptModel = ""
        sessionState = .idle
    }

    private func readTextFile(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func preferredPopoverSize(selectedTab: PopoverTabSelection) -> CGSize {
        switch selectedTab {
        case .live:
            return Self.livePopoverSize
        case .history:
            return Self.historyPopoverSize
        case .stats:
            return Self.statsPopoverSize
        }
    }

    func availableModels(
        for providerID: String,
        usage: ProviderModelUsage
    ) -> [String] {
        let fallback = fallbackModels(for: providerID, usage: usage)
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

    private func fallbackModels(for providerID: String, usage: ProviderModelUsage) -> [String] {
        switch (providerID, usage) {
        case ("whispercpp", .transcription):
            return ["tiny", "base", "small", "medium"]
        case ("openai_whisper", .transcription):
            return ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"]
        case ("groq_whisper", .transcription):
            return ["whisper-large-v3", "whisper-large-v3-turbo"]
        case ("openrouter_transcribe", .transcription):
            return ["google/gemini-2.5-flash", "openai/gpt-4o-mini"]
        case ("gemini_transcribe", .transcription):
            return ["gemini-3-flash-preview", "gemini-2.5-flash"]
        case ("openai_polish", .polish):
            return ["gpt-5-nano", "gpt-5-mini"]
        case ("groq_polish", .polish):
            return ["llama-3.3-70b-versatile", "mixtral-8x7b-32768"]
        case ("openrouter_polish", .polish):
            return ["openai/gpt-5-nano", "openai/gpt-5-mini", "google/gemini-2.5-flash"]
        case ("gemini_polish", .polish):
            return ["gemini-2.5-flash"]
        case (_, .transcription):
            return ["base"]
        case (_, .polish):
            return ["gpt-5-nano"]
        }
    }

    func providerConnectivityStatus(for providerID: String) -> ProviderConnectivityStatus {
        guard let backend = backend(for: providerID) else {
            return .idle
        }
        return providerConnectivityByBackend[backend.statusID] ?? .idle
    }

    func verifyProvider(for providerID: String, updateStatusMessage: Bool = true) {
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
                if updateStatusMessage {
                    self.statusMessage = "\(backend.displayName) verified"
                }
            } catch {
                self.providerConnectivityByBackend[backend.statusID] = .init(
                    state: .failed,
                    detail: "Failed: \(error.localizedDescription)"
                )
                if updateStatusMessage {
                    self.statusMessage = "\(backend.displayName) verification failed"
                }
            }
        }
    }

    func refreshModels(for providerID: String) {
        verifyProvider(for: providerID)
    }

    private func prefetchProviderCatalogsOnLaunch() {
        let verificationPlan: [(KeychainEntry, String)] = [
            (.openAI, "openai_whisper"),
            (.groq, "groq_whisper"),
            (.openRouter, "openrouter_transcribe"),
            (.gemini, "gemini_transcribe")
        ]

        for (entry, providerID) in verificationPlan {
            if apiKeyResolver.resolve(entry).value != nil {
                verifyProvider(for: providerID, updateStatusMessage: false)
            }
        }
    }

    private func normalizeReservedHotkeyConflicts() {
        let rulesHotkey = Self.openRulesTabHotkey.normalizedForCarbonHotkey()
        let copyRawHotkey = settings.copyRawHotkey.normalizedForCarbonHotkey()
        guard copyRawHotkey == rulesHotkey else {
            return
        }

        settingsStore.update { settings in
            settings.copyRawHotkey = .copyRawDefault
        }
    }

    private func registerHotkeys() {
        do {
            try validateUniqueHotkeys()

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

            try hotkeyManager.register(action: .copyRaw, setting: settings.copyRawHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.copyRawTranscript()
                }
            }

            try hotkeyManager.register(action: .pasteLatest, setting: settings.pasteHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.pasteLatestPolishedViaHotkey()
                }
            }

            try hotkeyManager.register(action: .togglePopover, setting: settings.togglePopoverHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.togglePopoverWindow()
                }
            }

            try hotkeyManager.register(action: .openSettings, setting: settings.openSettingsHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openSettingsWindow()
                }
            }

            try hotkeyManager.register(action: .showLiveTab, setting: Self.showLiveTabHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.showLiveTabFromHotkey()
                }
            }

            try hotkeyManager.register(action: .showHistoryTab, setting: Self.showHistoryTabHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.showHistoryTabFromHotkey()
                }
            }

            try hotkeyManager.register(action: .showStatsTab, setting: Self.showStatsTabHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.showStatsTabFromHotkey()
                }
            }

            try hotkeyManager.register(action: .openRulesTab, setting: Self.openRulesTabHotkey) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.openRulesFromHotkey()
                }
            }

            hotkeyError = nil
        } catch {
            hotkeyError = error.localizedDescription
            statusMessage = "Hotkey registration failed. Change hotkey in Settings."
        }
    }

    private func validateUniqueHotkeys() throws {
        let entries: [(name: String, setting: HotkeySetting)] = [
            ("Start/Stop", settings.startStopHotkey),
            ("Copy latest", settings.copyHotkey),
            ("Copy raw", settings.copyRawHotkey),
            ("Paste latest", settings.pasteHotkey),
            ("Toggle popover", settings.togglePopoverHotkey),
            ("Open settings", settings.openSettingsHotkey),
            ("Show Live tab", Self.showLiveTabHotkey),
            ("Show History tab", Self.showHistoryTabHotkey),
            ("Show Stats tab", Self.showStatsTabHotkey),
            ("Open Rules tab", Self.openRulesTabHotkey)
        ]

        var seen: [HotkeySetting: String] = [:]
        for entry in entries {
            let normalized = entry.setting.normalizedForCarbonHotkey()
            if let existing = seen[normalized] {
                throw HotkeyError.registrationFailed(
                    "\(entry.name) hotkey cannot match \(existing). Choose a different shortcut."
                )
            }
            seen[normalized] = entry.name
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

        switch resolution.source {
        case .keychain:
            return "\(entry.providerDisplayName): using saved Keychain key."
        case .missing:
            return "\(entry.providerDisplayName): no saved API key."
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

    private func openSystemSettings(path: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(path)") else {
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

    private func runTranscriptionWithRetry(
        audioFileURL: URL,
        settings: AppSettings
    ) async throws -> TranscriptResult {
        try await ProviderRetryPolicy.run {
            try await self.transcriptionPipeline.run(audioFileURL: audioFileURL, settings: settings)
        }
    }

    private func runPolishWithRetry(
        rawText: String,
        rulesMarkdown: String,
        settings: AppSettings
    ) async throws -> PolishResult {
        try await ProviderRetryPolicy.run {
            try await self.polishPipeline.run(
                rawText: rawText,
                rulesMarkdown: rulesMarkdown,
                settings: settings
            )
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

    private func completeWithoutUsableAudio(
        session: inout SessionContext,
        reason: String
    ) throws {
        rawTranscript = ""
        polishedTranscript = ""
        rawTranscriptProviderID = ""
        rawTranscriptModel = ""
        polishedTranscriptProviderID = ""
        polishedTranscriptModel = ""
        try sessionManager.writeRaw("", for: &session)
        try sessionManager.writePolished("", for: &session)
        try sessionManager.transition(&session, to: .completed, details: "No usable speech detected: \(reason)")
        sessionState = .completed
        statusMessage = "No audio captured. Speak clearly and try again."
        lastError = nil
    }

    private func completeWithoutPolish(
        rawText: String,
        session: inout SessionContext,
        completionMessage: String,
        copiedMessage: String,
        pastedMessage: String
    ) throws {
        polishedTranscript = rawText
        latestPolishedTranscript = rawText
        polishedTranscriptProviderID = "disabled"
        polishedTranscriptModel = "passthrough"
        session.metadata.polishProvider = "disabled"
        session.metadata.polishModel = "passthrough"
        try sessionManager.writePolished(rawText, for: &session)
        deliverOutput(
            rawText,
            completionMessage: completionMessage,
            copiedMessage: copiedMessage,
            pastedMessage: pastedMessage
        )
    }

    private func deliverOutput(
        _ text: String,
        completionMessage: String,
        copiedMessage: String,
        pastedMessage: String
    ) {
        let clipboardText = normalizedClipboardText(text)
        guard !clipboardText.isEmpty else {
            statusMessage = completionMessage
            return
        }

        let shouldCopy = settings.copyOnComplete || autoPasteOnComplete
        if shouldCopy {
            Clipboard.copy(text: clipboardText)
        }

        guard autoPasteOnComplete else {
            statusMessage = settings.copyOnComplete ? copiedMessage : completionMessage
            return
        }

        guard AccessibilityInputInjector.isTrusted(promptIfNeeded: false) else {
            statusMessage = "Auto-paste requires Accessibility permission. Transcript copied."
            return
        }

        if AccessibilityInputInjector.triggerPasteShortcut() {
            statusMessage = pastedMessage
        } else {
            statusMessage = settings.copyOnComplete ? copiedMessage : completionMessage
        }
    }

    private func recordTranscriptionStats(
        session: SessionContext,
        transcript: TranscriptResult,
        rawText: String,
        processingDurationMs: Int? = nil
    ) {
        let rawWordCount = wordCount(in: rawText)
        let recordingDurationMs = sessionRecordingDurationMs(session)
        let audioSeconds = Double(recordingDurationMs ?? 0) / 1_000.0

        let wordsPerMinute: Double?
        if let durationMs = recordingDurationMs, durationMs > 0 {
            wordsPerMinute = Double(rawWordCount) / (Double(durationMs) / 60_000.0)
        } else {
            wordsPerMinute = nil
        }

        let event = StatsEvent(
            id: UUID(),
            sessionId: session.id,
            timestamp: Date(),
            stage: .transcription,
            providerId: transcript.providerId,
            model: transcript.model,
            inputUnits: audioSeconds,
            outputUnits: Double(rawWordCount),
            inputUnit: .audioSeconds,
            outputUnit: .words,
            inputTokens: transcript.inputTokens,
            outputTokens: transcript.outputTokens,
            recordingDurationMs: recordingDurationMs,
            wordsPerMinute: wordsPerMinute,
            wordDelta: nil,
            wordDeltaPercent: nil,
            processingDurationMs: processingDurationMs
        )
        appendStatsEvent(event)
    }

    private func recordPolishStats(
        session: SessionContext,
        polish: PolishResult,
        rawText: String,
        polishedText: String,
        processingDurationMs: Int? = nil
    ) {
        let rawWordCount = wordCount(in: rawText)
        let polishedWordCount = wordCount(in: polishedText)
        let deltaWords = polishedWordCount - rawWordCount
        let deltaPercent: Double?
        if rawWordCount > 0 {
            deltaPercent = (Double(deltaWords) / Double(rawWordCount)) * 100.0
        } else {
            deltaPercent = nil
        }

        let event = StatsEvent(
            id: UUID(),
            sessionId: session.id,
            timestamp: Date(),
            stage: .polish,
            providerId: polish.providerId,
            model: polish.model,
            inputUnits: Double(rawWordCount),
            outputUnits: Double(polishedWordCount),
            inputUnit: .words,
            outputUnit: .words,
            inputTokens: polish.inputTokens,
            outputTokens: polish.outputTokens,
            recordingDurationMs: nil,
            wordsPerMinute: nil,
            wordDelta: deltaWords,
            wordDeltaPercent: deltaPercent,
            processingDurationMs: processingDurationMs
        )
        appendStatsEvent(event)
    }

    private func appendStatsEvent(_ event: StatsEvent) {
        do {
            try statsStore.append(event)
            refreshStatsSummary()
        } catch {
            // Stats persistence is best-effort and should not block session completion.
        }
    }

    private func sessionRecordingDurationMs(_ session: SessionContext) -> Int? {
        if let durationMs = session.metadata.durationMs, durationMs > 0 {
            return durationMs
        }
        guard let stoppedAt = session.metadata.stoppedAt else {
            return nil
        }
        let durationMs = Int(stoppedAt.timeIntervalSince(session.metadata.createdAt) * 1_000)
        return durationMs > 0 ? durationMs : nil
    }

    private func wordCount(in text: String) -> Int {
        text
            .split { character in
                character.isWhitespace || character.isNewline
            }
            .count
    }

    private func transcribeElapsedMs() -> Int? {
        guard let started = transcribeStartedAt else { return nil }
        return max(0, Int(Date().timeIntervalSince(started) * 1000))
    }

    private func polishElapsedMs() -> Int? {
        guard let started = polishStartedAt else { return nil }
        return max(0, Int(Date().timeIntervalSince(started) * 1000))
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
