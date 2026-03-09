import CoreAudio
import Foundation

enum CoreAudioMicrophoneCatalog {
    private static let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

    struct Device: Equatable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    static func currentSnapshot() -> MicrophoneDeviceSnapshot {
        let devices = inputDevices()
        let defaultInputDeviceID = defaultInputDeviceID()

        return MicrophoneDeviceSnapshot(
            devices: devices
                .map { MicrophoneDevice(id: $0.uid, name: $0.name) }
                .sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                },
            systemDefaultDeviceID: defaultInputDeviceID.flatMap(deviceUID(for:)),
            systemDefaultDeviceName: defaultInputDeviceID.flatMap(deviceName(for:))
        )
    }

    static func audioDeviceID(for uid: String) -> AudioDeviceID? {
        inputDevices().first(where: { $0.uid == uid })?.id
    }

    static func propertyAddressesToObserve() -> [AudioObjectPropertyAddress] {
        [
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        ]
    }

    private static func inputDevices() -> [Device] {
        allAudioDeviceIDs().compactMap { deviceID in
            guard deviceHasInputChannels(deviceID),
                  let uid = deviceUID(for: deviceID),
                  let name = deviceName(for: deviceID) else {
                return nil
            }

            return Device(id: deviceID, uid: uid, name: name)
        }
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            systemObjectID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            return nil
        }

        return deviceID
    }

    private static func allAudioDeviceIDs() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            systemObjectID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)

        let dataStatus: OSStatus = deviceIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }

            return AudioObjectGetPropertyData(
                systemObjectID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }
        guard dataStatus == noErr else {
            return []
        }

        return deviceIDs
    }

    private static func deviceHasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return false
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            rawBuffer
        )
        guard dataStatus == noErr else {
            return false
        }

        let audioBufferList = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return bufferList.contains(where: { $0.mNumberChannels > 0 })
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        propertyString(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        propertyString(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private static func propertyString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &value) { valuePointer in
            AudioObjectGetPropertyData(
                objectID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                valuePointer
            )
        }
        guard status == noErr else {
            return nil
        }

        return value as String
    }
}
