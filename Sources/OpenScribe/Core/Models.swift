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

struct TranscriptResult: Codable, Sendable {
    let text: String
    let providerId: String
    let model: String
    let latencyMs: Int
    let inputTokens: Int?
    let outputTokens: Int?
}

struct PolishResult: Codable, Sendable {
    let markdown: String
    let providerId: String
    let model: String
    let latencyMs: Int
    let inputTokens: Int?
    let outputTokens: Int?
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
    var audioActivity: AudioActivityAssessment?
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

    // Space, ANSI P, ANSI R, ANSI T, and ANSI V are stable virtual keycodes on macOS.
    private static let spaceKeyCode: UInt32 = 49
    private static let pKeyCode: UInt32 = 35
    private static let rKeyCode: UInt32 = 15
    private static let tKeyCode: UInt32 = 17
    private static let vKeyCode: UInt32 = 9
    private static let oKeyCode: UInt32 = 31
    private static let commaKeyCode: UInt32 = 43
    static let carbonFunctionMask: UInt32 = UInt32(kEventKeyModifierFnMask)

    /// Modifiers for the Control-Option shortcut family. The side-by-side build adds Command
    /// so it can run next to the installed app without hotkey collisions.
    static let shortcutModifiers: UInt32 = UInt32(controlKey | optionKey) | (AppVariant.isSideBySide ? UInt32(cmdKey) : 0)

    static let startStopDefault = HotkeySetting(
        keyCode: spaceKeyCode,
        modifiers: carbonFunctionMask | (AppVariant.isSideBySide ? UInt32(shiftKey) : 0)
    )

    static let copyDefault = HotkeySetting(
        keyCode: pKeyCode,
        modifiers: shortcutModifiers
    )

    static let copyRawDefault = HotkeySetting(
        keyCode: tKeyCode,
        modifiers: shortcutModifiers
    )

    static let pasteDefault = HotkeySetting(
        keyCode: vKeyCode,
        modifiers: shortcutModifiers
    )

    static let togglePopoverDefault = HotkeySetting(
        keyCode: oKeyCode,
        modifiers: shortcutModifiers
    )

    static let openSettingsDefault = HotkeySetting(
        keyCode: commaKeyCode,
        modifiers: shortcutModifiers
    )

    func normalizedForCarbonHotkey() -> HotkeySetting {
        self
    }
}

struct PinnedMicrophone: Codable, Equatable {
    var id: String
    var name: String
}

struct AppSettings: Codable, Equatable {
    var transcriptionProviderID: String
    var transcriptionModel: String
    var parakeetUsesNeuralEngine: Bool?
    var transcriptionCustomInstructionEnabled: Bool?
    var transcriptionInstruction: String?
    var polishEnabled: Bool
    var polishProviderID: String
    var polishModel: String
    var polishCustomInstructionEnabled: Bool?
    var polishInstruction: String?
    var appearanceMode: String
    var showActiveSessionIndicator: Bool?
    var languageMode: String
    var copyOnComplete: Bool
    var startStopHotkey: HotkeySetting
    var copyHotkey: HotkeySetting
    var copyRawHotkey: HotkeySetting
    var pasteHotkey: HotkeySetting
    var togglePopoverHotkey: HotkeySetting
    var openSettingsHotkey: HotkeySetting
    var pinnedMicrophone: PinnedMicrophone?

    static let `default` = AppSettings(
        transcriptionProviderID: "parakeet",
        transcriptionModel: ModelDownloadManager.parakeetUltraModelID,
        parakeetUsesNeuralEngine: nil,
        transcriptionCustomInstructionEnabled: nil,
        transcriptionInstruction: nil,
        polishEnabled: false,
        polishProviderID: "openai_polish",
        polishModel: "gpt-5-nano",
        polishCustomInstructionEnabled: nil,
        polishInstruction: nil,
        appearanceMode: "system",
        showActiveSessionIndicator: true,
        languageMode: "auto",
        copyOnComplete: true,
        startStopHotkey: .startStopDefault,
        copyHotkey: .copyDefault,
        copyRawHotkey: .copyRawDefault,
        pasteHotkey: .pasteDefault,
        togglePopoverHotkey: .togglePopoverDefault,
        openSettingsHotkey: .openSettingsDefault,
        pinnedMicrophone: nil
    )

    var activeSessionIndicatorEnabled: Bool {
        showActiveSessionIndicator ?? true
    }
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

enum ModelAssetKind: String, Codable, Sendable {
    /// A single ggml file for whisper.cpp.
    case whisper
    /// A Core ML folder for the Parakeet engine.
    case parakeet

    var providerID: String {
        self == .whisper ? "whispercpp" : "parakeet"
    }
}

struct ModelAssetFile: Codable, Equatable, Sendable {
    let path: String
    let sizeBytes: Int64
    let sha256: String
}

struct ModelAsset: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: ModelAssetKind
    let displayName: String
    let detail: String
    /// Hugging Face `resolve/<revision>/` URL; every file path is relative to it.
    let repositoryURL: URL
    let files: [ModelAssetFile]

    var expectedSizeBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }

    func downloadURL(for file: ModelAssetFile) -> URL {
        repositoryURL.appendingPathComponent(file.path)
    }
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

/// `OpenScribe Dev.app` from `Scripts/build_side_by_side_app.sh` sets `OpenScribeSideBySide` in its
/// Info.plist to run next to the installed app with its own data folder and hotkeys.
enum AppVariant {
    static let isSideBySide = Bundle.main.object(forInfoDictionaryKey: "OpenScribeSideBySide") as? Bool == true
}

enum AppDirectories {
    static let appSupportName = AppVariant.isSideBySide ? "OpenScribe Dev" : "OpenScribe"
}

enum KeychainEntry: String {
    case openAI = "openai_api_key"
    case groq = "groq_api_key"
    case openRouter = "openrouter_api_key"
    case gemini = "gemini_api_key"
    case cerebras = "cerebras_api_key"

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
        case .cerebras:
            return "Cerebras"
        }
    }
}
