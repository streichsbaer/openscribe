import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let shell = AppShell()
    private let uiSmokeModeEnabled = ProcessInfo.processInfo.environment["OPENSCRIBE_UI_SMOKE"] == "1"

    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(shell: shell)
        shell.applyInitialAppearanceModeAfterLaunch()
        let shouldAutoPresentSetupAssistant = shell.shouldAutoPresentSetupAssistantOnLaunch && !uiSmokeModeEnabled

        if shouldAutoPresentSetupAssistant {
            statusBarController?.showSetupAssistantOnLaunch()
        }

        if shell.settings.transcriptionProviderID == "whispercpp",
           !shell.shouldDeferDefaultModelDownloadForSetupAssistant,
           !uiSmokeModeEnabled {
            shell.downloadDefaultModelIfNeeded()
        }

        if uiSmokeModeEnabled {
            statusBarController?.runUISmokeCaptureIfConfigured()
        }
    }

    func openSettingsWindow() {
        statusBarController?.openSettingsFromShortcut()
    }
}
