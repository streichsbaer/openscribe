import XCTest
@testable import OpenScribe

final class WhisperBinaryResolverTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testResolveReturnsBundledBinaryForAppBundle() throws {
        let resourcesURL = tempDirectory.appendingPathComponent("OpenScribe.app/Contents/Resources", isDirectory: true)
        let bundledBinary = resourcesURL.appendingPathComponent("bin/whisper-cli")
        try makeExecutableFile(at: bundledBinary)
        let localBinary = tempDirectory.appendingPathComponent("local/whisper-cli")
        try makeExecutableFile(at: localBinary)

        let resolved = try WhisperBinaryResolver.resolve(
            bundleResourceURL: resourcesURL,
            bundleURL: tempDirectory.appendingPathComponent("OpenScribe.app"),
            localCandidatePaths: [localBinary.path]
        )

        XCTAssertEqual(resolved.standardizedFileURL, bundledBinary.standardizedFileURL)
    }

    func testResolveAppBundleFailsWhenBundledBinaryMissingEvenIfLocalBinaryExists() throws {
        let resourcesURL = tempDirectory.appendingPathComponent("OpenScribe.app/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let localBinary = tempDirectory.appendingPathComponent("local/whisper-cli")
        try makeExecutableFile(at: localBinary)

        XCTAssertThrowsError(
            try WhisperBinaryResolver.resolve(
                bundleResourceURL: resourcesURL,
                bundleURL: tempDirectory.appendingPathComponent("OpenScribe.app"),
                localCandidatePaths: [localBinary.path]
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Bundled whisper.cpp binary not found in the app bundle."
            )
        }
    }

    func testResolveNonAppBundleFallsBackToLocalBinary() throws {
        let resourcesURL = tempDirectory.appendingPathComponent("debug-resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let localBinary = tempDirectory.appendingPathComponent("local/whisper-cli")
        try makeExecutableFile(at: localBinary)

        let resolved = try WhisperBinaryResolver.resolve(
            bundleResourceURL: resourcesURL,
            bundleURL: tempDirectory.appendingPathComponent("OpenScribe"),
            localCandidatePaths: [localBinary.path]
        )

        XCTAssertEqual(resolved.standardizedFileURL, localBinary.standardizedFileURL)
    }

    private func makeExecutableFile(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
