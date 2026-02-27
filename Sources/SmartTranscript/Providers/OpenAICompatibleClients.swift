import Foundation

struct OpenAITranscriptionResponse: Codable {
    let text: String?
}

struct OpenAIChatRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

struct OpenAIChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }

        let index: Int
        let message: Message
    }

    let choices: [Choice]
}

enum OpenAICompatibleError: Error {
    case http(Int, String)
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
        mimeType: "audio/wav"
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
    let requestBody = OpenAIChatRequest(
        model: model,
        messages: [
            .init(role: "system", content: systemPrompt),
            .init(role: "user", content: userPrompt)
        ],
        temperature: 0.1
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
    guard let content = payload.choices.first?.message.content else {
        throw ProviderError.invalidResponse
    }

    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}
