import Foundation
import XCTest
@testable import OpenScribe

@MainActor
final class AudioCaptureManagerLiveTests: XCTestCase {
    func testDefaultMicrophoneCaptureStartStop() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RUN_LIVE_AUDIO_CAPTURE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_AUDIO_CAPTURE_TESTS=1 to run live microphone capture tests.")
        }

        let manager = AudioCaptureManager()
        let granted = await ensurePermissionGranted(manager)
        guard granted else {
            throw XCTSkip("Microphone permission is required for live audio capture tests.")
        }

        let playTTS = env["LIVE_CAPTURE_PLAY_TTS"] != "0"
        let requireSignal = env["LIVE_CAPTURE_REQUIRE_SIGNAL"] == "1"

        let result = try await capture(
            manager: manager,
            inputDeviceID: nil,
            durationSeconds: 1.8,
            playTTS: playTTS
        )

        XCTAssertGreaterThan(result.assessment.totalDurationMs, 900)
        XCTAssertGreaterThan(result.audioByteCount, 44)
        if requireSignal {
            XCTAssertGreaterThan(
                result.assessment.peakLevel,
                0,
                "No live signal detected. Consider setting LIVE_CAPTURE_PLAY_TTS=1 or speaking near the mic."
            )
        }
    }

    func testExplicitMicrophoneSelectionCaptureStartStop() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["RUN_LIVE_AUDIO_CAPTURE_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_LIVE_AUDIO_CAPTURE_TESTS=1 to run live microphone capture tests.")
        }

        let manager = AudioCaptureManager()
        let granted = await ensurePermissionGranted(manager)
        guard granted else {
            throw XCTSkip("Microphone permission is required for live audio capture tests.")
        }

        let targetID: String?
        if let configuredID = env["LIVE_CAPTURE_DEVICE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredID.isEmpty {
            targetID = configuredID
        } else {
            let snapshot = CoreAudioMicrophoneCatalog.currentSnapshot()
            targetID = snapshot.devices
                .first(where: { $0.id != snapshot.systemDefaultDeviceID })?
                .id ?? snapshot.systemDefaultDeviceID
        }

        guard let targetID else {
            throw XCTSkip("No audio input device available for explicit selection test.")
        }

        let playTTS = env["LIVE_CAPTURE_PLAY_TTS"] != "0"
        let requireSignal = env["LIVE_CAPTURE_REQUIRE_SIGNAL"] == "1"

        let result = try await capture(
            manager: manager,
            inputDeviceID: targetID,
            durationSeconds: 1.8,
            playTTS: playTTS
        )

        XCTAssertGreaterThan(result.assessment.totalDurationMs, 900)
        XCTAssertGreaterThan(result.audioByteCount, 44)
        if requireSignal {
            XCTAssertGreaterThan(
                result.assessment.peakLevel,
                0,
                "No live signal detected for selected input \(targetID)."
            )
        }
    }

    private func ensurePermissionGranted(_ manager: AudioCaptureManager) async -> Bool {
        switch manager.permissionState() {
        case .authorized:
            return true
        case .denied:
            return false
        case .undetermined:
            return await manager.requestPermission()
        }
    }

    private func capture(
        manager: AudioCaptureManager,
        inputDeviceID: String?,
        durationSeconds: Double,
        playTTS: Bool
    ) async throws -> (assessment: AudioActivityAssessment, audioByteCount: Int) {
        let tempURL = temporaryFileURL()
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try manager.startRecording(to: tempURL, inputDeviceID: inputDeviceID)
        if playTTS {
            launchTTS()
        }

        try await Task.sleep(for: .seconds(durationSeconds))
        let assessment = manager.stopRecording()
        let audioByteCount = (try? Data(contentsOf: tempURL).count) ?? 0
        return (assessment, audioByteCount)
    }

    private func launchTTS() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["Open Scribe live capture test sample"]
        try? process.run()
    }

    private func temporaryFileURL() -> URL {
        let fileName = "openscribe-live-capture-\(UUID().uuidString).wav"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}
