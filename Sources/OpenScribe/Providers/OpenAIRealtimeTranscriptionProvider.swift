import Foundation

final class OpenAIRealtimeTranscriptionProvider: TranscriptionProvider {
    let id = "openai_realtime_transcription"
    let displayName = "OpenAI Realtime"

    private let apiKey: String
    private let sampleRate: Int

    init(apiKey: String, sampleRate: Int = 24_000) {
        self.apiKey = apiKey
        self.sampleRate = sampleRate
    }

    func transcribe(audioFileURL: URL, language: String?, model: String, instruction: String?) async throws -> TranscriptResult {
        let start = Date()
        let pcmData = try OpenAIRealtimeAudioLoader.loadPCM24k(from: audioFileURL)
        let session = OpenAIRealtimeTranscriptionSession(
            apiKey: apiKey,
            model: model,
            language: language,
            sampleRate: sampleRate,
            onPartialTranscript: nil
        )

        try await session.connect()
        try await session.appendAudio(pcmData)
        let transcript = try await session.finish()
        guard !transcript.isEmpty else {
            throw ProviderError.invalidResponse
        }

        return TranscriptResult(
            text: transcript,
            providerId: id,
            model: model,
            latencyMs: Int(Date().timeIntervalSince(start) * 1_000),
            inputTokens: nil,
            outputTokens: nil
        )
    }
}

