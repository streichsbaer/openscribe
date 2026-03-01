import Carbon
import Foundation
import XCTest
@testable import OpenScribe

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testPersistsHotkeyChanges() throws {
        let layout = try makeTempLayout()
        let store = SettingsStore(layout: layout)

        let updatedCopy = HotkeySetting(keyCode: 12, modifiers: UInt32(controlKey | optionKey))
        let updatedRawCopy = HotkeySetting(keyCode: 15, modifiers: UInt32(controlKey | optionKey))
        let updatedPaste = HotkeySetting(keyCode: 13, modifiers: UInt32(controlKey | optionKey))
        store.update {
            $0.copyHotkey = updatedCopy
            $0.copyRawHotkey = updatedRawCopy
            $0.pasteHotkey = updatedPaste
        }

        let reloaded = SettingsStore(layout: layout)
        XCTAssertEqual(reloaded.settings.copyHotkey, updatedCopy)
        XCTAssertEqual(reloaded.settings.copyRawHotkey, updatedRawCopy)
        XCTAssertEqual(reloaded.settings.pasteHotkey, updatedPaste)
    }

    private func makeTempLayout() throws -> DirectoryLayout {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OpenScribeSettingsTests-\(UUID().uuidString)", isDirectory: true)

        let layout = DirectoryLayout(
            appSupport: root,
            recordings: root.appendingPathComponent("Recordings", isDirectory: true),
            rules: root.appendingPathComponent("Rules", isDirectory: true),
            models: root.appendingPathComponent("Models/whisper", isDirectory: true),
            config: root.appendingPathComponent("Config", isDirectory: true),
            rulesFile: root.appendingPathComponent("Rules/rules.md"),
            rulesHistory: root.appendingPathComponent("Rules/rules.history.jsonl"),
            settingsFile: root.appendingPathComponent("Config/settings.json")
        )

        try layout.ensureExists()
        return layout
    }
}
