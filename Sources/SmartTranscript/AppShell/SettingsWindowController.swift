import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(shell: AppShell) {
        let host = NSHostingController(rootView: SettingsView().environmentObject(shell))
        let window = NSWindow(contentViewController: host)
        window.title = "SmartTranscript Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 780))
        window.contentMinSize = NSSize(width: 900, height: 720)
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
