import AppKit
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

struct RulesDiffResult {
    let unifiedDiff: String
    let summary: String
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
    var feedbackLogPath: String
}

struct SessionPaths {
    let folderURL: URL
    let audioTempURL: URL
    let audioURL: URL
    let metadataURL: URL
    let rawURL: URL
    let polishedURL: URL
    let feedbackLogURL: URL
}

struct SessionContext {
    let id: UUID
    let paths: SessionPaths
    var metadata: SessionMetadata
}

struct HotkeySetting: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    // Space key and ANSI V key are stable virtual keycodes on macOS.
    private static let spaceKeyCode: UInt32 = 49
    private static let vKeyCode: UInt32 = 9
    static let legacyNSEventFunctionMask: UInt32 = UInt32(NSEvent.ModifierFlags.function.rawValue)
    static let carbonFunctionMask: UInt32 = UInt32(kEventKeyModifierFnMask)

    static let startStopDefault = HotkeySetting(
        keyCode: spaceKeyCode,
        modifiers: carbonFunctionMask
    )

    static let copyDefault = HotkeySetting(
        keyCode: vKeyCode,
        modifiers: UInt32(controlKey | optionKey)
    )

    func normalizedForCarbonHotkey() -> HotkeySetting {
        var normalized = self
        if (normalized.modifiers & Self.legacyNSEventFunctionMask) != 0 {
            normalized.modifiers &= ~Self.legacyNSEventFunctionMask
            normalized.modifiers |= Self.carbonFunctionMask
        }
        return normalized
    }
}

struct AppSettings: Codable, Equatable {
    var transcriptionProviderID: String
    var transcriptionModel: String
    var polishProviderID: String
    var polishModel: String
    var languageMode: String
    var copyOnComplete: Bool
    var startStopHotkey: HotkeySetting
    var copyHotkey: HotkeySetting

    static let `default` = AppSettings(
        transcriptionProviderID: "whispercpp",
        transcriptionModel: "base",
        polishProviderID: "openai_polish",
        polishModel: "gpt-5-mini",
        languageMode: "auto",
        copyOnComplete: true,
        startStopHotkey: .startStopDefault,
        copyHotkey: .copyDefault
    )
}

struct ModelAsset: Codable, Equatable {
    let id: String
    let displayName: String
    let downloadURL: URL
    let expectedSizeBytes: Int64
    let sha256: String?
}

struct FeedbackEvent: Codable {
    let timestamp: Date
    let rawText: String
    let polishedText: String
    let feedback: String
    let diffSummary: String
    let approved: Bool
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
    static let appSupportName = "SmartTranscript"
}

enum KeychainEntry: String {
    case openAI = "openai_api_key"
    case groq = "groq_api_key"

    var environmentVariableName: String {
        switch self {
        case .openAI:
            return "OPENAI_API_KEY"
        case .groq:
            return "GROQ_API_KEY"
        }
    }

    var providerDisplayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .groq:
            return "Groq"
        }
    }
}
