import Foundation

final class SessionManager {
    private let layout: DirectoryLayout
    private let fileManager: FileManager

    init(layout: DirectoryLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    func startSession(settings: AppSettings, inputDeviceName: String?) throws -> SessionContext {
        let id = UUID()
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dayFolder = formatter.string(from: now)

        formatter.dateFormat = "HHmmss"
        let timeStamp = formatter.string(from: now)

        let folder = layout.recordings
            .appendingPathComponent(dayFolder, isDirectory: true)
            .appendingPathComponent("\(timeStamp)-\(id.uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let paths = SessionPaths(
            folderURL: folder,
            audioTempURL: folder.appendingPathComponent("audio.capture.wav.part"),
            audioURL: folder.appendingPathComponent("audio.m4a"),
            metadataURL: folder.appendingPathComponent("session.json"),
            rawURL: folder.appendingPathComponent("raw.txt"),
            polishedURL: folder.appendingPathComponent("polished.md")
        )

        var metadata = SessionMetadata(
            sessionId: id,
            createdAt: now,
            stoppedAt: nil,
            durationMs: nil,
            inputDeviceName: inputDeviceName,
            sampleRate: 16_000,
            channels: 1,
            sttProvider: settings.transcriptionProviderID,
            sttModel: settings.transcriptionModel,
            polishProvider: settings.polishProviderID,
            polishModel: settings.polishModel,
            languageMode: settings.languageMode,
            state: .recording,
            stateTransitions: [],
            lastError: nil,
            audioFilePath: paths.audioURL.path,
            rawFilePath: paths.rawURL.path,
            polishedFilePath: paths.polishedURL.path
        )

        metadata.stateTransitions.append(SessionStateTransition(state: .recording, timestamp: now, details: "Session started"))
        let context = SessionContext(id: id, paths: paths, metadata: metadata)
        try persistMetadata(context)
        return context
    }

    func transition(_ session: inout SessionContext, to state: SessionState, details: String? = nil) throws {
        session.metadata.state = state
        session.metadata.stateTransitions.append(SessionStateTransition(state: state, timestamp: Date(), details: details))
        try persistMetadata(session)
    }

    func recordFailure(_ session: inout SessionContext, error: String) {
        session.metadata.lastError = error
        try? transition(&session, to: .failed, details: error)
    }

    func stopSession(_ session: inout SessionContext) throws {
        let now = Date()
        session.metadata.stoppedAt = now
        session.metadata.durationMs = Int(now.timeIntervalSince(session.metadata.createdAt) * 1_000)
        try persistMetadata(session)
    }

    func finalizeAudioFile(_ session: inout SessionContext) throws {
        guard fileManager.fileExists(atPath: session.paths.audioTempURL.path) else {
            return
        }

        try AudioTranscoder.transcodeToM4A(
            sourceWAVURL: session.paths.audioTempURL,
            destinationURL: session.paths.audioURL
        )
        try fileManager.removeItem(at: session.paths.audioTempURL)
    }

    func writeRaw(_ text: String, for session: inout SessionContext) throws {
        try atomicWrite(text, to: session.paths.rawURL)
        try persistMetadata(session)
    }

    func writePolished(_ text: String, for session: inout SessionContext) throws {
        try atomicWrite(text, to: session.paths.polishedURL)
        try persistMetadata(session)
    }

    func recoverDanglingRecordings() -> [URL] {
        guard let enumerator = fileManager.enumerator(at: layout.recordings, includingPropertiesForKeys: nil) else {
            return []
        }

        var recovered: [URL] = []

        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".wav.part") {
            recovered.append(url)
        }

        return recovered
    }

    func loadLatestPolishedTranscript() -> String? {
        let dayFolders = (try? fileManager.contentsOfDirectory(
            at: layout.recordings,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for dayFolder in dayFolders.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            guard (try? dayFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            let sessions = (try? fileManager.contentsOfDirectory(
                at: dayFolder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for sessionFolder in sessions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                guard (try? sessionFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }

                let polishedURL = sessionFolder.appendingPathComponent("polished.md")
                guard fileManager.fileExists(atPath: polishedURL.path),
                      let value = try? String(contentsOf: polishedURL, encoding: .utf8) else {
                    continue
                }

                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }

    private func persistMetadata(_ session: SessionContext) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(session.metadata)
        try atomicWrite(data, to: session.paths.metadataURL)
    }

    private func atomicWrite(_ text: String, to url: URL) throws {
        try atomicWrite(Data(text.utf8), to: url)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).tmp")
        try data.write(to: temp, options: [.atomic])

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        try fileManager.moveItem(at: temp, to: url)
    }
}
