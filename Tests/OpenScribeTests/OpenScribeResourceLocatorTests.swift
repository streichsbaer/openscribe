import XCTest
@testable import OpenScribe

final class OpenScribeResourceLocatorTests: XCTestCase {
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

    func testResourceBundleURLPrefersLoadedBundle() throws {
        let loadedBundleURL = tempDirectory.appendingPathComponent("Loaded/\(OpenScribeResourceLocator.resourceBundleName)", isDirectory: true)
        try FileManager.default.createDirectory(at: loadedBundleURL, withIntermediateDirectories: true)

        let resolvedURL = OpenScribeResourceLocator.resourceBundleURL(
            mainResourceURL: nil,
            mainBundleURL: tempDirectory.appendingPathComponent("OpenScribe"),
            executableURL: nil,
            loadedBundleURLs: [loadedBundleURL]
        )

        XCTAssertEqual(resolvedURL?.standardizedFileURL, loadedBundleURL.standardizedFileURL)
    }

    func testResourceBundleURLFindsBundleInsideAppResources() throws {
        let appBundleURL = tempDirectory.appendingPathComponent("OpenScribe.app", isDirectory: true)
        let resourcesURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let bundleURL = resourcesURL.appendingPathComponent(OpenScribeResourceLocator.resourceBundleName, isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let resolvedURL = OpenScribeResourceLocator.resourceBundleURL(
            mainResourceURL: resourcesURL,
            mainBundleURL: appBundleURL,
            executableURL: appBundleURL.appendingPathComponent("Contents/MacOS/OpenScribe"),
            loadedBundleURLs: []
        )

        XCTAssertEqual(resolvedURL?.standardizedFileURL, bundleURL.standardizedFileURL)
    }

    func testResourceBundleURLFindsBundleNextToExecutable() throws {
        let binDirectory = tempDirectory.appendingPathComponent("debug-bin", isDirectory: true)
        let executableURL = binDirectory.appendingPathComponent("OpenScribe")
        let bundleURL = binDirectory.appendingPathComponent(OpenScribeResourceLocator.resourceBundleName, isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let resolvedURL = OpenScribeResourceLocator.resourceBundleURL(
            mainResourceURL: nil,
            mainBundleURL: executableURL,
            executableURL: executableURL,
            loadedBundleURLs: []
        )

        XCTAssertEqual(resolvedURL?.standardizedFileURL, bundleURL.standardizedFileURL)
    }

    func testResourceBundleURLReturnsNilWhenBundleIsMissing() {
        let resolvedURL = OpenScribeResourceLocator.resourceBundleURL(
            mainResourceURL: nil,
            mainBundleURL: tempDirectory.appendingPathComponent("OpenScribe"),
            executableURL: tempDirectory.appendingPathComponent("OpenScribe"),
            loadedBundleURLs: []
        )

        XCTAssertNil(resolvedURL)
    }
}
