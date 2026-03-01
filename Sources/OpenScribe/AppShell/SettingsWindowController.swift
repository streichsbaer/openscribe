import AppKit
import SwiftUI

@MainActor
final class SettingsTabState: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let minimumContentSize = NSSize(width: 700, height: 540)
    private static let defaultContentSize = NSSize(width: 760, height: 580)
    private let tabState = SettingsTabState()

    init(shell: AppShell) {
        let host = NSHostingController(rootView: SettingsView()
            .environmentObject(shell)
            .environmentObject(tabState))
        let window = NSWindow(contentViewController: host)
        window.title = "OpenScribe Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.defaultContentSize)
        window.contentMinSize = Self.minimumContentSize
        window.isReleasedWhenClosed = false
        super.init(window: window)

        host.rootView = SettingsView { [weak self] size, animated in
            self?.resize(to: NSSize(width: size.width, height: size.height), animated: animated)
        }
        .environmentObject(shell)
        .environmentObject(tabState)
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

    func selectTab(_ tab: SettingsTab) {
        tabState.selectedTab = tab
    }

    private func resize(to contentSize: NSSize, animated: Bool) {
        guard let window else {
            return
        }

        let targetContentSize = NSSize(
            width: max(Self.minimumContentSize.width, contentSize.width),
            height: max(Self.minimumContentSize.height, contentSize.height)
        )

        let frameRect = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))
        var newFrame = window.frame
        newFrame.origin.y += newFrame.height - frameRect.height
        newFrame.size = frameRect.size

        if animated {
            window.animator().setFrame(newFrame, display: true)
        } else {
            window.setFrame(newFrame, display: true)
        }
    }
}
