import Foundation

enum OpenScribeResourceLocator {
    static let resourceBundleName = "OpenScribe_OpenScribe.bundle"

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }

        guard let bundleURL = resourceBundleURL(),
              let bundle = Bundle(url: bundleURL) else {
            return nil
        }

        return bundle.url(forResource: name, withExtension: ext)
    }

    static func resourceBundleURL(
        mainResourceURL: URL? = Bundle.main.resourceURL,
        mainBundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL,
        loadedBundleURLs: [URL] = Bundle.allBundles.map(\.bundleURL),
        fileManager: FileManager = .default
    ) -> URL? {
        if let loadedBundleURL = loadedBundleURLs.first(where: {
            $0.lastPathComponent == resourceBundleName && fileManager.fileExists(atPath: $0.path)
        }) {
            return loadedBundleURL
        }

        return candidateBundleURLs(
            mainResourceURL: mainResourceURL,
            mainBundleURL: mainBundleURL,
            executableURL: executableURL
        ).first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private static func candidateBundleURLs(
        mainResourceURL: URL?,
        mainBundleURL: URL,
        executableURL: URL?
    ) -> [URL] {
        var urls: [URL] = []
        var seen: Set<URL> = []

        func append(_ url: URL?) {
            guard let url else {
                return
            }
            let standardizedURL = url.standardizedFileURL
            guard seen.insert(standardizedURL).inserted else {
                return
            }
            urls.append(standardizedURL)
        }

        append(mainResourceURL?.appendingPathComponent(resourceBundleName, isDirectory: true))

        if mainBundleURL.pathExtension == "app" {
            append(
                mainBundleURL
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(resourceBundleName, isDirectory: true)
            )
        } else {
            append(
                mainBundleURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(resourceBundleName, isDirectory: true)
            )
        }

        append(
            executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(resourceBundleName, isDirectory: true)
        )

        return urls
    }
}
