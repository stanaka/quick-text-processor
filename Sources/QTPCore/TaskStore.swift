import Combine
import Foundation

/// The user's prompt tasks, persisted to tasks.json. Seeds the five bundled
/// tasks on first launch. Not thread-safe: use from the main thread.
public final class TaskStore: ObservableObject {

    @Published public private(set) var tasks: [PromptTask] = []

    private let store: JSONStore<PromptTask>

    public init(url: URL) {
        store = JSONStore(url: url)
        let loaded = store.load()
        if loaded.isEmpty {
            tasks = SeedTasks.defaultTasks()
            persist()
        } else {
            tasks = loaded.sorted { $0.sortOrder < $1.sortOrder }
            migrateSeedTemplates()
        }
    }

    /// Upgrade bundled tasks whose template still matches an earlier release's
    /// seed text verbatim; user-customized templates are left untouched.
    private func migrateSeedTemplates() {
        var changed = false
        for index in tasks.indices {
            guard let key = tasks[index].seedKey,
                  SeedTasks.legacyTemplates(forKey: key).contains(tasks[index].template),
                  let seed = SeedTasks.all.first(where: { $0.key == key }) else { continue }
            tasks[index].template = seed.template
            changed = true
        }
        if changed { persist() }
    }

    public func task(withID id: UUID) -> PromptTask? {
        tasks.first { $0.id == id }
    }

    public func update(_ task: PromptTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        persist()
    }

    @discardableResult
    public func addTask(named name: String = "New task") -> PromptTask {
        let task = PromptTask(name: name,
                              template: "{{selected_text}}",
                              sortOrder: tasks.count)
        tasks.append(task)
        persist()
        return task
    }

    public func delete(id: UUID) {
        tasks.removeAll { $0.id == id }
        normalizeOrder()
        persist()
    }

    /// Move a task one slot up (`offset` = -1) or down (`offset` = +1).
    public func move(id: UUID, offset: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard tasks.indices.contains(target) else { return }
        tasks.swapAt(index, target)
        normalizeOrder()
        persist()
    }

    /// Restore a bundled task's template (and name) from SeedTasks.
    public func resetToDefault(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              let key = tasks[index].seedKey,
              let seed = SeedTasks.all.first(where: { $0.key == key }) else { return }
        tasks[index].template = seed.template
        tasks[index].name = seed.name
        persist()
    }

    private func normalizeOrder() {
        for index in tasks.indices {
            tasks[index].sortOrder = index
        }
    }

    private func persist() {
        try? store.save(tasks)
    }
}
