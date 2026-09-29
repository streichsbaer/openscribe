import Foundation

struct SessionHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let folderURL: URL
    let createdAt: Date
    let state: SessionState
    let sttProvider: String
    let sttModel: String
    let polishProvider: String
    let polishModel: String
    let previewText: String
    let durationMs: Int?
    let hadNoSpeech: Bool
    let lastError: String?

    var polishRan: Bool {
        polishProvider != "disabled" && !polishProvider.isEmpty && state == .completed && !hadNoSpeech
    }
}

struct SessionHistoryPage: Equatable {
    let entries: [SessionHistoryEntry]
    let hasMore: Bool
}
