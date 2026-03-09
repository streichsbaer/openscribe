import CoreAudio
import Foundation

protocol MicrophoneDeviceCatalogProtocol: AnyObject {
    var onSnapshotChange: ((MicrophoneDeviceSnapshot) -> Void)? { get set }
    func currentSnapshot() -> MicrophoneDeviceSnapshot
}

final class MicrophoneDeviceCatalog: MicrophoneDeviceCatalogProtocol {
    var onSnapshotChange: ((MicrophoneDeviceSnapshot) -> Void)?

    private final class ListenerRelay {
        weak var owner: MicrophoneDeviceCatalog?

        func publishSnapshot() {
            owner?.publishSnapshot()
        }
    }

    private let listenerQueue: DispatchQueue
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerRelay: ListenerRelay
    private let propertyListener: AudioObjectPropertyListenerBlock

    init(listenerQueue: DispatchQueue = .main) {
        let listenerRelay = ListenerRelay()
        self.listenerQueue = listenerQueue
        self.listenerRelay = listenerRelay
        self.propertyListener = { [weak listenerRelay] _, _ in
            listenerRelay?.publishSnapshot()
        }
        listenerRelay.owner = self
        registerForDeviceChanges()
    }

    deinit {
        unregisterForDeviceChanges()
    }

    func currentSnapshot() -> MicrophoneDeviceSnapshot {
        CoreAudioMicrophoneCatalog.currentSnapshot()
    }

    private func registerForDeviceChanges() {
        for var propertyAddress in CoreAudioMicrophoneCatalog.propertyAddressesToObserve() {
            AudioObjectAddPropertyListenerBlock(
                systemObjectID,
                &propertyAddress,
                listenerQueue,
                propertyListener
            )
        }
    }

    private func unregisterForDeviceChanges() {
        for var propertyAddress in CoreAudioMicrophoneCatalog.propertyAddressesToObserve() {
            AudioObjectRemovePropertyListenerBlock(
                systemObjectID,
                &propertyAddress,
                listenerQueue,
                propertyListener
            )
        }
    }

    private func publishSnapshot() {
        onSnapshotChange?(currentSnapshot())
    }
}
