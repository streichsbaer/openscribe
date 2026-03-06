import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private static let popoverVerticalMargin: CGFloat = 64
    private static let popoverMaxHeightFraction: CGFloat = 0.88
    private static let popoverMinHeight: CGFloat = 420
    // Popover uses a single live size -- no compact/expanded modes.
    private enum MicIconState {
        case idle
        case working
        case paused
        case noAudio
        case transcribing
        case polishing
    }

    private struct PopoverLayoutMetrics {
        let frameWidth: CGFloat
        let frameHeight: CGFloat
        let windowWidth: CGFloat
        let windowHeight: CGFloat
        let hostWidth: CGFloat
        let hostHeight: CGFloat
        let hostOriginY: CGFloat
        let hostFittingHeight: CGFloat

        var hostVerticalSlack: CGFloat {
            max(0, hostHeight - hostFittingHeight)
        }

        var topInset: CGFloat {
            max(0, hostOriginY)
        }

        var bottomInset: CGFloat {
            max(0, windowHeight - (hostOriginY + hostHeight))
        }

        var debugString: String {
            String(
                format: "frame=%dx%d window=%dx%d host=%dx%d y=%d fitting=%d slack=%d insetTop=%d insetBottom=%d",
                Int(frameWidth),
                Int(frameHeight),
                Int(windowWidth),
                Int(windowHeight),
                Int(hostWidth),
                Int(hostHeight),
                Int(hostOriginY),
                Int(hostFittingHeight),
                Int(hostVerticalSlack),
                Int(topInset),
                Int(bottomInset)
            )
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let shell: AppShell
    private let settingsWindowController: SettingsWindowController
    private var cancellables = Set<AnyCancellable>()
    private var blinkTimer: Timer?
    private var blinkPhase = false
    private var iconState: MicIconState = .idle
    private var currentMeterLevel: Float = 0
    private var smoothedMeterLevel: Float = 0
    private var currentSessionState: SessionState = .idle
    private var currentPermissionState: MicrophonePermissionState = .undetermined
    private var lastDetectedActivityAt: Date?
    private var noiseFloor: Float = 0.005
    private var activityThreshold: Float = 0.020
    private var instantActivityThreshold: Float = 0.012
    private var currentAppearanceMode: AppearanceMode = .system

    private let smoothingAlpha: Float = 0.22
    private let noiseFloorAlpha: Float = 0.08
    private let minNoiseFloor: Float = 0.005
    private let maxNoiseFloor: Float = 0.060
    private let activityFloor: Float = 0.020
    private let activityNoiseMultiplier: Float = 2.2
    private let activityHoldSeconds: TimeInterval = 0.35
    private let noAudioTimeoutSeconds: TimeInterval = 1.4

    init(shell: AppShell) {
        self.shell = shell
        self.settingsWindowController = SettingsWindowController(shell: shell)
        super.init()
        shell.openSettingsWindowHandler = { [weak self] in
            self?.openSettings()
        }
        shell.openRulesWindowHandler = { [weak self] in
            self?.openRulesSettings()
        }
        shell.togglePopoverHandler = { [weak self] in
            self?.togglePopoverFromHotkey()
        }
        shell.showPopoverHandler = { [weak self] in
            self?.showPopoverFromHotkey()
        }
        shell.updatePopoverSizeHandler = { [weak self] size in
            self?.updatePopoverSize(size)
        }
        currentAppearanceMode = AppearanceMode(rawValue: shell.settings.appearanceMode) ?? .system
        configureStatusItem()
        configurePopover()
        applyAppearanceSettings()
        bindShellState()
        startBlinkTimer()
        updateIconAppearance()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.autoenablesItems = false

            let settingsItem = NSMenuItem(
                title: "Settings",
                action: #selector(openSettings),
                keyEquivalent: ","
            )
            settingsItem.target = self
            settingsItem.isEnabled = true
            menu.addItem(settingsItem)

            menu.addItem(.separator())

            let quitItem = NSMenuItem(
                title: "Quit OpenScribe",
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
            quitItem.target = self
            quitItem.isEnabled = true
            menu.addItem(quitItem)

            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }

        togglePopover(sender)
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func openRulesSettings() {
        settingsWindowController.selectTab(.rules)
        settingsWindowController.show()
    }

    func openSettingsFromShortcut() {
        openSettings()
    }

    func togglePopoverFromHotkey() {
        guard let button = statusItem.button else {
            return
        }
        togglePopover(button)
    }

    func showPopoverFromHotkey() {
        guard let button = statusItem.button else {
            return
        }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            updatePopoverSize(shell.preferredPopoverSizeForCurrentState())
            return
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func runUISmokeCaptureIfConfigured() {
        guard let outputPath = ProcessInfo.processInfo.environment["OPENSCRIBE_UI_SMOKE_OUT"],
              !outputPath.isEmpty else {
            return
        }

        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await runUISmokeCapture(outputDirectory: outputDirectory)
            NSApp.terminate(nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func runUISmokeCapture(outputDirectory: URL) async {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(nanoseconds: 500_000_000)

        let popoverImageURL = outputDirectory.appendingPathComponent("openscribe-window.png")
        let directHotkeyHistoryImageURL = outputDirectory.appendingPathComponent("openscribe-window-hotkey-history-direct.png")
        let clickHistoryImageURL = outputDirectory.appendingPathComponent("openscribe-window-click-history.png")
        let clickHistoryWindowImageURL = outputDirectory.appendingPathComponent("openscribe-window-click-history-full.png")
        let clickStatsImageURL = outputDirectory.appendingPathComponent("openscribe-window-click-stats.png")
        let hotkeyHistoryImageURL = outputDirectory.appendingPathComponent("openscribe-window-hotkey-history.png")
        let hotkeyHistoryWindowImageURL = outputDirectory.appendingPathComponent("openscribe-window-hotkey-history-full.png")
        let hotkeyStatsImageURL = outputDirectory.appendingPathComponent("openscribe-window-hotkey-stats.png")
        let hotkeyLiveImageURL = outputDirectory.appendingPathComponent("openscribe-window-hotkey-live.png")
        let liveExpandedContentImageURL = outputDirectory.appendingPathComponent("openscribe-window-live-expanded-content.png")
        let settingsImageURL = outputDirectory.appendingPathComponent("settings-window.png")
        let debugURL = outputDirectory.appendingPathComponent("ui-smoke-debug.txt")

        var popoverStatus = "fail"
        var hotkeyTabsStatus = "fail"
        var statsCaptureStatus = "fail"
        var hotkeyDispatchStatus = "pass"
        var tabClickDispatchStatus = "pass"
        var historyDirectLayoutParityStatus = "fail"
        var historyDirectLayoutParityReason = "not-evaluated"
        var historyLayoutParityStatus = "fail"
        var historyLayoutParityReason = "not-evaluated"
        var historyVerticalFillStatus = "fail"
        var historyVerticalFillReason = "not-evaluated"
        var liveExpandedContentCaptureStatus = "fail"
        var settingsStatus = "fail"
        var iconStatus = "fail"
        var debugLines: [String] = []
        debugLines.append("statusButton=\(statusItem.button != nil)")
        let originalPopoverBehavior = popover.behavior
        popover.behavior = .applicationDefined

        var hotkeyCaptureFailures = 0
        if showPopoverForUISmoke() {
            debugLines.append("popoverShown=true")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let popoverView = popover.contentViewController?.view.window?.contentView
                ?? popover.contentViewController?.view
            if let popoverView {
                let b = popoverView.bounds
                debugLines.append("popoverBounds=\(Int(b.width))x\(Int(b.height))")
            } else {
                debugLines.append("popoverBounds=missing")
            }
            if captureViewSnapshot(popoverView, to: popoverImageURL) {
                popoverStatus = "pass"
                debugLines.append("popoverCapture=pass")
            } else {
                debugLines.append("popoverCapture=fail")
            }

            let liveTabClickedForDirectHotkey = selectPopoverTabViaSegmentedControlForUISmoke(.live)
            debugLines.append("tabClickDispatch[live-direct]=\(liveTabClickedForDirectHotkey)")
            if !liveTabClickedForDirectHotkey {
                tabClickDispatchStatus = "fail"
                shell.selectPopoverTab(.live)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)

            let historyDirectHotkeyDispatched = triggerTabHotkeyForUISmoke(.history)
            debugLines.append("hotkeyDispatch[history-direct]=\(historyDirectHotkeyDispatched)")
            if !historyDirectHotkeyDispatched {
                hotkeyDispatchStatus = "fail"
                shell.showHistoryTabFromHotkey()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if shell.selectedPopoverTab != .history {
                debugLines.append("hotkeyDispatch[history-direct]-fallback=true")
                shell.showHistoryTabFromHotkey()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            let historyDirectHotkeyView = popover.contentViewController?.view.window?.contentView
                ?? popover.contentViewController?.view
            let directHotkeyHistoryMetrics = currentPopoverLayoutMetrics()
            if let directHotkeyHistoryMetrics {
                debugLines.append("popoverDirectHotkeyHistoryMetrics=\(directHotkeyHistoryMetrics.debugString)")
            } else {
                debugLines.append("popoverDirectHotkeyHistoryMetrics=missing")
            }
            if captureViewSnapshot(historyDirectHotkeyView, to: directHotkeyHistoryImageURL) {
                debugLines.append("popoverDirectHotkeyHistoryCapture=pass")
            } else {
                hotkeyCaptureFailures += 1
                debugLines.append("popoverDirectHotkeyHistoryCapture=fail")
            }

            let liveTabClickedBeforeStatsHotkey = selectPopoverTabViaSegmentedControlForUISmoke(.live)
            debugLines.append("tabClickDispatch[live-before-stats-hotkey]=\(liveTabClickedBeforeStatsHotkey)")
            if !liveTabClickedBeforeStatsHotkey {
                tabClickDispatchStatus = "fail"
                shell.selectPopoverTab(.live)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)

            let statsHotkeyDispatched = triggerTabHotkeyForUISmoke(.stats)
            debugLines.append("hotkeyDispatch[stats]=\(statsHotkeyDispatched)")
            if !statsHotkeyDispatched {
                hotkeyDispatchStatus = "fail"
                shell.showStatsTabFromHotkey()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if shell.selectedPopoverTab != .stats {
                debugLines.append("hotkeyDispatch[stats]-fallback=true")
                shell.showStatsTabFromHotkey()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            let statsHotkeyView = popover.contentViewController?.view.window?.contentView
                ?? popover.contentViewController?.view
            if captureViewSnapshot(statsHotkeyView, to: hotkeyStatsImageURL) {
                debugLines.append("popoverHotkeyStatsCapture=pass")
            } else {
                hotkeyCaptureFailures += 1
                debugLines.append("popoverHotkeyStatsCapture=fail")
            }

            let liveTabClickedAfterStatsHotkey = selectPopoverTabViaSegmentedControlForUISmoke(.live)
            debugLines.append("tabClickDispatch[live-after-stats-hotkey]=\(liveTabClickedAfterStatsHotkey)")
            if !liveTabClickedAfterStatsHotkey {
                tabClickDispatchStatus = "fail"
                shell.selectPopoverTab(.live)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)

            let liveTabClickedBeforeClickHistory = selectPopoverTabViaSegmentedControlForUISmoke(.live)
            debugLines.append("tabClickDispatch[live-before-click-history]=\(liveTabClickedBeforeClickHistory)")
            if !liveTabClickedBeforeClickHistory {
                tabClickDispatchStatus = "fail"
                shell.selectPopoverTab(.live)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            let historyTabClickedForBaseline = selectPopoverTabViaSegmentedControlForUISmoke(.history)
            debugLines.append("tabClickDispatch[history-baseline]=\(historyTabClickedForBaseline)")
            if !historyTabClickedForBaseline {
                tabClickDispatchStatus = "fail"
                shell.selectPopoverTab(.history)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            let historyClickView = popover.contentViewController?.view.window?.contentView
                ?? popover.contentViewController?.view
            let clickHistoryMetrics = currentPopoverLayoutMetrics()
            if let clickHistoryMetrics {
                debugLines.append("popoverClickHistoryMetrics=\(clickHistoryMetrics.debugString)")
            } else {
                debugLines.append("popoverClickHistoryMetrics=missing")
            }
            if captureViewSnapshot(historyClickView, to: clickHistoryImageURL) {
                debugLines.append("popoverClickHistoryCapture=pass")
            } else {
                hotkeyCaptureFailures += 1
                debugLines.append("popoverClickHistoryCapture=fail")
            }
            if captureWindowSnapshot(popover.contentViewController?.view.window, to: clickHistoryWindowImageURL) {
                debugLines.append("popoverClickHistoryWindowCapture=pass")
            } else {
                debugLines.append("popoverClickHistoryWindowCapture=fail")
            }

            let statsTabClickedForCapture = selectPopoverTabViaSegmentedControlForUISmoke(.stats)
            debugLines.append("tabClickDispatch[stats-capture]=\(statsTabClickedForCapture)")
            if !statsTabClickedForCapture {
                tabClickDispatchStatus = "fail"
                shell.selectPopoverTab(.stats)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            let statsClickView = popover.contentViewController?.view.window?.contentView
                ?? popover.contentViewController?.view
            if captureViewSnapshot(statsClickView, to: clickStatsImageURL) {
                statsCaptureStatus = "pass"
                debugLines.append("popoverClickStatsCapture=pass")
            } else {
                statsCaptureStatus = "fail"
                debugLines.append("popoverClickStatsCapture=fail")
            }

            let liveTabClickedAfterStatsCapture = selectPopoverTabViaSegmentedControlForUISmoke(.live)
            debugLines.append("tabClickDispatch[live-after-stats-capture]=\(liveTabClickedAfterStatsCapture)")
            if !liveTabClickedAfterStatsCapture {
                tabClickDispatchStatus = "fail"
                shell.selectPopoverTab(.live)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)

            if let clickHistoryMetrics, let directHotkeyHistoryMetrics {
                let directParity = evaluateHistoryLayoutParity(
                    clickMetrics: clickHistoryMetrics,
                    hotkeyMetrics: directHotkeyHistoryMetrics
                )
                historyDirectLayoutParityStatus = directParity.isMatch ? "pass" : "fail"
                historyDirectLayoutParityReason = directParity.reason
                debugLines.append("historyLayoutParityDirect=\(historyDirectLayoutParityStatus)")
                debugLines.append("historyLayoutParityDirectReason=\(historyDirectLayoutParityReason)")
            } else {
                historyDirectLayoutParityStatus = "fail"
                historyDirectLayoutParityReason = "missing-metrics"
                debugLines.append("historyLayoutParityDirect=fail")
                debugLines.append("historyLayoutParityDirectReason=missing-metrics")
            }

            let liveTabClickedBeforeHotkeyComparison = selectPopoverTabViaSegmentedControlForUISmoke(.live)
            debugLines.append("tabClickDispatch[live-before-hotkey-comparison]=\(liveTabClickedBeforeHotkeyComparison)")
            if !liveTabClickedBeforeHotkeyComparison {
                tabClickDispatchStatus = "fail"
                shell.selectPopoverTab(.live)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)

            let historyHotkeyDispatched = triggerTabHotkeyForUISmoke(.history)
            debugLines.append("hotkeyDispatch[history]=\(historyHotkeyDispatched)")
            if !historyHotkeyDispatched {
                hotkeyDispatchStatus = "fail"
                shell.showHistoryTabFromHotkey()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if shell.selectedPopoverTab != .history {
                debugLines.append("hotkeyDispatch[history]-fallback=true")
                shell.showHistoryTabFromHotkey()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            let historyHotkeyView = popover.contentViewController?.view.window?.contentView
                ?? popover.contentViewController?.view
            let hotkeyHistoryMetrics = currentPopoverLayoutMetrics()
            if let historyHotkeyView {
                let b = historyHotkeyView.bounds
                debugLines.append("popoverHotkeyHistoryBounds=\(Int(b.width))x\(Int(b.height))")
            } else {
                debugLines.append("popoverHotkeyHistoryBounds=missing")
            }
            if let hotkeyHistoryMetrics {
                debugLines.append("popoverHotkeyHistoryMetrics=\(hotkeyHistoryMetrics.debugString)")
            } else {
                debugLines.append("popoverHotkeyHistoryMetrics=missing")
            }
            if captureViewSnapshot(historyHotkeyView, to: hotkeyHistoryImageURL) {
                debugLines.append("popoverHotkeyHistoryCapture=pass")
            } else {
                hotkeyCaptureFailures += 1
                debugLines.append("popoverHotkeyHistoryCapture=fail")
            }
            if captureWindowSnapshot(popover.contentViewController?.view.window, to: hotkeyHistoryWindowImageURL) {
                debugLines.append("popoverHotkeyHistoryWindowCapture=pass")
            } else {
                debugLines.append("popoverHotkeyHistoryWindowCapture=fail")
            }

            if let clickHistoryMetrics, let hotkeyHistoryMetrics {
                let parity = evaluateHistoryLayoutParity(
                    clickMetrics: clickHistoryMetrics,
                    hotkeyMetrics: hotkeyHistoryMetrics
                )
                historyLayoutParityStatus = parity.isMatch ? "pass" : "fail"
                historyLayoutParityReason = parity.reason
                debugLines.append("historyLayoutParity=\(historyLayoutParityStatus)")
                debugLines.append("historyLayoutParityReason=\(historyLayoutParityReason)")

                let clickFill = evaluateHistoryVerticalFill(clickHistoryMetrics)
                let hotkeyFill = evaluateHistoryVerticalFill(hotkeyHistoryMetrics)
                if clickFill.isMatch, hotkeyFill.isMatch {
                    historyVerticalFillStatus = "pass"
                    historyVerticalFillReason = "ok"
                } else {
                    historyVerticalFillStatus = "fail"
                    historyVerticalFillReason = "click=\(clickFill.reason);hotkey=\(hotkeyFill.reason)"
                }
                debugLines.append("historyVerticalFill=\(historyVerticalFillStatus)")
                debugLines.append("historyVerticalFillReason=\(historyVerticalFillReason)")
            } else {
                historyLayoutParityStatus = "fail"
                historyLayoutParityReason = "missing-metrics"
                debugLines.append("historyLayoutParity=fail")
                debugLines.append("historyLayoutParityReason=missing-metrics")
                historyVerticalFillStatus = "fail"
                historyVerticalFillReason = "missing-metrics"
                debugLines.append("historyVerticalFill=fail")
                debugLines.append("historyVerticalFillReason=missing-metrics")
            }

            let liveHotkeyDispatched = triggerTabHotkeyForUISmoke(.live)
            debugLines.append("hotkeyDispatch[live]=\(liveHotkeyDispatched)")
            if !liveHotkeyDispatched {
                hotkeyDispatchStatus = "fail"
                shell.showLiveTabFromHotkey()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if shell.selectedPopoverTab != .live {
                debugLines.append("hotkeyDispatch[live]-fallback=true")
                shell.showLiveTabFromHotkey()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            let liveHotkeyView = popover.contentViewController?.view.window?.contentView
                ?? popover.contentViewController?.view
            if let liveHotkeyView {
                let b = liveHotkeyView.bounds
                debugLines.append("popoverHotkeyLiveBounds=\(Int(b.width))x\(Int(b.height))")
            } else {
                debugLines.append("popoverHotkeyLiveBounds=missing")
            }
            if captureViewSnapshot(liveHotkeyView, to: hotkeyLiveImageURL) {
                debugLines.append("popoverHotkeyLiveCapture=pass")
            } else {
                hotkeyCaptureFailures += 1
                debugLines.append("popoverHotkeyLiveCapture=fail")
            }

            let sampleText = "Smoke sample: transcript content should remain scrollable and never overlap controls."
            shell.rawTranscript = sampleText + " Raw."
            shell.polishedTranscript = sampleText + " Polished."
            shell.rawTranscriptProviderID = "groq_whisper"
            shell.rawTranscriptModel = "whisper-large-v3-turbo"
            shell.polishedTranscriptProviderID = "gemini_polish"
            shell.polishedTranscriptModel = "gemini-2.5-flash-lite"
            shell.selectPopoverTab(.live)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let liveContentView = popover.contentViewController?.view.window?.contentView
                ?? popover.contentViewController?.view
            let liveContentMetrics = currentPopoverLayoutMetrics()
            if let liveContentMetrics {
                debugLines.append("popoverLiveContentMetrics=\(liveContentMetrics.debugString)")
            } else {
                debugLines.append("popoverLiveContentMetrics=missing")
            }
            if captureViewSnapshot(liveContentView, to: liveExpandedContentImageURL) {
                liveExpandedContentCaptureStatus = "pass"
                debugLines.append("popoverLiveContentCapture=pass")
            } else {
                liveExpandedContentCaptureStatus = "fail"
                debugLines.append("popoverLiveContentCapture=fail")
            }
        } else {
            hotkeyCaptureFailures = 3
            historyLayoutParityStatus = "fail"
            historyLayoutParityReason = "popover-not-shown"
            liveExpandedContentCaptureStatus = "fail"
            statsCaptureStatus = "fail"
            debugLines.append("popoverShown=false")
        }
        hotkeyTabsStatus = hotkeyCaptureFailures == 0 ? "pass" : "missing:\(hotkeyCaptureFailures)"

        openSettings()
        settingsWindowController.moveToPreferredCaptureScreen()
        try? await Task.sleep(nanoseconds: 700_000_000)
        if let settingsView = settingsWindowController.window?.contentView {
            let b = settingsView.bounds
            debugLines.append("settingsBounds=\(Int(b.width))x\(Int(b.height))")
        } else {
            debugLines.append("settingsBounds=missing")
        }
        if let screen = settingsWindowController.window?.screen {
            debugLines.append("settingsCaptureScreen=\(screen.localizedName)@\(screen.backingScaleFactor)x")
        } else {
            debugLines.append("settingsCaptureScreen=missing")
        }
        if captureViewSnapshot(settingsWindowController.window?.contentView, to: settingsImageURL) {
            settingsStatus = "pass"
            debugLines.append("settingsCapture=pass")
        } else {
            debugLines.append("settingsCapture=fail")
        }

        var tabCaptureFailures = 0
        for tab in SettingsTab.allCases {
            settingsWindowController.selectTab(tab)
            try? await Task.sleep(nanoseconds: 500_000_000)
            settingsWindowController.moveToPreferredCaptureScreen()
            let tabURL = outputDirectory.appendingPathComponent("settings-\(tab.rawValue).png")
            if captureViewSnapshot(settingsWindowController.window?.contentView, to: tabURL) {
                debugLines.append("settingsTab[\(tab.rawValue)]=pass")
            } else {
                tabCaptureFailures += 1
                debugLines.append("settingsTab[\(tab.rawValue)]=fail")
            }
        }
        if tabCaptureFailures > 0 {
            settingsStatus = "partial"
        }

        let iconCaptureFailures = captureMenubarIconSnapshots(outputDirectory: outputDirectory, debugLines: &debugLines)
        iconStatus = iconCaptureFailures == 0 ? "pass" : "missing:\(iconCaptureFailures)"

        popover.behavior = originalPopoverBehavior

        let summary = """
        popover=\(popoverStatus)
        hotkeyPopoverTabs=\(hotkeyTabsStatus)
        hotkeyPopoverTabsFailed=\(hotkeyCaptureFailures)
        hotkeyDispatch=\(hotkeyDispatchStatus)
        tabClickDispatch=\(tabClickDispatchStatus)
        statsCapture=\(statsCaptureStatus)
        historyLayoutParityDirect=\(historyDirectLayoutParityStatus)
        historyLayoutParityDirectReason=\(historyDirectLayoutParityReason)
        historyLayoutParity=\(historyLayoutParityStatus)
        historyLayoutParityReason=\(historyLayoutParityReason)
        historyVerticalFill=\(historyVerticalFillStatus)
        historyVerticalFillReason=\(historyVerticalFillReason)
        liveExpandedContentCapture=\(liveExpandedContentCaptureStatus)
        settings=\(settingsStatus)
        settingsTabsFailed=\(tabCaptureFailures)
        menubarIcons=\(iconStatus)
        menubarIconsFailed=\(iconCaptureFailures)
        """
        try? summary.write(
            to: outputDirectory.appendingPathComponent("ui-smoke-status.txt"),
            atomically: true,
            encoding: .utf8
        )
        try? debugLines.joined(separator: "\n").write(
            to: debugURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private func captureMenubarIconSnapshots(outputDirectory: URL, debugLines: inout [String]) -> Int {
        let appearanceModes: [(fileTag: String, mode: AppearanceMode)] = [
            ("system", .system),
            ("light", .light),
            ("dark", .dark)
        ]
        let iconStates: [(fileTag: String, state: MicIconState, blink: Bool)] = [
            ("idle", .idle, false),
            ("recording-working", .working, true),
            ("recording-paused", .paused, false),
            ("recording-no-audio", .noAudio, true),
            ("transcribing", .transcribing, true),
            ("polishing", .polishing, true)
        ]

        let originalMode = currentAppearanceMode
        var failures = 0

        for appearance in appearanceModes {
            currentAppearanceMode = appearance.mode
            applyAppearanceSettings()

            for icon in iconStates {
                let fileURL = outputDirectory.appendingPathComponent("menubar-icon-\(appearance.fileTag)-\(icon.fileTag).png")
                guard let image = drawStatusIcon(for: icon.state, blinkPhase: icon.blink) else {
                    failures += 1
                    debugLines.append("menubarIcon[\(appearance.fileTag)/\(icon.fileTag)]=draw-fail")
                    continue
                }

                if writeMenubarIconPreview(image, to: fileURL) {
                    debugLines.append("menubarIcon[\(appearance.fileTag)/\(icon.fileTag)]=pass")
                } else {
                    failures += 1
                    debugLines.append("menubarIcon[\(appearance.fileTag)/\(icon.fileTag)]=write-fail")
                }
            }
        }

        currentAppearanceMode = originalMode
        applyAppearanceSettings()
        return failures
    }

    private func writeMenubarIconPreview(_ iconImage: NSImage, to outputURL: URL) -> Bool {
        let canvasSide: CGFloat = 72
        let iconSide: CGFloat = 54
        let preview = NSImage(size: NSSize(width: canvasSide, height: canvasSide))
        preview.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasSide, height: canvasSide)).fill()

        let iconRect = NSRect(
            x: (canvasSide - iconSide) / 2,
            y: (canvasSide - iconSide) / 2,
            width: iconSide,
            height: iconSide
        )
        iconImage.draw(
            in: iconRect,
            from: NSRect(origin: .zero, size: iconImage.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        preview.unlockFocus()

        guard let tiff = preview.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return false
        }

        do {
            try pngData.write(to: outputURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func showPopoverForUISmoke() -> Bool {
        guard let button = statusItem.button else {
            return false
        }

        if !popover.isShown {
            togglePopover(button)
        }
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        return popover.isShown
    }

    private func captureViewSnapshot(_ view: NSView?, to outputURL: URL) -> Bool {
        guard let view else {
            return false
        }

        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bounds = view.bounds.integral
        guard bounds.width > 0, bounds.height > 0 else {
            return false
        }

        let scale = max(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1, 1)
        let pixelWidth = max(Int(ceil(bounds.width * scale)), 1)
        let pixelHeight = max(Int(ceil(bounds.height * scale)), 1)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return false
        }
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        do {
            try pngData.write(to: outputURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func captureWindowSnapshot(_ window: NSWindow?, to outputURL: URL) -> Bool {
        guard let window,
              let frameView = window.contentView?.superview else {
            return false
        }

        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        let bounds = frameView.bounds.integral
        guard bounds.width > 0, bounds.height > 0 else {
            return false
        }

        let scale = max(window.backingScaleFactor, 1)
        let pixelWidth = max(Int(ceil(bounds.width * scale)), 1)
        let pixelHeight = max(Int(ceil(bounds.height * scale)), 1)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return false
        }
        bitmap.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        do {
            try pngData.write(to: outputURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func currentPopoverLayoutMetrics() -> PopoverLayoutMetrics? {
        guard let window = popover.contentViewController?.view.window,
              let windowContentView = window.contentView,
              let hostView = popover.contentViewController?.view else {
            return nil
        }

        windowContentView.layoutSubtreeIfNeeded()
        hostView.layoutSubtreeIfNeeded()

        let windowBounds = windowContentView.bounds.integral
        let hostBounds = hostView.bounds.integral
        let hostFrame = hostView.frame.integral
        let fitting = hostView.fittingSize

        guard windowBounds.width > 0,
              windowBounds.height > 0,
              hostBounds.width > 0,
              hostBounds.height > 0 else {
            return nil
        }

        return PopoverLayoutMetrics(
            frameWidth: window.frame.width,
            frameHeight: window.frame.height,
            windowWidth: windowBounds.width,
            windowHeight: windowBounds.height,
            hostWidth: hostBounds.width,
            hostHeight: hostBounds.height,
            hostOriginY: hostFrame.origin.y,
            hostFittingHeight: fitting.height
        )
    }

    private func evaluateHistoryLayoutParity(
        clickMetrics: PopoverLayoutMetrics,
        hotkeyMetrics: PopoverLayoutMetrics
    ) -> (isMatch: Bool, reason: String) {
        let tolerance: CGFloat = 1
        let frameHeightDelta = abs(clickMetrics.frameHeight - hotkeyMetrics.frameHeight)
        let windowHeightDelta = abs(clickMetrics.windowHeight - hotkeyMetrics.windowHeight)
        let hostHeightDelta = abs(clickMetrics.hostHeight - hotkeyMetrics.hostHeight)
        let slackDelta = abs(clickMetrics.hostVerticalSlack - hotkeyMetrics.hostVerticalSlack)
        let topInsetDelta = abs(clickMetrics.topInset - hotkeyMetrics.topInset)
        let bottomInsetDelta = abs(clickMetrics.bottomInset - hotkeyMetrics.bottomInset)

        guard frameHeightDelta <= tolerance else {
            return (
                false,
                "frame-height mismatch click=\(Int(clickMetrics.frameHeight)) hotkey=\(Int(hotkeyMetrics.frameHeight))"
            )
        }
        guard windowHeightDelta <= tolerance else {
            return (
                false,
                "window-height mismatch click=\(Int(clickMetrics.windowHeight)) hotkey=\(Int(hotkeyMetrics.windowHeight))"
            )
        }
        guard hostHeightDelta <= tolerance else {
            return (
                false,
                "host-height mismatch click=\(Int(clickMetrics.hostHeight)) hotkey=\(Int(hotkeyMetrics.hostHeight))"
            )
        }
        guard slackDelta <= tolerance else {
            return (
                false,
                "host-slack mismatch click=\(Int(clickMetrics.hostVerticalSlack)) hotkey=\(Int(hotkeyMetrics.hostVerticalSlack))"
            )
        }
        guard topInsetDelta <= tolerance else {
            return (
                false,
                "top-inset mismatch click=\(Int(clickMetrics.topInset)) hotkey=\(Int(hotkeyMetrics.topInset))"
            )
        }
        guard bottomInsetDelta <= tolerance else {
            return (
                false,
                "bottom-inset mismatch click=\(Int(clickMetrics.bottomInset)) hotkey=\(Int(hotkeyMetrics.bottomInset))"
            )
        }
        return (true, "ok")
    }

    private func evaluateHistoryVerticalFill(_ metrics: PopoverLayoutMetrics) -> (isMatch: Bool, reason: String) {
        let maxAllowedSlack: CGFloat = 48
        guard metrics.hostVerticalSlack <= maxAllowedSlack else {
            return (false, "excess-slack=\(Int(metrics.hostVerticalSlack))")
        }
        return (true, "ok")
    }

    private func selectPopoverTabViaSegmentedControlForUISmoke(_ tab: PopoverTabSelection) -> Bool {
        let rootView = popover.contentViewController?.view.window?.contentView
            ?? popover.contentViewController?.view
        guard let rootView,
              let control = findPopoverTabSegmentedControl(in: rootView) else {
            return false
        }

        let targetLabel: String
        switch tab {
        case .live:
            targetLabel = "live"
        case .history:
            targetLabel = "history"
        case .stats:
            targetLabel = "stats"
        }
        let targetIndex = (0..<control.segmentCount).first { index in
            (control.label(forSegment: index) ?? "").lowercased() == targetLabel
        }
        guard let targetIndex else {
            return false
        }

        control.selectedSegment = targetIndex
        control.sendAction(control.action, to: control.target)
        return true
    }

    private func findPopoverTabSegmentedControl(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl, control.segmentCount >= 2 {
            let labels = (0..<control.segmentCount)
                .map { (control.label(forSegment: $0) ?? "").lowercased() }
            if labels.contains("live"), labels.contains("history") {
                return control
            }
        }

        for child in view.subviews {
            if let found = findPopoverTabSegmentedControl(in: child) {
                return found
            }
        }
        return nil
    }

    private func triggerTabHotkeyForUISmoke(_ tab: PopoverTabSelection) -> Bool {
        let keyCode: CGKeyCode
        switch tab {
        case .live:
            keyCode = 37 // ANSI L
        case .history:
            keyCode = 4 // ANSI H
        case .stats:
            keyCode = 1 // ANSI S
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        setStatusIcon(for: .idle, blinkPhase: blinkPhase)
        button.imagePosition = .imageOnly
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 540, height: 700)
        popover.contentViewController = NSHostingController(rootView: PopoverView().environmentObject(shell))
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            updatePopoverSize(shell.preferredPopoverSizeForCurrentState())
        }
    }

    private func updatePopoverSize(_ size: CGSize) {
        let requested = NSSize(width: size.width, height: size.height)
        let target = NSSize(
            width: requested.width,
            height: min(requested.height, maxPopoverHeight())
        )
        popover.contentSize = target
        popover.contentViewController?.view.frame.size = target
        popover.contentViewController?.view.layoutSubtreeIfNeeded()
        if popover.isShown {
            popover.contentViewController?.view.window?.setContentSize(target)
        }
    }

    private func maxPopoverHeight() -> CGFloat {
        if let window = popover.contentViewController?.view.window,
           let screen = window.screen {
            return cappedPopoverHeight(for: screen)
        }
        if let buttonScreen = statusItem.button?.window?.screen {
            return cappedPopoverHeight(for: buttonScreen)
        }
        if let mainScreen = NSScreen.main {
            return cappedPopoverHeight(for: mainScreen)
        }
        return 900
    }

    private func cappedPopoverHeight(for screen: NSScreen) -> CGFloat {
        let visibleHeight = screen.visibleFrame.height
        let marginCap = visibleHeight - Self.popoverVerticalMargin
        let fractionCap = visibleHeight * Self.popoverMaxHeightFraction
        return max(Self.popoverMinHeight, min(marginCap, fractionCap))
    }

    private func bindShellState() {
        shell.$meterLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                guard let self else { return }
                currentMeterLevel = level
                smoothedMeterLevel = (smoothedMeterLevel == 0)
                    ? level
                    : ((1 - smoothingAlpha) * smoothedMeterLevel + smoothingAlpha * level)

                if currentSessionState == .recording {
                    updateNoiseFloor(using: smoothedMeterLevel)
                    if currentMeterLevel >= instantActivityThreshold || smoothedMeterLevel >= activityThreshold {
                        lastDetectedActivityAt = Date()
                    }
                }
                reevaluateMicIconState()
            }
            .store(in: &cancellables)

        shell.$sessionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if currentSessionState != .recording, state == .recording {
                    lastDetectedActivityAt = Date()
                    smoothedMeterLevel = 0
                    noiseFloor = minNoiseFloor
                    activityThreshold = activityFloor
                    instantActivityThreshold = 0.012
                } else if state != .recording {
                    lastDetectedActivityAt = nil
                    smoothedMeterLevel = 0
                    noiseFloor = minNoiseFloor
                    activityThreshold = activityFloor
                    instantActivityThreshold = 0.012
                }
                currentSessionState = state
                reevaluateMicIconState()
            }
            .store(in: &cancellables)

        shell.$permissionState
            .receive(on: RunLoop.main)
            .sink { [weak self] permission in
                guard let self else { return }
                currentPermissionState = permission
                reevaluateMicIconState()
            }
            .store(in: &cancellables)

        shell.settingsStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] settings in
                guard let self else { return }
                currentAppearanceMode = AppearanceMode(rawValue: settings.appearanceMode) ?? .system
                applyAppearanceSettings()
                reevaluateMicIconState()
            }
            .store(in: &cancellables)
    }

    private func startBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = Timer(timeInterval: 0.45, target: self, selector: #selector(handleBlinkTimerTick), userInfo: nil, repeats: true)
        if let blinkTimer {
            RunLoop.main.add(blinkTimer, forMode: .common)
        }
    }

    @objc private func handleBlinkTimerTick() {
        blinkPhase.toggle()
        reevaluateMicIconState()
    }

    private func reevaluateMicIconState() {
        var silenceDuration: TimeInterval = 0
        switch currentSessionState {
        case .recording:
            if currentPermissionState != .authorized {
                iconState = .noAudio
                updateIconAppearance()
                publishDebug(silenceDuration: silenceDuration)
                return
            }

            silenceDuration = Date().timeIntervalSince(lastDetectedActivityAt ?? .distantPast)
            if silenceDuration <= activityHoldSeconds {
                iconState = .working
                updateIconAppearance()
                publishDebug(silenceDuration: silenceDuration)
                return
            }

            iconState = silenceDuration >= noAudioTimeoutSeconds ? .noAudio : .paused
        case .finalizingAudio, .transcribing:
            iconState = .transcribing
        case .polishing:
            iconState = .polishing
        case .idle, .completed, .failed:
            iconState = .idle
        }
        updateIconAppearance()
        publishDebug(silenceDuration: silenceDuration)
    }

    private func updateIconAppearance() {
        setStatusIcon(for: iconState, blinkPhase: blinkPhase)
    }

    private func setStatusIcon(for state: MicIconState, blinkPhase: Bool) {
        guard let button = statusItem.button else {
            return
        }

        guard let image = drawStatusIcon(for: state, blinkPhase: blinkPhase) else {
            button.image = nil
            button.title = "ST"
            return
        }

        button.image = image
        button.contentTintColor = nil
        button.title = ""
    }

    private func drawStatusIcon(for state: MicIconState, blinkPhase: Bool) -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: size).insetBy(dx: 1.25, dy: 1.25)
        let strokeAlpha: CGFloat
        let fillAlpha: CGFloat
        let barAlpha: CGFloat
        let barProfile: [CGFloat]
        let drawSlash: Bool

        switch state {
        case .idle:
            strokeAlpha = 0.90
            fillAlpha = 0.08
            barAlpha = 0.75
            barProfile = [0.24, 0.42, 0.24]
            drawSlash = false
        case .working:
            strokeAlpha = 1.00
            fillAlpha = 0.14
            barAlpha = 1.00
            barProfile = blinkPhase ? [0.55, 0.90, 0.65] : [0.40, 0.70, 0.50]
            drawSlash = false
        case .paused:
            strokeAlpha = blinkPhase ? 1.00 : 0.70
            fillAlpha = 0.12
            barAlpha = blinkPhase ? 0.96 : 0.58
            barProfile = [0.22, 0.52, 0.22]
            drawSlash = false
        case .noAudio:
            strokeAlpha = 1.00
            fillAlpha = 0.14
            barAlpha = 0.80
            barProfile = [0.22, 0.22, 0.22]
            drawSlash = true
        case .transcribing:
            strokeAlpha = 1.00
            fillAlpha = 0.13
            barAlpha = 0.96
            barProfile = blinkPhase ? [0.30, 0.88, 0.45] : [0.55, 0.36, 0.82]
            drawSlash = false
        case .polishing:
            strokeAlpha = 1.00
            fillAlpha = 0.13
            barAlpha = 0.96
            barProfile = blinkPhase ? [0.82, 0.42, 0.64] : [0.38, 0.86, 0.48]
            drawSlash = false
        }

        let baseColor = iconBaseColor(for: state, blinkPhase: blinkPhase)
        baseColor.withAlphaComponent(fillAlpha).setFill()
        let outerCircle = NSBezierPath(ovalIn: bounds)
        outerCircle.fill()

        baseColor.withAlphaComponent(strokeAlpha).setStroke()
        outerCircle.lineWidth = 1.3
        outerCircle.stroke()

        let innerRect = bounds.insetBy(dx: 4.3, dy: 4.1)
        let barCount = max(1, barProfile.count)
        let spacing: CGFloat = 1.4
        let totalSpacing = spacing * CGFloat(max(0, barCount - 1))
        let barWidth = max(1.6, (innerRect.width - totalSpacing) / CGFloat(barCount))

        baseColor.withAlphaComponent(barAlpha).setFill()
        for index in 0..<barCount {
            let normalizedHeight = min(max(barProfile[index], 0.12), 1.0)
            let height = max(1.6, innerRect.height * normalizedHeight)
            let x = innerRect.minX + CGFloat(index) * (barWidth + spacing)
            let y = innerRect.midY - (height * 0.5)
            let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 0.9, yRadius: 0.9)
            barPath.fill()
        }

        if drawSlash {
            let slash = NSBezierPath()
            slash.move(to: CGPoint(x: bounds.minX + 2.0, y: bounds.maxY - 2.0))
            slash.line(to: CGPoint(x: bounds.maxX - 2.0, y: bounds.minY + 2.0))
            slash.lineWidth = 2.0
            baseColor.withAlphaComponent(strokeAlpha).setStroke()
            slash.stroke()
        }

        image.isTemplate = false
        return image
    }

    private func iconBaseColor(for state: MicIconState, blinkPhase: Bool) -> NSColor {
        switch state {
        case .idle:
            return monochromeColor()
        case .working:
            return adjustedAccentColor(NSColor.systemGreen, blinkPhase: blinkPhase)
        case .paused:
            if blinkPhase {
                return adjustedAccentColor(NSColor.systemGreen, blinkPhase: true)
            }
            return monochromeColor().withAlphaComponent(0.62)
        case .noAudio:
            return adjustedAccentColor(NSColor.systemRed, blinkPhase: blinkPhase)
        case .transcribing:
            return adjustedAccentColor(NSColor.systemOrange, blinkPhase: blinkPhase)
        case .polishing:
            return adjustedAccentColor(NSColor.systemMint, blinkPhase: blinkPhase)
        }
    }

    private func adjustedAccentColor(_ baseColor: NSColor, blinkPhase: Bool) -> NSColor {
        let alpha: CGFloat = blinkPhase ? 1.0 : 0.65
        if shouldUseDarkPalette() {
            let lightened = blend(baseColor: baseColor, target: .white, amount: 0.18)
            return lightened.withAlphaComponent(alpha)
        }
        return baseColor.withAlphaComponent(alpha)
    }

    private func monochromeColor() -> NSColor {
        if shouldUseDarkPalette() {
            return NSColor(calibratedWhite: 0.92, alpha: 1.0)
        }
        return NSColor(calibratedWhite: 0.10, alpha: 1.0)
    }

    private func shouldUseDarkPalette() -> Bool {
        switch currentAppearanceMode {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            let effective = statusItem.button?.effectiveAppearance
                ?? popover.contentViewController?.view.effectiveAppearance
                ?? NSApp.effectiveAppearance
            return isDarkAppearance(effective)
        }
    }

    private func isDarkAppearance(_ appearance: NSAppearance?) -> Bool {
        appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func applyAppearanceSettings() {
        let appearance = nsAppearance(for: currentAppearanceMode)
        statusItem.button?.appearance = appearance
        popover.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
    }

    private func nsAppearance(for mode: AppearanceMode) -> NSAppearance? {
        switch mode {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    private func blend(baseColor: NSColor, target: NSColor, amount: CGFloat) -> NSColor {
        let clamped = min(max(amount, 0), 1)
        guard let base = baseColor.usingColorSpace(.deviceRGB),
              let target = target.usingColorSpace(.deviceRGB) else {
            return baseColor
        }

        return NSColor(
            calibratedRed: base.redComponent + (target.redComponent - base.redComponent) * clamped,
            green: base.greenComponent + (target.greenComponent - base.greenComponent) * clamped,
            blue: base.blueComponent + (target.blueComponent - base.blueComponent) * clamped,
            alpha: base.alphaComponent
        )
    }

    private func updateNoiseFloor(using level: Float) {
        let boundedLevel = min(max(0, level), maxNoiseFloor)
        let floorUpdateCutoff = max(activityThreshold * 0.75, activityFloor)
        if boundedLevel <= floorUpdateCutoff {
            noiseFloor = ((1 - noiseFloorAlpha) * noiseFloor) + (noiseFloorAlpha * boundedLevel)
            noiseFloor = min(max(noiseFloor, minNoiseFloor), maxNoiseFloor)
        }

        activityThreshold = max(activityFloor, noiseFloor * activityNoiseMultiplier)
        instantActivityThreshold = max(0.012, min(0.020, activityThreshold * 0.7))
    }

    private func publishDebug(silenceDuration: TimeInterval) {
        shell.menubarIconDebug = String(
            format: "icon=%@ raw=%.3f smooth=%.3f floor=%.3f instant=%.3f threshold=%.3f silence=%.1fs",
            iconStateLabel(iconState),
            currentMeterLevel,
            smoothedMeterLevel,
            noiseFloor,
            instantActivityThreshold,
            activityThreshold,
            max(0, silenceDuration)
        )
    }

    private func iconStateLabel(_ state: MicIconState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .working:
            return "working"
        case .paused:
            return "paused"
        case .noAudio:
            return "no-audio"
        case .transcribing:
            return "transcribing"
        case .polishing:
            return "polishing"
        }
    }
}
