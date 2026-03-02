import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private enum MicIconState {
        case idle
        case working
        case paused
        case noAudio
        case transcribing
        case polishing
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
        shell.togglePopoverHandler = { [weak self] in
            self?.togglePopoverFromHotkey()
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

    func openSettingsFromShortcut() {
        openSettings()
    }

    func togglePopoverFromHotkey() {
        guard let button = statusItem.button else {
            return
        }
        togglePopover(button)
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
        let settingsImageURL = outputDirectory.appendingPathComponent("settings-window.png")
        let debugURL = outputDirectory.appendingPathComponent("ui-smoke-debug.txt")

        var popoverStatus = "fail"
        var settingsStatus = "fail"
        var iconStatus = "fail"
        var debugLines: [String] = []
        debugLines.append("statusButton=\(statusItem.button != nil)")
        let originalPopoverBehavior = popover.behavior
        popover.behavior = .applicationDefined

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
        } else {
            debugLines.append("popoverShown=false")
        }

        openSettings()
        try? await Task.sleep(nanoseconds: 700_000_000)
        if let settingsView = settingsWindowController.window?.contentView {
            let b = settingsView.bounds
            debugLines.append("settingsBounds=\(Int(b.width))x\(Int(b.height))")
        } else {
            debugLines.append("settingsBounds=missing")
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else {
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
            fitPopoverToContent(minSize: popover.contentSize)
        }
    }

    private func updatePopoverSize(_ size: CGSize) {
        let minSize = NSSize(width: size.width, height: size.height)
        popover.contentSize = minSize
        fitPopoverToContent(minSize: minSize)
    }

    private func fitPopoverToContent(minSize: NSSize) {
        guard let contentView = popover.contentViewController?.view else {
            return
        }

        contentView.frame.size.width = minSize.width
        contentView.layoutSubtreeIfNeeded()
        let fitting = contentView.fittingSize
        let target = NSSize(
            width: minSize.width,
            height: max(minSize.height, fitting.height)
        )

        popover.contentSize = target
        if popover.isShown {
            popover.contentViewController?.view.window?.setContentSize(target)
        }
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
