import Foundation

/// Versioned on-disk JSON container: {"version": 1, "items": [...]}.
struct VersionedFile<Item: Codable>: Codable {
    var version: Int
    var items: [Item]
}

/// Generic load/save for an array of Codable items in one JSON file.
///
/// - Writes are atomic (temp file + rename), so a crash never leaves a
///   half-written file.
/// - A file that fails to decode is quarantined (renamed to
///   "<name>.corrupt-<timestamp>") and the store restarts empty instead of
///   crashing or silently overwriting user data.
public final class JSONStore<Item: Codable> {

    public let url: URL
    private let version = 1

    public init(url: URL) {
        self.url = url
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() -> [Item] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let file = try Self.decoder().decode(VersionedFile<Item>.self, from: data)
            return file.items
        } catch {
            quarantineCorruptFile()
            return []
        }
    }

    public func save(_ items: [Item]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(VersionedFile(version: version, items: items))
        try data.write(to: url, options: .atomic)
    }

    private func quarantineCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let quarantineURL = url.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: url, to: quarantineURL)
    }
}

/// Locations for the app's data files.
public enum AppSupport {
    /// ~/Library/Application Support/QuickTextProcessor
    public static func directory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickTextProcessor", isDirectory: true)
    }
}
