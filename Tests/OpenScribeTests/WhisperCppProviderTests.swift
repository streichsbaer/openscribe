import XCTest
@testable import OpenScribe

final class WhisperCppProviderTests: XCTestCase {
    func testArgumentsUseGPUByDefaultOnAppleSilicon() {
        let args = WhisperCppProvider.arguments(
            modelPath: "/models/ggml-base.bin",
            inputPath: "/tmp/input.wav",
            outputBasePath: "/tmp/out",
            language: nil
        )

        #if arch(arm64)
        XCTAssertFalse(args.contains("-ng"))
        #else
        XCTAssertTrue(args.contains("-ng"))
        #endif
        XCTAssertEqual(
            Array(args.prefix(7)),
            ["-m", "/models/ggml-base.bin", "-f", "/tmp/input.wav", "-otxt", "-of", "/tmp/out"]
        )
    }

    func testArgumentsDisableGPUWhenRequested() {
        let args = WhisperCppProvider.arguments(
            modelPath: "/m.bin",
            inputPath: "/i.wav",
            outputBasePath: "/o",
            language: "de",
            usesGPU: false
        )

        XCTAssertTrue(args.contains("-ng"))
        XCTAssertEqual(Array(args.suffix(2)), ["-l", "de"])
    }

    func testArgumentsMapAutoAndMissingLanguageToAuto() {
        for language in [nil, "", "AUTO"] as [String?] {
            let args = WhisperCppProvider.arguments(
                modelPath: "/m.bin",
                inputPath: "/i.wav",
                outputBasePath: "/o",
                language: language
            )
            XCTAssertEqual(Array(args.suffix(2)), ["-l", "auto"])
        }
    }
}
