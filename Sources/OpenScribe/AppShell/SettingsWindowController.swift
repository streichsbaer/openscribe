import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class SettingsTabState: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

@MainActor
final class SetupAssistantWindowState: ObservableObject {
    @Published var isPresented = false
    @Published var selectedTrack: SetupAssistantTrack = .recommended
    @Published var selectedLocalModel = SetupAssistantChecklist.defaultLocalModelID
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let minimumContentSize = NSSize(width: 760, height: 540)
    private static let defaultContentSize = NSSize(width: 760, height: 580)
    private let tabState = SettingsTabState()
    private let setupAssistantState = SetupAssistantWindowState()

    init(shell: AppShell) {
        setupAssistantState.selectedTrack = shell.setupAssistantPreferredTrack
        if SetupAssistantChecklist.localModelOptions.contains(where: { $0.id == shell.settings.transcriptionModel }) {
            setupAssistantState.selectedLocalModel = shell.settings.transcriptionModel
        }
        let host = NSHostingController(rootView: SettingsView()
            .environmentObject(shell)
            .environmentObject(tabState)
            .environmentObject(setupAssistantState))
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
        .environmentObject(setupAssistantState)
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

    func showSetupAssistant(track: SetupAssistantTrack? = nil) {
        if let track {
            setupAssistantState.selectedTrack = track
        }
        tabState.selectedTab = .general
        show()
        setupAssistantState.isPresented = true
    }

    func moveToPreferredCaptureScreen() {
        guard let window,
              let screen = Self.preferredCaptureScreen() else {
            return
        }

        let visibleFrame = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        var frame = window.frame
        frame.origin.x = visibleFrame.midX - (frame.width / 2)
        frame.origin.y = visibleFrame.midY - (frame.height / 2)
        window.setFrame(frame, display: true)
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

    private static func preferredCaptureScreen() -> NSScreen? {
        let screens = NSScreen.screens
        return screens.first(where: \.isBuiltInRetinaDisplay)
            ?? screens
                .filter { $0.backingScaleFactor > 1 }
                .max(by: { $0.backingScaleFactor < $1.backingScaleFactor })
            ?? NSScreen.main
            ?? screens.first
    }
}

private extension NSScreen {
    var isBuiltInRetinaDisplay: Bool {
        guard backingScaleFactor > 1,
              let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }
}
