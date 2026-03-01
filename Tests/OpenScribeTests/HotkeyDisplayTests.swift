import XCTest
@testable import OpenScribe

final class HotkeyDisplayTests: XCTestCase {
    func testStartStopDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .startStopDefault), "Fn+Space")
    }

    func testCopyDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .copyDefault), "Ctrl+Option+P")
    }

    func testCopyRawDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .copyRawDefault), "Ctrl+Option+R")
    }

    func testPasteDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .pasteDefault), "Ctrl+Option+V")
    }

    func testTogglePopoverDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .togglePopoverDefault), "Ctrl+Option+O")
    }

    func testOpenSettingsDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .openSettingsDefault), "Ctrl+Option+,")
    }
}
