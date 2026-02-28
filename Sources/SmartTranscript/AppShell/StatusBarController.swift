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
        shell.updatePopoverSizeHandler = { [weak self] size in
            self?.updatePopoverSize(size)
        }
        configureStatusItem()
        configurePopover()
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
            menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit SmartTranscript", action: #selector(quitApp), keyEquivalent: "q")
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

    @objc private func quitApp() {
        NSApp.terminate(nil)
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
        popover.contentSize = NSSize(width: 540, height: 760)
        popover.contentViewController = NSHostingController(rootView: PopoverView().environmentObject(shell))
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updatePopoverSize(_ size: CGSize) {
        popover.contentSize = NSSize(width: size.width, height: size.height)
        if popover.isShown {
            popover.contentViewController?.view.window?.setContentSize(NSSize(width: size.width, height: size.height))
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
        button.contentTintColor = tintColor(for: state, blinkPhase: blinkPhase)
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

        let baseColor = NSColor.labelColor
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

        image.isTemplate = true
        return image
    }

    private func tintColor(for state: MicIconState, blinkPhase: Bool) -> NSColor? {
        switch state {
        case .idle:
            return nil
        case .working:
            return NSColor.systemGreen
        case .paused:
            return blinkPhase ? NSColor.systemGreen : NSColor.systemGray
        case .noAudio:
            return NSColor.systemRed
        case .transcribing:
            return blinkPhase ? NSColor.systemOrange : NSColor.systemOrange.withAlphaComponent(0.65)
        case .polishing:
            return blinkPhase ? NSColor.systemBlue : NSColor.systemBlue.withAlphaComponent(0.65)
        }
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
