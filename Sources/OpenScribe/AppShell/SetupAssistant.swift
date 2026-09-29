import Foundation

enum SetupAssistantTrack: String, CaseIterable, Identifiable {
    case local
    case groq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local:
            return "Local only"
        case .groq:
            return "Groq cloud"
        }
    }

    var summary: String {
        switch self {
        case .local:
            return "Keep transcription on your Mac with a local model."
        case .groq:
            return "Fast Groq transcription and polish with one API key."
        }
    }

    /// Apple silicon runs Parakeet Ultra fast enough to be the first choice. Intel Macs run local
    /// models on the CPU only, so the Groq path is the faster start there.
    static func recommended(onAppleSilicon: Bool = runsOnAppleSilicon) -> SetupAssistantTrack {
        onAppleSilicon ? .local : .groq
    }

    static func ordered(recommended: SetupAssistantTrack) -> [SetupAssistantTrack] {
        [recommended] + allCases.filter { $0 != recommended }
    }

    static func recommendationNote(onAppleSilicon: Bool = runsOnAppleSilicon) -> String {
        onAppleSilicon
            ? "Recommended for this Mac: Local only. Apple silicon runs Parakeet Ultra quickly on this Mac, with no API key and no audio leaving it."
            : "Recommended for this Mac: Groq cloud. Intel Macs run local models on the CPU, which is much slower. Local only still works if you prefer it."
    }

    static var runsOnAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }
}

struct SetupAssistantLocalModelOption: Identifiable, Equatable {
    let id: String
    let providerID: String
    let title: String
    let detail: String
}

struct SetupAssistantChecklistContext: Equatable {
    var accessibilityPermissionGranted: Bool
    var autoPasteEnabled: Bool
    var hasSuccessfulRecording: Bool
    var latestOutputAvailable: Bool
    var testFieldContainsOutput: Bool
    var groqKeySaved: Bool
    var groqVerified: Bool
    var transcriptionProviderID: String
    var transcriptionModel: String
    var polishEnabled: Bool
    var polishProviderID: String
    var polishModel: String
    var languageMode: String
    var selectedLocalModel: String
    var localModelInstalled: Bool
}

struct SetupAssistantChecklistItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let isComplete: Bool
}

enum SetupAssistantChecklist {
    static let groqTranscriptionProviderID = "groq_whisper"
    static let groqTranscriptionModel = "whisper-large-v3-turbo"
    static let groqPolishProviderID = "groq_polish"
    static let groqPolishModel = "openai/gpt-oss-120b"
    static let defaultLocalModelID = ModelDownloadManager.parakeetUltraModelID

    static let localModelOptions: [SetupAssistantLocalModelOption] = [
        .init(
            id: ModelDownloadManager.parakeetUltraModelID,
            providerID: "parakeet",
            title: "Parakeet Ultra",
            detail: "Recommended. Most accurate and fastest local option, 25 European languages. 600 MB download."
        ),
        .init(
            id: "large-v3-turbo",
            providerID: "whispercpp",
            title: "Whisper large-v3-turbo",
            detail: "Best Whisper accuracy and 99 languages, the same model Groq runs. 1.6 GB download."
        ),
        .init(id: "medium", providerID: "whispercpp", title: "Whisper medium", detail: "Larger download. Slower and less accurate than large-v3-turbo."),
        .init(id: "small", providerID: "whispercpp", title: "Whisper small", detail: "Balanced Whisper size and accuracy."),
        .init(id: "base", providerID: "whispercpp", title: "Whisper base", detail: "Small Whisper download, lower accuracy."),
        .init(id: "tiny", providerID: "whispercpp", title: "Whisper tiny", detail: "Smallest Whisper download, lowest accuracy.")
    ]

    static func localOption(for modelID: String) -> SetupAssistantLocalModelOption {
        localModelOptions.first { $0.id == modelID } ?? localModelOptions[0]
    }

    static func items(
        for track: SetupAssistantTrack,
        context: SetupAssistantChecklistContext
    ) -> [SetupAssistantChecklistItem] {
        switch track {
        case .local:
            return localItems(context: context)
        case .groq:
            return groqItems(context: context)
        }
    }

    static func isComplete(
        for track: SetupAssistantTrack,
        context: SetupAssistantChecklistContext
    ) -> Bool {
        items(for: track, context: context).allSatisfy(\.isComplete)
    }

    static func shouldAutoPresent(hasSessionHistory: Bool, doNotShowAgain: Bool) -> Bool {
        !hasSessionHistory && !doNotShowAgain
    }

    static func sessionMatchesTrack(
        sttProvider: String,
        sttModel: String,
        polishProvider: String,
        polishModel: String,
        track: SetupAssistantTrack,
        selectedLocalModel: String
    ) -> Bool {
        switch track {
        case .local:
            return sttProvider == localOption(for: selectedLocalModel).providerID &&
                sttModel == selectedLocalModel &&
                polishProvider == "disabled" &&
                polishModel == "passthrough"
        case .groq:
            return sttProvider == groqTranscriptionProviderID &&
                sttModel == groqTranscriptionModel &&
                polishProvider == groqPolishProviderID &&
                polishModel == groqPolishModel
        }
    }

