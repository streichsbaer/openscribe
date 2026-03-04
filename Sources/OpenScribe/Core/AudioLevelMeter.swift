@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

enum AudioLevelMeter {
    static func rmsLevel(from buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return 0
        }

        let streamDescription = format.streamDescription.pointee

        let channelCount = Int(streamDescription.mChannelsPerFrame)
        guard channelCount > 0 else {
            return 0
        }

        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        let formatFlags = streamDescription.mFormatFlags
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0
        guard isFloat || isSignedInteger else {
            return 0
        }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>(mutating: buffer.audioBufferList)
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        guard !bufferList.isEmpty else {
            return 0
        }

        var sumSquares: Double = 0
        var sampleCount = 0

        if format.isInterleaved {
            guard let interleavedBuffer = bufferList.first else {
                return 0
            }
            let interleavedSampleCount = frameLength * channelCount
            accumulateSamples(
                from: interleavedBuffer,
                expectedSampleCount: interleavedSampleCount,
                bitsPerChannel: bitsPerChannel,
                isFloat: isFloat,
                isSignedInteger: isSignedInteger,
                sumSquares: &sumSquares,
                sampleCount: &sampleCount
            )
        } else {
            let bufferCount = min(channelCount, bufferList.count)
            for index in 0..<bufferCount {
                accumulateSamples(
                    from: bufferList[index],
                    expectedSampleCount: frameLength,
                    bitsPerChannel: bitsPerChannel,
                    isFloat: isFloat,
                    isSignedInteger: isSignedInteger,
                    sumSquares: &sumSquares,
                    sampleCount: &sampleCount
                )
            }
        }

        guard sampleCount > 0 else {
            return 0
        }
        return Float(sqrt(sumSquares / Double(sampleCount)))
    }

    private static func accumulateSamples(
        from audioBuffer: AudioBuffer,
        expectedSampleCount: Int,
        bitsPerChannel: Int,
        isFloat: Bool,
        isSignedInteger: Bool,
        sumSquares: inout Double,
        sampleCount: inout Int
    ) {
        guard expectedSampleCount > 0, let data = audioBuffer.mData else {
            return
        }

        if isFloat {
            let bytesPerSample = bitsPerChannel / 8
            guard bytesPerSample > 0 else {
                return
            }

            let availableSamples = Int(audioBuffer.mDataByteSize) / bytesPerSample
            let boundedSampleCount = min(expectedSampleCount, availableSamples)
            guard boundedSampleCount > 0 else {
                return
            }

            if bitsPerChannel == 32 {
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<boundedSampleCount {
                    let sample = samples[index]
                    let normalized = max(-1, min(1, sample))
                    sumSquares += Double(normalized * normalized)
                }
                sampleCount += boundedSampleCount
                return
            }

            if bitsPerChannel == 64 {
                let samples = data.assumingMemoryBound(to: Double.self)
                for index in 0..<boundedSampleCount {
                    let sample = Float(samples[index])
                    let normalized = max(-1, min(1, sample))
                    sumSquares += Double(normalized * normalized)
                }
                sampleCount += boundedSampleCount
            }
            return
        }

        guard isSignedInteger, bitsPerChannel > 0, bitsPerChannel <= 32 else {
            return
        }

        let bytesPerSample = (bitsPerChannel + 7) / 8
        guard bytesPerSample > 0 else {
            return
        }

        let availableSamples = Int(audioBuffer.mDataByteSize) / bytesPerSample
        let boundedSampleCount = min(expectedSampleCount, availableSamples)
        guard boundedSampleCount > 0 else {
            return
        }

        let maxMagnitude = Float((Int64(1) << (bitsPerChannel - 1)) - 1)
        guard maxMagnitude > 0 else {
            return
        }

        let bytes = data.assumingMemoryBound(to: UInt8.self)
        for index in 0..<boundedSampleCount {
            let raw = readSignedInteger(
                bytes,
                sampleIndex: index,
                bytesPerSample: bytesPerSample
            )
            let normalized = max(-1, min(1, Float(raw) / maxMagnitude))
            sumSquares += Double(normalized * normalized)
        }
        sampleCount += boundedSampleCount
    }

    private static func readSignedInteger(
        _ bytes: UnsafePointer<UInt8>,
        sampleIndex: Int,
        bytesPerSample: Int
    ) -> Int32 {
        let offset = sampleIndex * bytesPerSample
        switch bytesPerSample {
        case 1:
            return Int32(Int8(bitPattern: bytes[offset]))
        case 2:
            let unsigned = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            return Int32(Int16(bitPattern: unsigned))
        case 3:
            let b0 = Int32(bytes[offset])
            let b1 = Int32(bytes[offset + 1]) << 8
            let b2 = Int32(bytes[offset + 2]) << 16
            var value = b0 | b1 | b2
            if (value & 0x0080_0000) != 0 {
                value |= ~0x00FF_FFFF
            }
            return value
        case 4:
            let unsigned = UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
            return Int32(bitPattern: unsigned)
        default:
            return 0
        }
    }
}
