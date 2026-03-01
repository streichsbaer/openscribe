import Foundation

enum AudioTranscoder {
    static func transcodeToM4A(sourceWAVURL: URL, destinationURL: URL) throws {
        try transcode(
            sourceURL: sourceWAVURL,
            destinationURL: destinationURL,
            fileFormat: "m4af",
            dataFormat: "aac",
            bitrate: nil
        )
    }

    static func transcodeToWAV(sourceURL: URL, destinationURL: URL) throws {
        try transcode(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            fileFormat: "WAVE",
            dataFormat: "LEI16@16000",
            bitrate: nil
        )
    }

    private static func transcode(
        sourceURL: URL,
        destinationURL: URL,
        fileFormat: String,
        dataFormat: String,
        bitrate: String?
    ) throws {
        let fileManager = FileManager.default
        let parentDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let tempDestination = parentDirectory.appendingPathComponent("\(UUID().uuidString).\(destinationURL.pathExtension)")
        if fileManager.fileExists(atPath: tempDestination.path) {
            try fileManager.removeItem(at: tempDestination)
        }

        var arguments = [
            "-f", fileFormat,
            "-d", dataFormat
        ]
        if let bitrate, !bitrate.isEmpty {
            arguments.append(contentsOf: ["-b", bitrate])
        }
        arguments.append(contentsOf: [sourceURL.path, tempDestination.path])

        do {
            try runAFConvert(arguments: arguments)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: tempDestination, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: tempDestination)
            throw error
        }
    }

    private static func runAFConvert(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                throw ProviderError.processFailed(message)
            }
            throw ProviderError.processFailed("afconvert failed.")
        }
    }
}
