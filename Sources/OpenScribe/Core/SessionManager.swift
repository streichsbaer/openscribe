import Foundation

final class SessionManager {
    private let layout: DirectoryLayout
    private let fileManager: FileManager
    private static let metadataDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

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

    func loadSessionHistory(limit: Int) -> [SessionHistoryEntry] {
        loadSessionHistoryPage(limit: limit).entries
    }

    func loadSessionContext(folderURL: URL) -> SessionContext? {
        let metadataURL = folderURL.appendingPathComponent("session.json")
        guard fileManager.fileExists(atPath: metadataURL.path),
              let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? Self.metadataDecoder.decode(SessionMetadata.self, from: metadataData) else {
            return nil
        }

        let paths = SessionPaths(
            folderURL: folderURL,
            audioTempURL: folderURL.appendingPathComponent("audio.capture.wav.part"),
            audioURL: folderURL.appendingPathComponent("audio.m4a"),
            metadataURL: metadataURL,
            rawURL: folderURL.appendingPathComponent("raw.txt"),
            polishedURL: folderURL.appendingPathComponent("polished.md")
        )

        return SessionContext(id: metadata.sessionId, paths: paths, metadata: metadata)
    }

    func loadSessionHistoryPage(limit: Int) -> SessionHistoryPage {
        let normalizedLimit = max(0, limit)
        guard normalizedLimit > 0 else {
            return SessionHistoryPage(entries: [], hasMore: false)
        }

        let scanLimit: Int
        if normalizedLimit == Int.max {
            scanLimit = Int.max
        } else {
            scanLimit = normalizedLimit + 1
        }

        let scanned = loadSessionHistoryEntries(limit: scanLimit)
        if normalizedLimit == Int.max {
            return SessionHistoryPage(entries: scanned, hasMore: false)
        }
        if scanned.count > normalizedLimit {
            return SessionHistoryPage(
                entries: Array(scanned.prefix(normalizedLimit)),
                hasMore: true
            )
        }
        return SessionHistoryPage(entries: scanned, hasMore: false)
    }

    private func loadSessionHistoryEntries(limit: Int) -> [SessionHistoryEntry] {
        let dayFolders = (try? fileManager.contentsOfDirectory(
            at: layout.recordings,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var entries: [SessionHistoryEntry] = []

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
                guard entries.count < limit else {
                    return entries
                }
                guard (try? sessionFolder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                guard let entry = loadSessionHistoryEntry(from: sessionFolder) else {
                    continue
                }
                entries.append(entry)
            }
        }

        return entries
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

    private func loadSessionHistoryEntry(from sessionFolder: URL) -> SessionHistoryEntry? {
        let metadataURL = sessionFolder.appendingPathComponent("session.json")
        guard fileManager.fileExists(atPath: metadataURL.path),
              let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? Self.metadataDecoder.decode(SessionMetadata.self, from: metadataData) else {
            return nil
        }

        let previewText = sessionPreviewText(from: sessionFolder)

        return SessionHistoryEntry(
            id: metadata.sessionId,
            folderURL: sessionFolder,
            createdAt: metadata.createdAt,
            state: metadata.state,
            sttProvider: metadata.sttProvider,
            sttModel: metadata.sttModel,
            polishProvider: metadata.polishProvider,
            polishModel: metadata.polishModel,
            previewText: previewText
        )
    }

    private func sessionPreviewText(from sessionFolder: URL) -> String {
        let polishedURL = sessionFolder.appendingPathComponent("polished.md")
        let rawURL = sessionFolder.appendingPathComponent("raw.txt")

        if let polished = fileText(at: polishedURL), !polished.isEmpty {
            return polished
        }
        if let raw = fileText(at: rawURL), !raw.isEmpty {
            return raw
        }
        return ""
    }

    private func fileText(at url: URL) -> String? {
        guard fileManager.fileExists(atPath: url.path),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        let maxPreviewLength = 220
        if normalized.count <= maxPreviewLength {
            return normalized
        }

        let end = normalized.index(normalized.startIndex, offsetBy: maxPreviewLength)
        return String(normalized[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
