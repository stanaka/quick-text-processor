import XCTest
@testable import QTPCore

final class StoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qtp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    // MARK: - JSONStore

    func testRoundTrip() throws {
        let url = fileURL("glossary.json")
        let store = JSONStore<GlossaryEntry>(url: url)
        let entries = [GlossaryEntry(term: "QTP", preferred: "QuickTextProcessor", note: "app name")]
        try store.save(entries)
        let loaded = JSONStore<GlossaryEntry>(url: url).load()
        XCTAssertEqual(loaded, entries)
    }

    func testMissingFileLoadsEmpty() {
        XCTAssertEqual(JSONStore<GlossaryEntry>(url: fileURL("nope.json")).load(), [])
    }

    func testCorruptFileIsQuarantined() throws {
        let url = fileURL("tasks.json")
        try Data("{ not json ]".utf8).write(to: url)
        let loaded = JSONStore<PromptTask>(url: url).load()
        XCTAssertEqual(loaded, [])
        // Original moved aside, not deleted.
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(siblings.contains { $0.hasPrefix("tasks.json.corrupt-") })
    }

    func testDateSurvivesRoundTrip() throws {
        let url = fileURL("history.json")
        let entry = HistoryEntry(taskName: "t", input: "i", output: "o",
                                 providerName: "p", model: "m")
        try JSONStore<HistoryEntry>(url: url).save([entry])
        let loaded = JSONStore<HistoryEntry>(url: url).load()
        XCTAssertEqual(loaded.count, 1)
        // ISO8601 has second precision; compare loosely.
        XCTAssertEqual(loaded[0].date.timeIntervalSince1970,
                       entry.date.timeIntervalSince1970, accuracy: 1.0)
    }

    func testContextSurvivesRoundTrip() throws {
        let url = fileURL("history.json")
        let entry = HistoryEntry(taskName: "t", input: "i",
                                 contextBefore: "before text", contextAfter: "after text",
                                 output: "o", providerName: "p", model: "m")
        try JSONStore<HistoryEntry>(url: url).save([entry])
        let loaded = JSONStore<HistoryEntry>(url: url).load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].contextBefore, "before text")
        XCTAssertEqual(loaded[0].contextAfter, "after text")
    }

    func testHistoryWithoutContextKeysStillDecodes() throws {
        // history.json written before contextBefore/contextAfter existed must
        // load (with empty contexts), not get quarantined.
        let url = fileURL("history.json")
        let old = """
        {"version": 1, "items": [{
            "id": "00000000-0000-0000-0000-000000000001",
            "date": "2026-01-01T00:00:00Z",
            "taskName": "t",
            "input": "i",
            "output": "o",
            "providerName": "p",
            "model": "m"
        }]}
        """
        try Data(old.utf8).write(to: url)
        let loaded = JSONStore<HistoryEntry>(url: url).load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].contextBefore, "")
        XCTAssertEqual(loaded[0].contextAfter, "")
        XCTAssertEqual(loaded[0].reasoning, "")
        XCTAssertNil(loaded[0].appName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(siblings.contains { $0.hasPrefix("history.json.corrupt-") })
    }

    // MARK: - TaskStore

    func testTaskStoreSeedsOnFirstLaunch() {
        let store = TaskStore(url: fileURL("tasks.json"))
        XCTAssertEqual(store.tasks.count, SeedTasks.all.count)
        XCTAssertEqual(store.tasks.map(\.seedKey),
                       SeedTasks.all.map { Optional($0.key) })
        // Seeded state was persisted.
        let reloaded = TaskStore(url: fileURL("tasks.json"))
        XCTAssertEqual(reloaded.tasks.map(\.id), store.tasks.map(\.id))
    }

    func testTaskStoreResetToDefault() throws {
        let store = TaskStore(url: fileURL("tasks.json"))
        var task = try XCTUnwrap(store.tasks.first { $0.seedKey == "proofread" })
        task.template = "broken"
        store.update(task)
        XCTAssertEqual(store.task(withID: task.id)?.template, "broken")
        store.resetToDefault(id: task.id)
        XCTAssertEqual(store.task(withID: task.id)?.template, SeedTasks.template(forKey: "proofread"))
    }

    func testReasoningSurvivesRoundTrip() throws {
        let url = fileURL("history.json")
        let entry = HistoryEntry(taskName: "t", input: "i", output: "o",
                                 reasoning: "- fixed a typo", providerName: "p", model: "m")
        try JSONStore<HistoryEntry>(url: url).save([entry])
        let loaded = JSONStore<HistoryEntry>(url: url).load()
        XCTAssertEqual(loaded.first?.reasoning, "- fixed a typo")
    }

    func testTaskStoreMigratesUnmodifiedSeedTemplates() throws {
        let url = fileURL("tasks.json")
        let store = TaskStore(url: url)
        // Simulate an install that still carries the pre-reasoning templates:
        // one untouched seed (upgraded) and one user-customized (kept).
        var proofread = try XCTUnwrap(store.tasks.first { $0.seedKey == "proofread" })
        proofread.template = try XCTUnwrap(SeedTasks.legacyTemplates(forKey: "proofread").first)
        store.update(proofread)
        var summarize = try XCTUnwrap(store.tasks.first { $0.seedKey == "summarize" })
        summarize.template = "my own summarize prompt {{selected_text}}"
        store.update(summarize)

        let reloaded = TaskStore(url: url)
        XCTAssertEqual(reloaded.task(withID: proofread.id)?.template,
                       SeedTasks.template(forKey: "proofread"))
        XCTAssertEqual(reloaded.task(withID: summarize.id)?.template,
                       "my own summarize prompt {{selected_text}}")
        // The migration persisted: a further reload stays upgraded.
        XCTAssertEqual(TaskStore(url: url).task(withID: proofread.id)?.template,
                       SeedTasks.template(forKey: "proofread"))
    }

    func testTaskStoreMoveAndDelete() throws {
        let store = TaskStore(url: fileURL("tasks.json"))
        let first = store.tasks[0]
        store.move(id: first.id, offset: 1)
        XCTAssertEqual(store.tasks[1].id, first.id)
        XCTAssertEqual(store.tasks.map(\.sortOrder), Array(0..<store.tasks.count))
        store.move(id: first.id, offset: -1)
        XCTAssertEqual(store.tasks[0].id, first.id)
        // Moving past the edges is a no-op.
        store.move(id: first.id, offset: -1)
        XCTAssertEqual(store.tasks[0].id, first.id)

        store.delete(id: first.id)
        XCTAssertNil(store.task(withID: first.id))
        XCTAssertEqual(store.tasks.map(\.sortOrder), Array(0..<store.tasks.count))
    }

    // MARK: - HistoryStore

    private func entry(_ n: Int) -> HistoryEntry {
        HistoryEntry(date: Date(timeIntervalSince1970: Double(n)),
                     taskName: "task\(n)", appName: "App\(n)",
                     input: "input\(n)",
                     contextBefore: "before\(n)", contextAfter: "after\(n)",
                     output: "output\(n)",
                     providerName: "prov", model: "m")
    }

    func testHistoryCapTrimsOldest() {
        let store = HistoryStore(url: fileURL("history.json"), limit: 3)
        for n in 1...5 { store.append(entry(n)) }
        XCTAssertEqual(store.entries.map(\.taskName), ["task5", "task4", "task3"])
    }

    func testHistoryNewestFirstAfterReload() {
        let url = fileURL("history.json")
        let store = HistoryStore(url: url, limit: 10)
        for n in 1...3 { store.append(entry(n)) }
        let reloaded = HistoryStore(url: url, limit: 10)
        XCTAssertEqual(reloaded.entries.map(\.taskName), ["task3", "task2", "task1"])
    }

    func testHistorySearch() {
        let store = HistoryStore(url: fileURL("history.json"), limit: 10)
        store.append(entry(1))
        store.append(entry(2))
        XCTAssertEqual(store.filtered(query: "input1").count, 1)
        XCTAssertEqual(store.filtered(query: "OUTPUT2").count, 1)
        XCTAssertEqual(store.filtered(query: "App1").count, 1)
        XCTAssertEqual(store.filtered(query: "before1").count, 1)
        XCTAssertEqual(store.filtered(query: "AFTER2").count, 1)
        XCTAssertEqual(store.filtered(query: "").count, 2)
        XCTAssertEqual(store.filtered(query: "zzz").count, 0)
    }

    func testHistoryDeleteAndClear() {
        let store = HistoryStore(url: fileURL("history.json"), limit: 10)
        let first = entry(1)
        store.append(first)
        store.append(entry(2))
        store.delete(ids: [first.id])
        XCTAssertEqual(store.entries.count, 1)
        store.clear()
        XCTAssertEqual(store.entries.count, 0)
        XCTAssertEqual(HistoryStore(url: fileURL("history.json"), limit: 10).entries.count, 0)
    }

    // MARK: - GlossaryStore

    func testGlossaryCRUDAndPromptBlock() {
        let store = GlossaryStore(url: fileURL("glossary.json"))
        XCTAssertEqual(store.promptBlock(), "")
        var entry = store.addEntry()
        entry.term = "SSO"
        entry.preferred = "シングルサインオン"
        entry.note = "do not translate as 単独"
        store.update(entry)
        XCTAssertTrue(store.promptBlock().contains("\"SSO\" → \"シングルサインオン\""))
        store.delete(ids: [entry.id])
        XCTAssertEqual(store.entries.count, 0)
    }
}
