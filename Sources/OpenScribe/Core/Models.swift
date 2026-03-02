import Carbon
import Foundation

enum SessionState: String, Codable {
    case idle
    case recording
    case finalizingAudio
    case transcribing
    case polishing
    case completed
    case failed

    var displayLabel: String {
        switch self {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .finalizingAudio:
            return "Finalizing audio"
        case .transcribing:
            return "Transcribing"
        case .polishing:
            return "Polishing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
}

struct TranscriptResult: Codable {
    let text: String
    let providerId: String
    let model: String
    let latencyMs: Int
}

struct PolishResult: Codable {
    let markdown: String
    let providerId: String
    let model: String
    let latencyMs: Int
}

struct SessionStateTransition: Codable {
    let state: SessionState
    let timestamp: Date
    let details: String?
}

struct SessionMetadata: Codable {
    let sessionId: UUID
    var createdAt: Date
    var stoppedAt: Date?
    var durationMs: Int?
    var inputDeviceName: String?
    var sampleRate: Double
    var channels: Int
    var sttProvider: String
    var sttModel: String
    var polishProvider: String
    var polishModel: String
    var languageMode: String
    var state: SessionState
    var stateTransitions: [SessionStateTransition]
    var lastError: String?

    var audioFilePath: String
    var rawFilePath: String
    var polishedFilePath: String
}

struct SessionPaths {
    let folderURL: URL
    let audioTempURL: URL
    let audioURL: URL
    let metadataURL: URL
    let rawURL: URL
    let polishedURL: URL
}

struct SessionContext {
    let id: UUID
    let paths: SessionPaths
    var metadata: SessionMetadata
}

struct HotkeySetting: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    // Space, ANSI P, ANSI R, and ANSI V are stable virtual keycodes on macOS.
    private static let spaceKeyCode: UInt32 = 49
    private static let pKeyCode: UInt32 = 35
    private static let rKeyCode: UInt32 = 15
    private static let vKeyCode: UInt32 = 9
    private static let oKeyCode: UInt32 = 31
    private static let commaKeyCode: UInt32 = 43
    static let carbonFunctionMask: UInt32 = UInt32(kEventKeyModifierFnMask)

    static let startStopDefault = HotkeySetting(
        keyCode: spaceKeyCode,
        modifiers: carbonFunctionMask
    )

    static let copyDefault = HotkeySetting(
        keyCode: pKeyCode,
        modifiers: UInt32(controlKey | optionKey)
    )

    static let copyRawDefault = HotkeySetting(
        keyCode: rKeyCode,
        modifiers: UInt32(controlKey | optionKey)
    )

    static let pasteDefault = HotkeySetting(
        keyCode: vKeyCode,
        modifiers: UInt32(controlKey | optionKey)
    )

    static let togglePopoverDefault = HotkeySetting(
        keyCode: oKeyCode,
        modifiers: UInt32(controlKey | optionKey)
    )

    static let openSettingsDefault = HotkeySetting(
        keyCode: commaKeyCode,
        modifiers: UInt32(controlKey | optionKey)
    )

    func normalizedForCarbonHotkey() -> HotkeySetting {
        self
    }
}

struct AppSettings: Codable, Equatable {
    var transcriptionProviderID: String
    var transcriptionModel: String
    var polishEnabled: Bool
    var polishProviderID: String
    var polishModel: String
    var appearanceMode: String
    var languageMode: String
    var copyOnComplete: Bool
    var startStopHotkey: HotkeySetting
    var copyHotkey: HotkeySetting
    var copyRawHotkey: HotkeySetting
    var pasteHotkey: HotkeySetting
    var togglePopoverHotkey: HotkeySetting
    var openSettingsHotkey: HotkeySetting

    static let `default` = AppSettings(
        transcriptionProviderID: "whispercpp",
        transcriptionModel: "base",
        polishEnabled: false,
        polishProviderID: "openai_polish",
        polishModel: "gpt-5-nano",
        appearanceMode: "system",
        languageMode: "auto",
        copyOnComplete: true,
        startStopHotkey: .startStopDefault,
        copyHotkey: .copyDefault,
        copyRawHotkey: .copyRawDefault,
        pasteHotkey: .pasteDefault,
        togglePopoverHotkey: .togglePopoverDefault,
        openSettingsHotkey: .openSettingsDefault
    )
}

enum AppearanceMode: String, CaseIterable, Codable, Equatable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

struct ModelAsset: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let downloadURL: URL
    let expectedSizeBytes: Int64
    let sha256: String?
}

enum ProviderError: Error, LocalizedError {
    case missingAPIKey(String)
    case invalidResponse
    case processFailed(String)
    case missingModel(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Missing API key for \(provider)."
        case .invalidResponse:
            return "Provider returned an invalid response."
        case .processFailed(let reason):
            return "Local transcription failed: \(reason)"
        case .missingModel(let model):
            return "Model \(model) is not installed."
        case .unsupported(let message):
            return message
        }
    }
}

enum AppDirectories {
    static let appSupportName = "OpenScribe"
}

enum KeychainEntry: String {
    case openAI = "openai_api_key"
    case groq = "groq_api_key"
    case openRouter = "openrouter_api_key"
    case gemini = "gemini_api_key"

    var environmentVariableNames: [String] {
        switch self {
        case .openAI:
            return ["OPENAI_API_KEY"]
        case .groq:
            return ["GROQ_API_KEY"]
        case .openRouter:
            return ["SCRIBE_OPENROUTER_API_KEY", "OPENROUTER_API_KEY"]
        case .gemini:
            return ["GEMINI_API_KEY"]
        }
    }

    var environmentVariableName: String {
        environmentVariableNames.first ?? ""
    }

    var providerDisplayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .groq:
            return "Groq"
        case .openRouter:
            return "OpenRouter"
        case .gemini:
            return "Gemini"
        }
    }
}
