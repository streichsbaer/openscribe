import SwiftUI

/// Download progress for one model, or for every model downloading right now.
/// It observes the download manager itself, so it updates while the rest of the screen stays put.
struct ModelDownloadProgressView: View {
    @ObservedObject var manager: ModelDownloadManager
    var modelID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.modelID) { item in
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                    Text(label(for: item))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var items: [(modelID: String, progress: Double)] {
        manager.downloadProgress
            .filter { modelID == nil || $0.key == modelID }
            .sorted { $0.key < $1.key }
            .map { (modelID: $0.key, progress: min(max($0.value, 0), 1)) }
    }

    private func label(for item: (modelID: String, progress: Double)) -> String {
        guard let asset = manager.asset(for: item.modelID) else {
            return "Downloading \(Int(item.progress * 100))%"
        }
        let total = ByteCountFormatter.string(fromByteCount: asset.expectedSizeBytes, countStyle: .file)
        return "Downloading \(asset.displayName) · \(Int(item.progress * 100))% of \(total)"
    }
}

/// A model's download action: a button, then progress while it runs, then a checkmark.
struct ModelDownloadButton: View {
    @ObservedObject var manager: ModelDownloadManager
    let modelID: String
    var isEnabled = true
    let onDownload: () -> Void

    var body: some View {
        if manager.isInstalled(modelID: modelID) {
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        } else if manager.isDownloading(modelID: modelID) {
            ModelDownloadProgressView(manager: manager, modelID: modelID)
                .frame(width: 280)
        } else {
            Button("Download model", action: onDownload)
                .buttonStyle(.borderedProminent)
                .disabled(!isEnabled)
        }
    }
}

/// The capture card hint in Live: download progress while a model downloads, otherwise the text.
struct LiveCaptureHint: View {
    @ObservedObject var manager: ModelDownloadManager
    let text: String
    let isWarning: Bool

    var body: some View {
        if manager.isDownloading {
            ModelDownloadProgressView(manager: manager)
                .frame(maxWidth: 260)
        } else {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(isWarning ? Color.orange : PopoverPalette.muted)
                .lineLimit(1)
        }
    }
}
