import Carbon
import Foundation

enum HotkeyCaptureValidationResult: Equatable {
    case cancel
    case modifierOnly
    case missingModifier
    case save(HotkeySetting)
}

enum HotkeyCaptureValidator {
    private static let escapeKeyCode: UInt32 = 53
    private static let modifierOnlyKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static func validate(keyCode: UInt32, modifiers: UInt32) -> HotkeyCaptureValidationResult {
        if keyCode == escapeKeyCode {
            return .cancel
        }

        if modifierOnlyKeyCodes.contains(keyCode) {
            return .modifierOnly
        }

        guard modifiers != 0 else {
            return .missingModifier
        }

        return .save(HotkeySetting(keyCode: keyCode, modifiers: modifiers).normalizedForCarbonHotkey())
    }
}
