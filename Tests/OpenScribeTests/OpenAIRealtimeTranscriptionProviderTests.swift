import Foundation
import XCTest
@testable import OpenScribe

final class OpenAIRealtimeTranscriptionProviderTests: XCTestCase {
    func testSessionUpdatePayloadUsesRealtimeTranscriptionSchema() throws {
        let payload = OpenAIRealtimeTranscriptionSession.sessionUpdatePayload(
            model: "gpt-realtime-whisper",
            language: "en",
            sampleRate: 24_000
        )

        XCTAssertEqual(payload["type"] as? String, "session.update")

        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "transcription")

        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24_000)

        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-realtime-whisper")
        XCTAssertEqual(transcription["language"] as? String, "en")
        XCTAssertTrue(input["turn_detection"] is NSNull)
    }

    func testRealtimeAudioSenderPreservesChunkOrderBeforeFinish() async throws {
        let recorder = RealtimeAudioSendRecorder()
        let sender = OpenAIRealtimeAudioSender { data in
            await recorder.append(data)
        }

        sender.append(Data([0x01]))
        sender.append(Data([0x02]))
        sender.append(Data([0x03]))

        try await sender.finishSending()

        let chunks = await recorder.chunks
        XCTAssertEqual(chunks, [
            Data([0x01]),
            Data([0x02]),
            Data([0x03])
        ])
    }
}

private actor RealtimeAudioSendRecorder {
    private(set) var chunks: [Data] = []

    func append(_ data: Data) {
        chunks.append(data)
    }
}
