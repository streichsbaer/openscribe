import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioMeterState: ObservableObject {
    static let liveLevelCount = 56

    @Published var snapshot = AudioActivitySnapshot.silence
    /// The most recent input levels, oldest first, each from 0 (silence) to 1 (loud).
    @Published private(set) var recentLevels: [Float] = []
    /// Every level of the current recording, merged in pairs once it grows long.
    private(set) var recordingLevels: [Float] = []

    private static let maxRecordingLevels = 4_096

    func beginRecording() {
        recentLevels = []
        recordingLevels = []
        snapshot = .silence
    }

    func record(_ snapshot: AudioActivitySnapshot) {
        self.snapshot = snapshot
        let level = Self.normalizedLevel(snapshot.levelDBFS)
        recentLevels.append(level)
        if recentLevels.count > Self.liveLevelCount {
            recentLevels.removeFirst(recentLevels.count - Self.liveLevelCount)
        }
        recordingLevels.append(level)
        if recordingLevels.count > Self.maxRecordingLevels {
            recordingLevels = stride(from: 0, to: recordingLevels.count - 1, by: 2).map {
                max(recordingLevels[$0], recordingLevels[$0 + 1])
            }
        }
    }

    nonisolated static func normalizedLevel(_ levelDBFS: Float) -> Float {
        let minimumDBFS: Float = -60
        let maximumDBFS: Float = -6
        let bounded = min(max(levelDBFS, minimumDBFS), maximumDBFS)
        return (bounded - minimumDBFS) / (maximumDBFS - minimumDBFS)
    }
}

enum AudioEnvelope {
    /// Reduces levels to `count` bars, keeping the loudest level of each slice.
    static func bars(from levels: [Float], count: Int) -> [Float] {
        guard !levels.isEmpty, count > 0 else {
            return []
        }
        return (0..<count).map { index in
            let lower = index * levels.count / count
            let upper = max(lower + 1, (index + 1) * levels.count / count)
            return levels[lower..<min(upper, levels.count)].max() ?? 0
        }
    }

    /// Reads an audio file and returns `count` bars of its loudness, from 0 to 1.
    static func load(url: URL, count: Int) async -> [Float] {
        await Task.detached(priority: .utility) {
            guard let file = try? AVAudioFile(forReading: url) else {
                return []
            }
            let format = file.processingFormat
            let totalFrames = AVAudioFramePosition(file.length)
            guard totalFrames > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192) else {
                return []
            }
            let framesPerBar = max(1, totalFrames / AVAudioFramePosition(count))
            var sumOfSquares = [Float](repeating: 0, count: count)
            var sampleCounts = [Int](repeating: 0, count: count)
            var frameIndex: AVAudioFramePosition = 0
            while frameIndex < totalFrames {
                buffer.frameLength = 0
                guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0,
                      let channel = buffer.floatChannelData?[0] else {
                    break
                }
                for sample in 0..<Int(buffer.frameLength) {
                    let bar = min(count - 1, Int((frameIndex + AVAudioFramePosition(sample)) / framesPerBar))
                    sumOfSquares[bar] += channel[sample] * channel[sample]
                    sampleCounts[bar] += 1
                }
                frameIndex += AVAudioFramePosition(buffer.frameLength)
            }
            return (0..<count).map { bar in
                let rms = sampleCounts[bar] > 0 ? (sumOfSquares[bar] / Float(sampleCounts[bar])).squareRoot() : 0
                return AudioMeterState.normalizedLevel(rms > 0 ? 20 * log10(rms) : -80)
            }
        }.value
    }
}
