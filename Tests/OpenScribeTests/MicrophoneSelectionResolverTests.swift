import XCTest
@testable import OpenScribe

final class MicrophoneSelectionResolverTests: XCTestCase {
    func testSessionSelectionWinsWhenAvailable() {
        let snapshot = MicrophoneDeviceSnapshot(
            devices: [
                MicrophoneDevice(id: "builtin", name: "Built-in Mic"),
                MicrophoneDevice(id: "usb", name: "USB Mic")
            ],
            systemDefaultDeviceID: "builtin",
            systemDefaultDeviceName: "Built-in Mic"
        )

        let result = MicrophoneSelectionResolver.resolve(
            snapshot: snapshot,
            pinnedMicrophone: PinnedMicrophone(id: "usb", name: "USB Mic"),
            sessionOverrideID: "builtin"
        )

        XCTAssertEqual(result.source, .sessionOverride)
        XCTAssertEqual(result.device?.id, "builtin")
        XCTAssertNil(result.statusMessage)
    }

    func testPinnedMicrophoneUsedWhenSessionSelectionIsNotSet() {
        let snapshot = MicrophoneDeviceSnapshot(
            devices: [
                MicrophoneDevice(id: "builtin", name: "Built-in Mic"),
                MicrophoneDevice(id: "usb", name: "USB Mic")
            ],
            systemDefaultDeviceID: "builtin",
            systemDefaultDeviceName: "Built-in Mic"
        )

        let result = MicrophoneSelectionResolver.resolve(
            snapshot: snapshot,
            pinnedMicrophone: PinnedMicrophone(id: "usb", name: "USB Mic"),
            sessionOverrideID: nil
        )

        XCTAssertEqual(result.source, .pinned)
        XCTAssertEqual(result.device?.id, "usb")
        XCTAssertNil(result.statusMessage)
    }

    func testSessionSelectionUsedWhenPinnedMicrophoneIsMissing() {
        let snapshot = MicrophoneDeviceSnapshot(
            devices: [
                MicrophoneDevice(id: "builtin", name: "Built-in Mic"),
                MicrophoneDevice(id: "usb", name: "USB Mic")
            ],
            systemDefaultDeviceID: "builtin",
            systemDefaultDeviceName: "Built-in Mic"
        )

        let result = MicrophoneSelectionResolver.resolve(
            snapshot: snapshot,
            pinnedMicrophone: PinnedMicrophone(id: "gone", name: "Desk Mic"),
            sessionOverrideID: "usb"
        )

        XCTAssertEqual(result.source, .sessionOverride)
        XCTAssertEqual(result.device?.id, "usb")
        XCTAssertNil(result.statusMessage)
    }

    func testMissingPinnedMicrophoneFallsBackToSystemDefault() {
        let snapshot = MicrophoneDeviceSnapshot(
            devices: [
                MicrophoneDevice(id: "builtin", name: "Built-in Mic"),
                MicrophoneDevice(id: "usb", name: "USB Mic")
            ],
            systemDefaultDeviceID: "builtin",
            systemDefaultDeviceName: "Built-in Mic"
        )

        let result = MicrophoneSelectionResolver.resolve(
            snapshot: snapshot,
            pinnedMicrophone: PinnedMicrophone(id: "gone", name: "Desk Mic"),
            sessionOverrideID: nil
        )

        XCTAssertEqual(result.source, .systemDefault)
        XCTAssertEqual(result.device?.id, "builtin")
        XCTAssertEqual(result.statusMessage, "Pinned mic \"Desk Mic\" unavailable. Using system default \"Built-in Mic\".")
    }

    func testNoInputsAvailableReturnsUnavailable() {
        let snapshot = MicrophoneDeviceSnapshot(
            devices: [],
            systemDefaultDeviceID: nil,
            systemDefaultDeviceName: nil
        )

        let result = MicrophoneSelectionResolver.resolve(
            snapshot: snapshot,
            pinnedMicrophone: PinnedMicrophone(id: "gone", name: "Desk Mic"),
            sessionOverrideID: nil
        )

        XCTAssertEqual(result.source, .unavailable)
        XCTAssertNil(result.device)
        XCTAssertEqual(result.statusMessage, "Pinned mic \"Desk Mic\" unavailable and no microphone input is currently available.")
    }

    func testMissingSystemDefaultFallsBackToFirstAvailable() {
        let snapshot = MicrophoneDeviceSnapshot(
            devices: [
                MicrophoneDevice(id: "usb", name: "USB Mic"),
                MicrophoneDevice(id: "builtin", name: "Built-in Mic")
            ],
            systemDefaultDeviceID: nil,
            systemDefaultDeviceName: nil
        )

        let result = MicrophoneSelectionResolver.resolve(
            snapshot: snapshot,
            pinnedMicrophone: nil,
            sessionOverrideID: nil
        )

        XCTAssertEqual(result.source, .firstAvailable)
        XCTAssertEqual(result.device?.id, "usb")
        XCTAssertNil(result.statusMessage)
    }

    func testCaptureRoutingReturnsNilForAutomaticSystemDefault() {
        let resolution = MicrophoneResolutionResult(
            device: MicrophoneDevice(id: "builtin", name: "Built-in Mic"),
            source: .systemDefault,
            statusMessage: nil
        )

        let inputDeviceID = MicrophoneCaptureRouting.inputDeviceIDForCapture(
            resolution: resolution,
            systemDefaultDeviceID: "builtin"
        )

        XCTAssertNil(inputDeviceID)
    }

    func testCaptureRoutingReturnsExplicitIDForNonDefaultSessionOverride() {
        let resolution = MicrophoneResolutionResult(
            device: MicrophoneDevice(id: "airpods", name: "AirPods Pro"),
            source: .sessionOverride,
            statusMessage: nil
        )

        let inputDeviceID = MicrophoneCaptureRouting.inputDeviceIDForCapture(
            resolution: resolution,
            systemDefaultDeviceID: "builtin"
        )

        XCTAssertEqual(inputDeviceID, "airpods")
    }

    func testCaptureRoutingReturnsNilForPinnedWhenPinnedIsSystemDefault() {
        let resolution = MicrophoneResolutionResult(
            device: MicrophoneDevice(id: "builtin", name: "Built-in Mic"),
            source: .pinned,
            statusMessage: nil
        )

        let inputDeviceID = MicrophoneCaptureRouting.inputDeviceIDForCapture(
            resolution: resolution,
            systemDefaultDeviceID: "builtin"
        )

        XCTAssertNil(inputDeviceID)
    }

    func testCaptureRoutingReturnsExplicitIDForFirstAvailableFallback() {
        let resolution = MicrophoneResolutionResult(
            device: MicrophoneDevice(id: "usb", name: "USB Mic"),
            source: .firstAvailable,
            statusMessage: nil
        )

        let inputDeviceID = MicrophoneCaptureRouting.inputDeviceIDForCapture(
            resolution: resolution,
            systemDefaultDeviceID: "builtin"
        )

        XCTAssertEqual(inputDeviceID, "usb")
    }
}
