import Foundation

struct ProviderTextResponse {
    let text: String
    let inputTokens: Int?
    let outputTokens: Int?
}

private let defaultChatTranscriptionInstruction = "Transcribe the provided audio exactly. Return plain text only."

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
    struct Usage: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }
    }

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
    let usage: Usage?
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
) async throws -> ProviderTextResponse {
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
        let usage = extractTokenUsage(from: data)
        return ProviderTextResponse(text: text, inputTokens: usage.inputTokens, outputTokens: usage.outputTokens)
    }

    if let text = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !text.isEmpty {
        return ProviderTextResponse(text: text, inputTokens: nil, outputTokens: nil)
    }

    throw ProviderError.invalidResponse
}

func performChatRequest(
    endpoint: URL,
    apiKey: String,
    model: String,
    systemPrompt: String?,
    userPrompt: String
) async throws -> ProviderTextResponse {
    let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let temperature: Double? = normalizedModel.hasPrefix("gpt-5") ? nil : 0.1

    var messages: [OpenAIChatRequest.Message] = []
    if let systemPrompt = normalizedInstruction(systemPrompt) {
        messages.append(.init(role: "system", content: systemPrompt))
    }
    messages.append(.init(role: "user", content: userPrompt))

    let requestBody = OpenAIChatRequest(
        model: model,
        messages: messages,
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

    let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    let inputTokens = payload.usage?.inputTokens ?? payload.usage?.promptTokens
    let outputTokens = payload.usage?.outputTokens ?? payload.usage?.completionTokens
    return ProviderTextResponse(
        text: normalizedContent,
        inputTokens: inputTokens,
        outputTokens: outputTokens
    )
}

func performAudioTranscriptionViaChatRequest(
    endpoint: URL,
    apiKey: String,
    model: String,
    audioFileURL: URL,
    language: String?,
    instruction: String?
) async throws -> ProviderTextResponse {
    let preparedAudio = try prepareAudioForInputAudioPayload(audioFileURL)
    defer {
        if let cleanupURL = preparedAudio.cleanupURL {
            try? FileManager.default.removeItem(at: cleanupURL)
        }
    }
    let audioData = try Data(contentsOf: preparedAudio.fileURL)
    let audioBase64 = audioData.base64EncodedString()

    let normalizedInstruction = normalizedInstruction(instruction)
    let languageInstruction: String?
    if let language, !language.isEmpty, language.lowercased() != "auto" {
        languageInstruction = "The target language is \(language)."
    } else {
        languageInstruction = nil
    }

    var contentParts: [OpenAIChatRequest.ContentPart] = []
    var directive = defaultChatTranscriptionInstruction
    if let normalizedInstruction {
        directive += "\n\(normalizedInstruction)"
    }
    contentParts.append(.init(type: "text", text: directive))
    if let languageInstruction {
        contentParts.append(.init(type: "text", text: languageInstruction))
    }
    contentParts.append(
        .init(
            type: "input_audio",
            inputAudio: .init(format: preparedAudio.format, data: audioBase64)
        )
    )

    let requestBody = OpenAIChatRequest(
        model: model,
        messages: [
            .init(role: "system", content: "You are a transcription engine. Return transcript text only."),
            .init(
                role: "user",
                parts: contentParts
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

    let inputTokens = payload.usage?.inputTokens ?? payload.usage?.promptTokens
    let outputTokens = payload.usage?.outputTokens ?? payload.usage?.completionTokens
    return ProviderTextResponse(
        text: content,
        inputTokens: inputTokens,
        outputTokens: outputTokens
    )
}

private func extractTokenUsage(from data: Data) -> (inputTokens: Int?, outputTokens: Int?) {
    guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let usage = raw["usage"] as? [String: Any] else {
        return (nil, nil)
    }
    let inputTokens = extractInt(from: usage, keys: ["input_tokens", "prompt_tokens"])
    let outputTokens = extractInt(from: usage, keys: ["output_tokens", "completion_tokens"])
    return (inputTokens, outputTokens)
}

private func extractInt(from payload: [String: Any], keys: [String]) -> Int? {
    for key in keys {
        if let value = payload[key] as? Int {
            return value
        }
        if let value = payload[key] as? NSNumber {
            return value.intValue
        }
        if let value = payload[key] as? String,
           let parsed = Int(value) {
            return parsed
        }
    }
    return nil
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
