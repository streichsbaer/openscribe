import Carbon
import XCTest
@testable import OpenScribe

final class HotkeyCaptureValidatorTests: XCTestCase {
    func testModifierOnlyShortcutShowsValidationInsteadOfSaving() {
        let result = HotkeyCaptureValidator.validate(
            keyCode: 63,
            modifiers: HotkeySetting.carbonFunctionMask | UInt32(shiftKey)
        )

        XCTAssertEqual(result, .modifierOnly)
    }

    func testPlainKeyRequiresModifier() {
        let result = HotkeyCaptureValidator.validate(keyCode: 0, modifiers: 0)

        XCTAssertEqual(result, .missingModifier)
    }

    func testEscapeCancelsCapture() {
        let result = HotkeyCaptureValidator.validate(keyCode: 53, modifiers: UInt32(controlKey))

        XCTAssertEqual(result, .cancel)
    }

    func testFunctionSpaceSaves() {
        let result = HotkeyCaptureValidator.validate(
            keyCode: 49,
            modifiers: HotkeySetting.carbonFunctionMask
        )

        XCTAssertEqual(result, .save(.startStopDefault))
    }

    func testControlOptionPSaves() {
        let result = HotkeyCaptureValidator.validate(
            keyCode: 35,
            modifiers: UInt32(controlKey | optionKey)
        )

        XCTAssertEqual(result, .save(.copyDefault))
    }
}
