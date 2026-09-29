import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var shell: AppShell
    @StateObject private var playbackManager = AudioPlaybackManager()
    @State private var hoverHint: String?

    var body: some View {
        VStack(spacing: 12) {
            header

            Group {
                switch shell.selectedPopoverTab {
                case .live:
                    LiveTabView(playback: playbackManager, hoverHint: $hoverHint)
                case .history:
                    HistoryTabView(playback: playbackManager, hoverHint: $hoverHint)
                case .stats:
                    StatsTabView(hoverHint: $hoverHint)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(width: AppShell.popoverSize.width, height: AppShell.popoverSize.height)
        .background(
            LinearGradient(
                colors: [PopoverPalette.groundTop, PopoverPalette.groundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            shell.selectPopoverTab(shell.selectedPopoverTab)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            OpenScribeMarkTile()
            Text("OpenScribe")
                .font(.system(size: 14, weight: .semibold))

            Picker("Popover tab", selection: Binding(
                get: { shell.selectedPopoverTab },
                set: { shell.selectPopoverTab($0) }
            )) {
                Text("Live").tag(PopoverTabSelection.live)
                Text("History").tag(PopoverTabSelection.history)
                Text("Stats").tag(PopoverTabSelection.stats)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.leading, 4)

            Spacer(minLength: 8)

            statusPill
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private var statusPill: some View {
        switch shell.sessionState {
        case .recording:
            HStack(spacing: 6) {
                Circle()
                    .fill(PopoverPalette.record)
                    .frame(width: 7, height: 7)
                if let createdAt = shell.currentSession?.metadata.createdAt, shell.selectedPopoverTab != .live {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text("Recording \(PopoverFormat.clock(seconds: timeline.date.timeIntervalSince(createdAt)))")
                    }
                } else {
                    Text("Recording")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(PopoverPalette.record)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(PopoverPalette.record.opacity(0.12)))
        case .finalizingAudio, .transcribing, .polishing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(shell.sessionState == .polishing ? "Polishing" : "Transcribing")
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(PopoverPalette.subtle))
        case .failed:
            Label("Not transcribed", systemImage: "exclamationmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(PopoverPalette.subtle))
        case .idle, .completed:
            EmptyView()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            footerLeading
            Spacer(minLength: 8)
            if hoverHint == nil, shell.lastError == nil, shell.hotkeyError == nil {
                Text(shell.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(PopoverPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .trailing)
            }
            Button {
                shell.openSettingsWindow()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .instantHint("Open Settings", hoverHint: $hoverHint)
        }
        .frame(height: 30)
    }

    @ViewBuilder
    private var footerLeading: some View {
        if let hoverHint {
            Text(hoverHint)
                .font(.system(size: 12))
                .foregroundStyle(PopoverPalette.muted)
                .lineLimit(1)
        } else if let hotkeyError = shell.hotkeyError {
            Text("Hotkey issue: \(hotkeyError)")
                .font(.system(size: 12))
                .foregroundStyle(Color.orange)
                .lineLimit(1)
        } else if let lastError = shell.lastError, shell.selectedPopoverTab != .live {
            Text(lastError)
                .font(.system(size: 12))
                .foregroundStyle(Color.red)
                .lineLimit(1)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(startStopKeys.enumerated()), id: \.offset) { _, key in
                    KeycapLabel(text: key)
                }
                Text(shell.sessionState == .recording ? "stops recording" : "starts recording")
                    .font(.system(size: 12))
                    .foregroundStyle(PopoverPalette.muted)
                    .padding(.leading, 2)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var startStopKeys: [String] {
        HotkeyDisplay.string(for: shell.settings.startStopHotkey)
            .split(separator: "+")
            .map { $0.lowercased() }
    }
}
