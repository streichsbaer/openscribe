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

    @Published var feedbackText: String = ""
    @Published var pendingProposal: FeedbackProposal?

    @Published var hotkeyError: String?

    @Published var rulesDraft: String

    @Published var openAIKeyInput: String = ""
    @Published var groqKeyInput: String = ""
    @Published var latestPolishedTranscript: String = ""

    var openSettingsWindowHandler: (() -> Void)?

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
    private let feedbackEngine: FeedbackEngine
    private var hasPromptedForAccessibilityPermission = false

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
        self.feedbackEngine = FeedbackEngine(polishPipeline: self.polishPipeline, rulesStore: self.rulesStore)

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

    func openSettingsWindow() {
        openSettingsWindowHandler?()
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
            pendingProposal = nil
            feedbackText = ""
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
            try sessionManager.transition(&session, to: .transcribing, details: "Running transcription")

            let transcript = try await transcriptionPipeline.run(audioFileURL: session.paths.audioURL, settings: settings)
            rawTranscript = transcript.text
            try sessionManager.writeRaw(transcript.text, for: &session)

            do {
                sessionState = .polishing
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
                    Clipboard.copy(text: polished.markdown)
                    statusMessage = "Polished transcript copied"
                } else {
                    statusMessage = "Transcription complete"
                }
            } catch {
                polishedTranscript = ""
                statusMessage = "Raw transcript ready. Polish failed or needs API key."
                lastError = error.localizedDescription
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
                self.sessionState = .polishing
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
                    Clipboard.copy(text: polished.markdown)
                }
                self.statusMessage = "Polish retry complete"
            } catch {
                self.lastError = error.localizedDescription
                self.statusMessage = "Polish retry failed"
                self.currentSession = session
            }
        }
    }

    func proposeRulesUpdateFromFeedback() {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !self.rawTranscript.isEmpty else {
                return
            }

            do {
                let proposal = try await self.feedbackEngine.propose(
                    rawText: self.rawTranscript,
                    polishedText: self.polishedTranscript,
                    feedback: self.feedbackText,
                    settings: self.settings
                )
                self.pendingProposal = proposal
                self.statusMessage = "Diff proposed. Review and approve."
            } catch {
                self.lastError = error.localizedDescription
                self.statusMessage = "Failed to generate rules diff"
            }
        }
    }

    func approveRulesProposal() {
        Task { @MainActor [weak self] in
            guard let self,
                  let proposal = self.pendingProposal else {
                return
            }

            do {
                try self.feedbackEngine.applyApproved(proposal: proposal)
                self.rulesStore.reload()
                self.rulesDraft = self.rulesStore.currentRules
                self.pendingProposal = nil

                if let session = self.currentSession {
                    let feedbackEvent = FeedbackEvent(
                        timestamp: Date(),
                        rawText: self.rawTranscript,
                        polishedText: self.polishedTranscript,
                        feedback: self.feedbackText,
                        diffSummary: proposal.diffResult.summary,
                        approved: true
                    )
                    self.sessionManager.appendFeedback(feedbackEvent, for: session)
                }

                self.statusMessage = "Rules updated. Re-polishing current session."
                self.retryPolish()
            } catch {
                self.lastError = error.localizedDescription
                self.statusMessage = "Failed to apply rules update"
            }
        }
    }

    func rejectRulesProposal() {
        guard let proposal = pendingProposal else {
            return
        }

        feedbackEngine.reject(proposal)
        pendingProposal = nil
        statusMessage = "Rules update rejected"
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
        !polishedTranscript.isEmpty ? polishedTranscript : latestPolishedTranscript
    }

    private func pasteLatestPolishedViaHotkey() {
        let candidate = latestPolishedCandidate()
        guard !candidate.isEmpty else {
            statusMessage = "No polished transcript available yet"
            return
        }

        Clipboard.copy(text: candidate)

        if !AccessibilityInputInjector.isTrusted(promptIfNeeded: false) {
            if !hasPromptedForAccessibilityPermission {
                _ = AccessibilityInputInjector.isTrusted(promptIfNeeded: true)
                hasPromptedForAccessibilityPermission = true
            }
            statusMessage = "Latest polished transcript copied. Enable Accessibility permission for SmartTranscript to auto-paste."
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            if AccessibilityInputInjector.triggerPasteShortcut() {
                self.statusMessage = "Latest polished transcript pasted"
            } else {
                self.statusMessage = "Latest polished transcript copied"
            }
        }
    }
}
