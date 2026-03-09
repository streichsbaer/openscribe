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
    var permissionAuthorized: Bool
    var hasSuccessfulRecording: Bool
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

    private static func recommendedItems(
        context: SetupAssistantChecklistContext
    ) -> [SetupAssistantChecklistItem] {
        [
            .init(
                id: "recommended.microphone",
                title: "Microphone permission granted",
                detail: context.permissionAuthorized
                    ? "OpenScribe can access your microphone."
                    : "Grant microphone access before your first test recording.",
                isComplete: context.permissionAuthorized
            ),
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
                id: "recommended.transcribe",
                title: "Groq Whisper is selected",
                detail: context.transcriptionProviderID == recommendedTranscriptionProviderID &&
                    context.transcriptionModel == recommendedTranscriptionModel &&
                    context.languageMode == "auto"
                    ? "Transcription uses whisper-large-v3-turbo with language auto."
                    : "Use Groq Whisper with whisper-large-v3-turbo and language auto.",
                isComplete: context.transcriptionProviderID == recommendedTranscriptionProviderID &&
                    context.transcriptionModel == recommendedTranscriptionModel &&
                    context.languageMode == "auto"
            ),
            .init(
                id: "recommended.polish",
                title: "Groq polish is enabled",
                detail: context.polishEnabled &&
                    context.polishProviderID == recommendedPolishProviderID &&
                    context.polishModel == recommendedPolishModel
                    ? "Polish runs on openai/gpt-oss-120b."
                    : "Enable polish on Groq with openai/gpt-oss-120b.",
                isComplete: context.polishEnabled &&
                    context.polishProviderID == recommendedPolishProviderID &&
                    context.polishModel == recommendedPolishModel
            ),
            .init(
                id: "recommended.recording",
                title: "First recording completed",
                detail: context.hasSuccessfulRecording
                    ? "Your first transcript succeeded."
                    : "Make one short test recording to confirm the full setup works.",
                isComplete: context.hasSuccessfulRecording
            )
        ]
    }

    private static func localItems(
        context: SetupAssistantChecklistContext
    ) -> [SetupAssistantChecklistItem] {
        [
            .init(
                id: "local.microphone",
                title: "Microphone permission granted",
                detail: context.permissionAuthorized
                    ? "OpenScribe can access your microphone."
                    : "Grant microphone access before your first test recording.",
                isComplete: context.permissionAuthorized
            ),
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
                id: "local.recording",
                title: "First recording completed",
                detail: context.hasSuccessfulRecording
                    ? "Your first local transcript succeeded."
                    : "Make one short test recording to confirm local transcription works.",
                isComplete: context.hasSuccessfulRecording
            )
        ]
    }
}
