import Foundation

struct OpenAITranscriptionResponse: Codable {
    let text: String?
}

struct OpenAIChatRequest: Codable {
    struct InputAudio: Codable {
        let format: String
        let data: String
    }

    struct ContentPart: Codable {
        let type: String
        let text: String?
        let inputAudio: InputAudio?

        init(type: String, text: String? = nil, inputAudio: InputAudio? = nil) {
            self.type = type
            self.text = text
            self.inputAudio = inputAudio
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case inputAudio = "input_audio"
        }
    }

    struct Message: Codable {
        let role: String
        let content: Content

        init(role: String, content: String) {
            self.role = role
            self.content = .text(content)
        }

        init(role: String, parts: [ContentPart]) {
            self.role = role
            self.content = .parts(parts)
        }
    }

    enum Content: Codable {
        case text(String)
        case parts([ContentPart])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }
            self = .parts(try container.decode([ContentPart].self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(text)
            case .parts(let parts):
                try container.encode(parts)
            }
        }
    }

    let model: String
    let messages: [Message]
    let temperature: Double?
}

struct OpenAIChatResponse: Codable {
    struct ContentPart: Codable {
        let type: String?
        let text: String?
    }

    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: Content

            enum Content: Codable {
                case text(String)
                case parts([ContentPart])

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let text = try? container.decode(String.self) {
                        self = .text(text)
                        return
                    }
                    self = .parts(try container.decode([ContentPart].self))
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.singleValueContainer()
                    switch self {
                    case .text(let text):
                        try container.encode(text)
                    case .parts(let parts):
                        try container.encode(parts)
                    }
                }
            }

            var textualContent: String {
                switch content {
                case .text(let text):
                    return text
                case .parts(let parts):
                    return parts
                        .compactMap(\.text)
                        .joined(separator: "\n")
                }
            }
        }

        let index: Int
        let message: Message
    }

    let choices: [Choice]
}

enum OpenAICompatibleError: Error, LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let rawDetails):
            let details = Self.extractMessage(from: rawDetails) ?? rawDetails
            if details.isEmpty {
                return "OpenAI-compatible API request failed with HTTP \(status)."
            }
            return "OpenAI-compatible API request failed with HTTP \(status): \(details)"
        }
    }

    private static func extractMessage(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}

func performWhisperRequest(
    endpoint: URL,
    apiKey: String,
    model: String,
    audioFileURL: URL,
    language: String?,
    extraFields: [String: String] = [:]
) async throws -> String {
    let builder = MultipartFormDataBuilder()
    var fields: [String: String] = ["model": model]

    if let language, !language.isEmpty, language.lowercased() != "auto" {
        fields["language"] = language
    }
    for (key, value) in extraFields {
        fields[key] = value
    }

    let body = try builder.makeBody(
        fields: fields,
        fileFieldName: "file",
        fileURL: audioFileURL,
        mimeType: mimeTypeForWhisperUpload(audioFileURL)
    )

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(builder.boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw ProviderError.invalidResponse
    }

    guard (200..<300).contains(http.statusCode) else {
        let details = String(data: data, encoding: .utf8) ?? ""
        throw OpenAICompatibleError.http(http.statusCode, details)
    }

    if let payload = try? JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data),
       let text = payload.text?.trimmingCharacters(in: .whitespacesAndNewlines),
       !text.isEmpty {
        return text
    }

    if let text = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !text.isEmpty {
        return text
    }

    throw ProviderError.invalidResponse
}

func performChatRequest(
    endpoint: URL,
    apiKey: String,
    model: String,
    systemPrompt: String,
    userPrompt: String
) async throws -> String {
    let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let temperature: Double? = normalizedModel.hasPrefix("gpt-5") ? nil : 0.1

    let requestBody = OpenAIChatRequest(
        model: model,
        messages: [
            .init(role: "system", content: systemPrompt),
            .init(role: "user", content: userPrompt)
        ],
        temperature: temperature
    )

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
        throw ProviderError.invalidResponse
    }

    guard (200..<300).contains(http.statusCode) else {
        let details = String(data: data, encoding: .utf8) ?? ""
        throw OpenAICompatibleError.http(http.statusCode, details)
    }

    let payload = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
    guard let content = payload.choices.first?.message.textualContent else {
        throw ProviderError.invalidResponse
    }

    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}

func performAudioTranscriptionViaChatRequest(
    endpoint: URL,
    apiKey: String,
    model: String,
    audioFileURL: URL,
    language: String?
) async throws -> String {
    let preparedAudio = try prepareAudioForInputAudioPayload(audioFileURL)
    defer {
        if let cleanupURL = preparedAudio.cleanupURL {
            try? FileManager.default.removeItem(at: cleanupURL)
        }
    }
    let audioData = try Data(contentsOf: preparedAudio.fileURL)
    let audioBase64 = audioData.base64EncodedString()

    var instructions = "Transcribe the provided audio exactly. Return plain text only."
    if let language, !language.isEmpty, language.lowercased() != "auto" {
        instructions += " The target language is \(language)."
    }

    let requestBody = OpenAIChatRequest(
        model: model,
        messages: [
            .init(role: "system", content: "You are a transcription engine. Return transcript text only."),
            .init(
                role: "user",
                parts: [
                    .init(type: "text", text: instructions),
                    .init(
                        type: "input_audio",
                        inputAudio: .init(format: preparedAudio.format, data: audioBase64)
                    )
                ]
            )
        ],
        temperature: nil
    )

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
        throw ProviderError.invalidResponse
    }

    guard (200..<300).contains(http.statusCode) else {
        let details = String(data: data, encoding: .utf8) ?? ""
        throw OpenAICompatibleError.http(http.statusCode, details)
    }

    let payload = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
    guard let content = payload.choices.first?.message.textualContent
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !content.isEmpty else {
        throw ProviderError.invalidResponse
    }

    return content
}

private func mimeTypeForWhisperUpload(_ url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "wav":
        return "audio/wav"
    case "m4a":
        return "audio/m4a"
    case "mp3":
        return "audio/mpeg"
    case "mpga", "mpeg":
        return "audio/mpeg"
    case "mp4":
        return "audio/mp4"
    case "webm":
        return "audio/webm"
    default:
        return "application/octet-stream"
    }
}

private struct PreparedInputAudio {
    let fileURL: URL
    let format: String
    let cleanupURL: URL?
}

private func prepareAudioForInputAudioPayload(_ sourceURL: URL) throws -> PreparedInputAudio {
    let ext = sourceURL.pathExtension.lowercased()
    if ext == "wav" || ext == "mp3" {
        return PreparedInputAudio(fileURL: sourceURL, format: ext, cleanupURL: nil)
    }

    let tempWAV = FileManager.default.temporaryDirectory
        .appendingPathComponent("openscribe-input-audio-\(UUID().uuidString).wav")
    try AudioTranscoder.transcodeToWAV(sourceURL: sourceURL, destinationURL: tempWAV)
    return PreparedInputAudio(fileURL: tempWAV, format: "wav", cleanupURL: tempWAV)
}
