import Carbon
import Foundation

enum HotkeyAction: UInt32, CaseIterable {
    case startStop = 1
    case copyLatest = 2
    case pasteLatest = 3
    case togglePopover = 4
    case openSettings = 5
    case copyRaw = 6
}

enum HotkeyError: Error, LocalizedError {
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let message):
            return message
        }
    }
}

final class HotkeyManager {
    private var handlerRef: EventHandlerRef?
    private var hotkeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var actions: [HotkeyAction: () -> Void] = [:]

    private let signature: OSType = 0x5354524E // 'STRN'

    init() {
        installHandlerIfNeeded()
    }

    deinit {
        for (_, ref) in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }

        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func register(action: HotkeyAction, setting: HotkeySetting, handler: @escaping () -> Void) throws {
        unregister(action: action)
        let normalized = setting.normalizedForCarbonHotkey()

        if normalized.keyCode == 49 && normalized.modifiers == 0 {
            throw HotkeyError.registrationFailed(
                "Refusing to register plain Space as a global hotkey. Please choose a modified shortcut."
            )
        }

        let hotkeyID = EventHotKeyID(signature: signature, id: action.rawValue)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            normalized.keyCode,
            normalized.modifiers,
            hotkeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            throw HotkeyError.registrationFailed(
                "Failed to register hotkey action \(action.rawValue). macOS status: \(status)"
            )
        }

        hotkeyRefs[action] = ref
        actions[action] = handler
    }

    func unregister(action: HotkeyAction) {
        if let ref = hotkeyRefs[action] {
            UnregisterEventHotKey(ref)
            hotkeyRefs.removeValue(forKey: action)
        }

        actions.removeValue(forKey: action)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else {
            return
        }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let userData, let event else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handle(event: event)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        if status != noErr {
            handlerRef = nil
        }
    }

    private func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == signature,
              let action = HotkeyAction(rawValue: hotKeyID.id),
              let handler = actions[action] else {
            return OSStatus(eventNotHandledErr)
        }

        handler()
        return noErr
    }
}
