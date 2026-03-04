import Foundation

enum RetryTranscriptionFailureStateReset {
    @MainActor
    static func apply(
        didWriteFreshRawTranscript: Bool,
        polishEnabled: Bool,
        session: inout SessionContext,
        sessionManager: SessionManager,
        polishedTranscript: inout String,
        polishedTranscriptProviderID: inout String,
        polishedTranscriptModel: inout String,
        latestPolishedTranscript: inout String
    ) {
        guard didWriteFreshRawTranscript, polishEnabled else {
            return
        }

        polishedTranscript = ""
        polishedTranscriptProviderID = ""
        polishedTranscriptModel = ""
        try? sessionManager.writePolished("", for: &session)
        latestPolishedTranscript = sessionManager.loadLatestPolishedTranscript() ?? ""
    }
}