    static func groqSetupMatches(_ context: SetupAssistantChecklistContext) -> Bool {
        context.transcriptionProviderID == groqTranscriptionProviderID &&
            context.transcriptionModel == groqTranscriptionModel &&
            context.languageMode == "auto" &&
            context.polishEnabled &&
            context.polishProviderID == groqPolishProviderID &&
            context.polishModel == groqPolishModel
    }

    private static func groqItems(
        context: SetupAssistantChecklistContext
    ) -> [SetupAssistantChecklistItem] {
        let setupMatches = groqSetupMatches(context)

        return [
            .init(
                id: "groq.keySaved",
                title: "Groq API key saved",
                detail: context.groqKeySaved
                    ? "Your Groq key is stored in the macOS Keychain."
                    : "Save a Groq API key to unlock the Groq cloud setup.",
                isComplete: context.groqKeySaved
            ),
            .init(
                id: "groq.keyVerified",
                title: "Groq connection verified",
                detail: context.groqVerified
                    ? "OpenScribe confirmed your Groq key and refreshed the provider catalog."
                    : "Verify Groq after saving the key so the model catalog is ready.",
                isComplete: context.groqVerified
            ),
            .init(
                id: "groq.setup",
                title: "Groq setup configured",
                detail: setupMatches
                    ? "Groq Whisper and Groq polish use the suggested models."
                    : "Apply the Groq transcription and polish setup.",
                isComplete: setupMatches
            ),
            .init(
                id: "groq.accessibility",
                title: "Accessibility permission granted",
                detail: context.accessibilityPermissionGranted
                    ? "OpenScribe can paste into your focused app."
                    : "Grant Accessibility permission to support auto-paste.",
                isComplete: context.accessibilityPermissionGranted
            ),
            .init(
                id: "groq.autopaste",
                title: "Auto-paste enabled",
                detail: context.autoPasteEnabled
                    ? "Completed transcripts will paste into the focused app."
                    : "Turn on auto-paste if you want a one-step dictation workflow.",
                isComplete: context.autoPasteEnabled
            ),
            .init(
                id: "groq.recording",
                title: "Complete a test recording",
                detail: "Start and stop one short recording with the current setup.",
                isComplete: context.hasSuccessfulRecording
            ),
            .init(
                id: "groq.pasteTest",
                title: "Transcript appeared in the test field",
                detail: "Confirm the latest transcript appears in the test field.",
                isComplete: context.testFieldContainsOutput
            )
        ]
    }

    static func localSetupMatches(_ context: SetupAssistantChecklistContext) -> Bool {
        context.transcriptionProviderID == localOption(for: context.selectedLocalModel).providerID &&
            context.transcriptionModel == context.selectedLocalModel &&
            context.languageMode == "auto" &&
            !context.polishEnabled
    }

    private static func localItems(
        context: SetupAssistantChecklistContext
    ) -> [SetupAssistantChecklistItem] {
        [
            .init(
                id: "local.setup",
                title: "Local transcription is selected",
                detail: localSetupMatches(context)
                    ? "\(localOption(for: context.selectedLocalModel).title) is active with polish off."
                    : "Use \(localOption(for: context.selectedLocalModel).title), keep language auto, and keep polish off for a local-only path.",
                isComplete: localSetupMatches(context)
            ),
            .init(
                id: "local.model",
                title: "\(localOption(for: context.selectedLocalModel).title) downloaded",
                detail: context.localModelInstalled
                    ? "The selected local model is installed on this Mac."
                    : "Download the selected local model before the test recording.",
                isComplete: context.localModelInstalled
            ),
            .init(
                id: "local.accessibility",
                title: "Accessibility permission granted",
                detail: context.accessibilityPermissionGranted
                    ? "OpenScribe can paste into your focused app."
                    : "Grant Accessibility permission to support auto-paste.",
                isComplete: context.accessibilityPermissionGranted
            ),
            .init(
                id: "local.autopaste",
                title: "Auto-paste enabled",
                detail: context.autoPasteEnabled
                    ? "Completed transcripts will paste into the focused app."
                    : "Turn on auto-paste if you want the local setup to paste automatically.",
                isComplete: context.autoPasteEnabled
            ),
            .init(
                id: "local.recording",
                title: "Complete a test recording",
                detail: "Start and stop one short recording with the current setup.",
                isComplete: context.hasSuccessfulRecording
            ),
            .init(
                id: "local.pasteTest",
                title: "Transcript appeared in the test field",
                detail: "Confirm the latest transcript appears in the test field.",
                isComplete: context.testFieldContainsOutput
            )
        ]
    }
}
