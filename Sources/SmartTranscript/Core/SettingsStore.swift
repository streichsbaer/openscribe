import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    private let fileURL: URL
    private let fileManager: FileManager

    init(layout: DirectoryLayout, fileManager: FileManager = .default) {
        self.fileURL = layout.settingsFile
        self.fileManager = fileManager

        if var loaded = Self.load(from: fileURL) {
            let migrated = Self.normalize(loaded)
            self.settings = migrated
            if migrated != loaded {
                loaded = migrated
                try? persist()
            }
        } else {
            self.settings = .default
            try? persist()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var draft = settings
        mutate(&draft)
        settings = draft
        try? persist()
    }

    func resetToDefaults() {
        settings = .default
        try? persist()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try atomicWrite(data, to: fileURL)
    }

    private static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private static func normalize(_ settings: AppSettings) -> AppSettings {
        var normalized = settings
        normalized.startStopHotkey = normalized.startStopHotkey.normalizedForCarbonHotkey()
        normalized.copyHotkey = normalized.copyHotkey.normalizedForCarbonHotkey()
        if normalized.polishProviderID == "openai_polish", normalized.polishModel != "gpt-5-mini" {
            normalized.polishModel = "gpt-5-mini"
        }
        return normalized
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let tmpURL = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).tmp")
        try data.write(to: tmpURL, options: [.atomic])

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        try fileManager.moveItem(at: tmpURL, to: url)
    }
}