actor OpenAIRealtimeTranscriptionSession {
    private let apiKey: String
    private let model: String
    private let language: String?
    private let sampleRate: Int
    private let onPartialTranscript: (@MainActor @Sendable (String) -> Void)?
    private let endpoint = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var partialTranscript = ""
    private var finalTranscript: String?
    private var failure: Error?
    private var completionContinuation: CheckedContinuation<String, Error>?
    private var didClose = false

    init(
        apiKey: String,
        model: String,
        language: String?,
        sampleRate: Int,
        onPartialTranscript: (@MainActor @Sendable (String) -> Void)?
    ) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
        self.sampleRate = sampleRate
        self.onPartialTranscript = onPartialTranscript
    }

    func connect() async throws {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("openscribe-desktop", forHTTPHeaderField: "OpenAI-Safety-Identifier")

        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }

        try await sendSessionUpdate()
    }

    func appendAudio(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        try checkFailure()
        try await sendEvent([
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ])
    }

    func finish() async throws -> String {
        try checkFailure()
        try await sendEvent(["type": "input_audio_buffer.commit"])

        if let finalTranscript {
            close()
            return finalTranscript
        }
        if let failure {
            close()
            throw failure
        }

        let transcript = try await withCheckedThrowingContinuation { continuation in
            completionContinuation = continuation
        }
        close()
        return transcript
    }

    func cancel() {
        close()
    }

    private func sendSessionUpdate() async throws {
        try await sendEvent(Self.sessionUpdatePayload(
            model: model,
            language: language,
            sampleRate: sampleRate
        ))
    }

    nonisolated static func sessionUpdatePayload(model: String, language: String?, sampleRate: Int) -> [String: Any] {
        var transcription: [String: Any] = ["model": model]
        if let language, !language.isEmpty, language.lowercased() != "auto" {
            transcription["language"] = language
        }

        return [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": sampleRate
                        ],
                        "transcription": transcription,
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ]
    }

    private func receiveLoop() async {
        while !didClose {
            guard let webSocketTask else {
                fail(ProviderError.invalidResponse)
                return
            }

            do {
                let message = try await webSocketTask.receive()
                try handle(message: message)
            } catch {
                if !didClose {
                    fail(error)
                }
                return
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) throws {
        let data: Data
        switch message {
        case .string(let value):
            data = Data(value.utf8)
        case .data(let value):
            data = value
        @unknown default:
            throw ProviderError.invalidResponse
        }

        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = payload["type"] as? String else {
            throw ProviderError.invalidResponse
        }

        switch type {
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = payload["delta"] as? String, !delta.isEmpty else { return }
            partialTranscript += delta
            let current = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty, let onPartialTranscript {
                Task { @MainActor in
                    onPartialTranscript(current)
                }
            }
        case "conversation.item.input_audio_transcription.completed":
            let transcript = (payload["transcript"] as? String ?? partialTranscript)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            finalTranscript = transcript
            completionContinuation?.resume(returning: transcript)
            completionContinuation = nil
        case "error":
            fail(OpenAIRealtimeTranscriptionError(payload: payload))
        default:
            break
        }
    }

    private func sendEvent(_ payload: [String: Any]) async throws {
        guard let webSocketTask else {
            throw ProviderError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let message = String(data: data, encoding: .utf8) else {
            throw ProviderError.invalidResponse
        }
        try await webSocketTask.send(.string(message))
    }

    private func checkFailure() throws {
        if let failure {
            throw failure
        }
    }

    private func fail(_ error: Error) {
        failure = error
        completionContinuation?.resume(throwing: error)
        completionContinuation = nil
    }

    private func close() {
        didClose = true
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
}

final class OpenAIRealtimeAudioSender: @unchecked Sendable {
    private let continuation: AsyncStream<Data>.Continuation
    private let task: Task<Void, Error>

    convenience init(session: OpenAIRealtimeTranscriptionSession) {
        self.init(onReady: {}, onSend: { data in
            try await session.appendAudio(data)
        })
    }

    convenience init(
        session: OpenAIRealtimeTranscriptionSession,
        connect: @escaping @Sendable () async throws -> Void
    ) {
        self.init(onReady: connect, onSend: { data in
            try await session.appendAudio(data)
        })
    }

    init(
        onReady: @escaping @Sendable () async throws -> Void = {},
        onSend: @escaping @Sendable (Data) async throws -> Void
    ) {
        var streamContinuation: AsyncStream<Data>.Continuation?
        let stream = AsyncStream<Data> { continuation in
            streamContinuation = continuation
        }
        guard let streamContinuation else {
            preconditionFailure("Realtime audio stream continuation was not created.")
        }

        self.continuation = streamContinuation
        self.task = Task {
            try await onReady()
            for await data in stream {
                try await onSend(data)
            }
        }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        continuation.yield(data)
    }

    func finishSending() async throws {
        continuation.finish()
        try await task.value
    }

    func cancel() {
        continuation.finish()
        task.cancel()
    }
}

struct OpenAIRealtimeTranscriptionError: Error, LocalizedError {
    let message: String

    init(payload: [String: Any]) {
        if let error = payload["error"] as? [String: Any],
           let message = error["message"] as? String {
            self.message = message
        } else {
            self.message = "OpenAI Realtime transcription failed."
        }
    }

    var errorDescription: String? {
        message
    }
}

enum OpenAIRealtimeAudioLoader {
    static func loadPCM24k(from sourceURL: URL) throws -> Data {
        let fileManager = FileManager.default
        let tempWAV = fileManager.temporaryDirectory
            .appendingPathComponent("openscribe-realtime-input-\(UUID().uuidString).wav")
        defer { try? fileManager.removeItem(at: tempWAV) }

        if sourceURL.pathExtension.lowercased() == "wav",
           isPCM24kWAV(sourceURL) {
            return try pcmData(from: sourceURL)
        }

        try AudioTranscoder.transcodeToRealtimeWAV(sourceURL: sourceURL, destinationURL: tempWAV)
        return try pcmData(from: tempWAV)
    }

    private static func isPCM24kWAV(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), data.count >= 28 else {
            return false
        }
        let riff = String(data: data[0..<4], encoding: .ascii)
        let wave = String(data: data[8..<12], encoding: .ascii)
        let sampleRate = UInt32(data[24]) |
            UInt32(data[25]) << 8 |
            UInt32(data[26]) << 16 |
            UInt32(data[27]) << 24
        return riff == "RIFF" && wave == "WAVE" && sampleRate == 24_000
    }

    private static func pcmData(from url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard let range = findDataChunk(in: data) else {
            throw ProviderError.invalidResponse
        }
        return data.subdata(in: range)
    }

    private static func findDataChunk(in data: Data) -> Range<Int>? {
        guard data.count >= 12,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            return nil
        }

        var offset = 12
        while offset + 8 <= data.count {
            guard let chunkID = String(data: data[offset..<(offset + 4)], encoding: .ascii) else {
                return nil
            }
            let chunkSizeOffset = offset + 4
            let chunkSize = Int(UInt32(data[chunkSizeOffset]) |
                UInt32(data[chunkSizeOffset + 1]) << 8 |
                UInt32(data[chunkSizeOffset + 2]) << 16 |
                UInt32(data[chunkSizeOffset + 3]) << 24)
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + chunkSize
            guard payloadEnd <= data.count else {
                return nil
            }
            if chunkID == "data" {
                return payloadStart..<payloadEnd
            }
            offset = payloadEnd + (chunkSize % 2)
        }

        return nil
    }
}
