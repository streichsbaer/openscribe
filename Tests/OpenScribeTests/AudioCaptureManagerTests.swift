import Foundation
import XCTest
@testable import OpenScribe

final class AudioCaptureManagerTests: XCTestCase {
    func testStartRecordingThrowsWhenSelectedDeviceIsUnavailable() throws {
        let manager = AudioCaptureManager()
        let tempURL = temporaryFileURL()

        XCTAssertThrowsError(
            try manager.startRecording(to: tempURL, inputDeviceID: "__nonexistent_microphone_device__")
        )
    }

    private func temporaryFileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
        let fileName = "openscribe-audio-capture-test-\(UUID().uuidString).wav"
        return directory.appendingPathComponent(fileName)
    }
}
