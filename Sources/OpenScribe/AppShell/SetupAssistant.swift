import Foundation

enum SetupAssistantTrack: String, CaseIterable, Identifiable {
    case recommended
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended:
            return "Best setup"
        case .local:
            return "Local only"
        }
    }

    var summary: String {
        switch self {
        case .recommended:
            return "Fast Groq transcription and polish with one API key."
        case .local:
            return "Keep transcription on your Mac with a local whisper.cpp model."
        }
    }
}

struct SetupAssistantLocalModelOption: Identifiable, Equatable {
    let id: String
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
    static let recommendedTranscriptionProviderID = "groq_whisper"
    static let recommendedTranscriptionModel = "whisper-large-v3-turbo"
    static let recommendedPolishProviderID = "groq_polish"
    static let recommendedPolishModel = "openai/gpt-oss-120b"
    static let defaultLocalModelID = "small"

    static let localModelOptions: [SetupAssistantLocalModelOption] = [
        .init(id: "tiny", title: "tiny", detail: "Smallest local download. Fastest, with the lowest accuracy."),
        .init(id: "base", title: "base", detail: "Fastest local start. Smaller download, lower accuracy."),
        .init(id: "small", title: "small", detail: "Recommended local balance. Better accuracy without the largest download."),
        .init(id: "medium", title: "medium", detail: "Best local accuracy here. Larger download and slower processing.")
    ]

    static func items(
        for track: SetupAssistantTrack,
        context: SetupAssistantChecklistContext
    ) -> [SetupAssistantChecklistItem] {
        switch track {
        case .recommended:
            return recommendedItems(context: context)
        case .local:
            return localItems(context: context)
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
        case .recommended:
            return sttProvider == recommendedTranscriptionProviderID &&
                sttModel == recommendedTranscriptionModel &&
                polishProvider == recommendedPolishProviderID &&
                polishModel == recommendedPolishModel
        case .local:
            return sttProvider == "whispercpp" &&
                sttModel == selectedLocalModel &&
                polishProvider == "disabled" &&
                polishModel == "passthrough"
        }
    }

    private static func recommendedItems(
        context: SetupAssistantChecklistContext
    ) -> [SetupAssistantChecklistItem] {
        let recommendedSetupMatches =
            context.transcriptionProviderID == recommendedTranscriptionProviderID &&
            context.transcriptionModel == recommendedTranscriptionModel &&
            context.languageMode == "auto" &&
            context.polishEnabled &&
            context.polishProviderID == recommendedPolishProviderID &&
            context.polishModel == recommendedPolishModel

        return [
            .init(
                id: "recommended.keySaved",
                title: "Groq API key saved",
                detail: context.groqKeySaved
                    ? "Your Groq key is stored in the macOS Keychain."
                    : "Save a Groq API key to unlock the recommended hosted setup.",
                isComplete: context.groqKeySaved
            ),
            .init(
                id: "recommended.keyVerified",
                title: "Groq connection verified",
                detail: context.groqVerified
                    ? "OpenScribe confirmed your Groq key and refreshed the provider catalog."
                    : "Verify Groq after saving the key so the model catalog is ready.",
                isComplete: context.groqVerified
            ),
            .init(
                id: "recommended.setup",
                title: "Recommended setup configured",
                detail: recommendedSetupMatches
                    ? "Groq Whisper and Groq polish use the recommended models."
                    : "Apply the recommended Groq transcription and polish setup.",
                isComplete: recommendedSetupMatches
            ),
            .init(
                id: "recommended.accessibility",
                title: "Accessibility permission granted",
                detail: context.accessibilityPermissionGranted
                    ? "OpenScribe can paste into your focused app."
                    : "Grant Accessibility permission to support auto-paste.",
                isComplete: context.accessibilityPermissionGranted
            ),
            .init(
                id: "recommended.autopaste",
                title: "Auto-paste enabled",
                detail: context.autoPasteEnabled
                    ? "Completed transcripts will paste into the focused app."
                    : "Turn on auto-paste if you want a one-step dictation workflow.",
                isComplete: context.autoPasteEnabled
            ),
            .init(
                id: "recommended.recording",
                title: "Complete a test recording",
                detail: "Start and stop one short recording with the current setup.",
                isComplete: context.hasSuccessfulRecording
            ),
            .init(
                id: "recommended.pasteTest",
                title: "Transcript appeared in the test field",
                detail: "Confirm the latest transcript appears in the test field.",
                isComplete: context.testFieldContainsOutput
            )
        ]
    }

    private static func localItems(
        context: SetupAssistantChecklistContext
    ) -> [SetupAssistantChecklistItem] {
        [
            .init(
                id: "local.setup",
                title: "Local transcription is selected",
                detail: context.transcriptionProviderID == "whispercpp" &&
                    context.transcriptionModel == context.selectedLocalModel &&
                    context.languageMode == "auto" &&
                    !context.polishEnabled
                    ? "Local whisper.cpp is active with polish off."
                    : "Use local whisper.cpp, keep language auto, and keep polish off for a local-only path.",
                isComplete: context.transcriptionProviderID == "whispercpp" &&
                    context.transcriptionModel == context.selectedLocalModel &&
                    context.languageMode == "auto" &&
                    !context.polishEnabled
            ),
            .init(
                id: "local.model",
                title: "\(context.selectedLocalModel) model downloaded",
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
