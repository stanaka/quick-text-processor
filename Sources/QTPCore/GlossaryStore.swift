import Combine
import Foundation

/// The user's glossary (Dictionary section), persisted to glossary.json.
/// Not thread-safe: use from the main thread.
public final class GlossaryStore: ObservableObject {

    @Published public private(set) var entries: [GlossaryEntry] = []

    private let store: JSONStore<GlossaryEntry>

    public init(url: URL) {
        store = JSONStore(url: url)
        entries = store.load()
    }

    @discardableResult
    public func addEntry() -> GlossaryEntry {
        let entry = GlossaryEntry()
        entries.append(entry)
        persist()
        return entry
    }

    public func update(_ entry: GlossaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        persist()
    }

    public func delete(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        persist()
    }

    /// The {{glossary}} block for prompt templates ("" when empty).
    public func promptBlock() -> String {
        GlossaryFormatter.format(entries)
    }

    private func persist() {
        try? store.save(entries)
    }
}
