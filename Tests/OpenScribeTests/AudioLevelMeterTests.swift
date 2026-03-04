@preconcurrency import AVFoundation
import XCTest
@testable import OpenScribe

final class AudioLevelMeterTests: XCTestCase {
    func testFloat32NonInterleavedRMS() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4

        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        channel[0] = 0.5
        channel[1] = -0.5
        channel[2] = 0.5
        channel[3] = -0.5

        let rms = AudioLevelMeter.rmsLevel(from: buffer, format: format)
        XCTAssertEqual(rms, 0.5, accuracy: 0.0001)
    }

    func testInt16InterleavedRMS() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4

        writeInt16Samples([16_384, -16_384, 16_384, -16_384], to: buffer)

        let rms = AudioLevelMeter.rmsLevel(from: buffer, format: format)
        XCTAssertEqual(rms, 0.5, accuracy: 0.001)
    }

    func testInt32NonInterleavedRMS() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatInt32, sampleRate: 16_000, channels: 1, interleaved: false)
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4

        let channel = try XCTUnwrap(buffer.int32ChannelData?[0])
        channel[0] = Int32.max / 2
        channel[1] = -(Int32.max / 2)
        channel[2] = Int32.max / 2
        channel[3] = -(Int32.max / 2)

        let rms = AudioLevelMeter.rmsLevel(from: buffer, format: format)
        XCTAssertEqual(rms, 0.5, accuracy: 0.01)
    }

    func testPacked24BitInterleavedRMS() throws {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: 16_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 3,
            mFramesPerPacket: 1,
            mBytesPerFrame: 3,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 24,
            mReserved: 0
        )
        let format = try XCTUnwrap(AVAudioFormat(streamDescription: &streamDescription))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4

        write24BitSamples([4_194_304, -4_194_304, 4_194_304, -4_194_304], to: buffer)

        let rms = AudioLevelMeter.rmsLevel(from: buffer, format: format)
        XCTAssertEqual(rms, 0.5, accuracy: 0.02)
    }

    private func writeInt16Samples(_ samples: [Int16], to buffer: AVAudioPCMBuffer) {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let data = audioBuffer.mData else {
            XCTFail("Audio buffer data pointer is missing.")
            return
        }

        let target = data.assumingMemoryBound(to: Int16.self)
        for index in 0..<samples.count {
            target[index] = samples[index]
        }
    }

    private func write24BitSamples(_ samples: [Int32], to buffer: AVAudioPCMBuffer) {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let data = audioBuffer.mData else {
            XCTFail("Audio buffer data pointer is missing.")
            return
        }

        let target = data.assumingMemoryBound(to: UInt8.self)
        for (index, sample) in samples.enumerated() {
            let clamped = max(-8_388_608, min(8_388_607, sample))
            let encoded = UInt32(bitPattern: clamped) & 0x00FF_FFFF
            let offset = index * 3
            target[offset] = UInt8(encoded & 0xFF)
            target[offset + 1] = UInt8((encoded >> 8) & 0xFF)
            target[offset + 2] = UInt8((encoded >> 16) & 0xFF)
        }
    }
}
