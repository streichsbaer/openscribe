import Foundation

struct MicrophoneDevice: Equatable, Identifiable {
    let id: String
    let name: String
}

struct MicrophoneDeviceSnapshot: Equatable {
    let devices: [MicrophoneDevice]
    let systemDefaultDeviceID: String?
    let systemDefaultDeviceName: String?
}

enum MicrophoneResolutionSource: Equatable {
    case pinned
    case sessionOverride
    case systemDefault
    case firstAvailable
    case unavailable
}

struct MicrophoneResolutionResult: Equatable {
    let device: MicrophoneDevice?
    let source: MicrophoneResolutionSource
    let statusMessage: String?
}

enum MicrophoneSelectionResolver {
    static func resolve(
        snapshot: MicrophoneDeviceSnapshot,
        pinnedMicrophone: PinnedMicrophone?,
        sessionOverrideID: String?
    ) -> MicrophoneResolutionResult {
        let devicesByID = Dictionary(uniqueKeysWithValues: snapshot.devices.map { ($0.id, $0) })

        if let sessionOverrideID,
           let sessionDevice = devicesByID[sessionOverrideID] {
            return MicrophoneResolutionResult(
                device: sessionDevice,
                source: .sessionOverride,
                statusMessage: nil
            )
        }

        if let pinnedMicrophone {
            if let pinnedDevice = devicesByID[pinnedMicrophone.id] {
                return MicrophoneResolutionResult(
                    device: pinnedDevice,
                    source: .pinned,
                    statusMessage: nil
                )
            }

            if let defaultID = snapshot.systemDefaultDeviceID,
               let systemDefault = devicesByID[defaultID] {
                return MicrophoneResolutionResult(
                    device: systemDefault,
                    source: .systemDefault,
                    statusMessage: "Pinned mic \"\(pinnedMicrophone.name)\" unavailable. Using system default \"\(systemDefault.name)\"."
                )
            }

            if let firstDevice = snapshot.devices.first {
                return MicrophoneResolutionResult(
                    device: firstDevice,
                    source: .firstAvailable,
                    statusMessage: "Pinned mic \"\(pinnedMicrophone.name)\" unavailable. Using available input \"\(firstDevice.name)\"."
                )
            }

            return MicrophoneResolutionResult(
                device: nil,
                source: .unavailable,
                statusMessage: "Pinned mic \"\(pinnedMicrophone.name)\" unavailable and no microphone input is currently available."
            )
        }

        if let defaultID = snapshot.systemDefaultDeviceID,
           let systemDefault = devicesByID[defaultID] {
            return MicrophoneResolutionResult(
                device: systemDefault,
                source: .systemDefault,
                statusMessage: nil
            )
        }

        if let firstDevice = snapshot.devices.first {
            return MicrophoneResolutionResult(
                device: firstDevice,
                source: .firstAvailable,
                statusMessage: nil
            )
        }

        return MicrophoneResolutionResult(
            device: nil,
            source: .unavailable,
            statusMessage: "No microphone input is currently available."
        )
    }
}

enum MicrophoneCaptureRouting {
    static func inputDeviceIDForCapture(
        resolution: MicrophoneResolutionResult,
        systemDefaultDeviceID: String?
    ) -> String? {
        guard let selectedDeviceID = resolution.device?.id else {
            return nil
        }

        switch resolution.source {
        case .sessionOverride, .pinned, .firstAvailable:
            if selectedDeviceID == systemDefaultDeviceID {
                return nil
            }
            return selectedDeviceID
        case .systemDefault, .unavailable:
            return nil
        }
    }
}
