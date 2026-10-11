import Combine
import Foundation

/// Run history, persisted to history.json, newest first, capped at `limit`.
/// Not thread-safe: use from the main thread.
public final class HistoryStore: ObservableObject {

    @Published public private(set) var entries: [HistoryEntry] = []

    /// Maximum number of entries kept; older entries are trimmed on append.
    public var limit: Int {
        didSet {
            // Direct assignment inside didSet does not re-trigger it.
            if limit < 1 { limit = 1 }
            if entries.count > limit {
                entries.removeLast(entries.count - limit)
                persist()
            }
        }
    }

    private let store: JSONStore<HistoryEntry>

    public init(url: URL, limit: Int = 500) {
        self.store = JSONStore(url: url)
        self.limit = max(1, limit)
        self.entries = Array(store.load().sorted { $0.date > $1.date }.prefix(self.limit))
    }

    public func append(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        persist()
    }

    public func delete(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        persist()
    }

    public func clear() {
        entries.removeAll()
        persist()
    }

    /// Case-insensitive search across task name, app name, input, surrounding context and output.
    public static func matches(_ entry: HistoryEntry, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystacks = [entry.taskName, entry.appName ?? "", entry.input,
                         entry.contextBefore, entry.contextAfter, entry.output,
                         entry.providerName, entry.model]
        return haystacks.contains { $0.range(of: query, options: .caseInsensitive) != nil }
    }

    public func filtered(query: String) -> [HistoryEntry] {
        entries.filter { Self.matches($0, query: query) }
    }

    private func persist() {
        try? store.save(entries)
    }
}
