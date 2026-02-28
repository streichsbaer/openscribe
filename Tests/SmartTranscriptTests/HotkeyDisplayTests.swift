import XCTest
@testable import SmartTranscript

final class HotkeyDisplayTests: XCTestCase {
    func testStartStopDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .startStopDefault), "Fn+Space")
    }

    func testCopyDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .copyDefault), "Ctrl+Option+V")
    }
}
