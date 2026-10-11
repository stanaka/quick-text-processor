import QTPCore
import SwiftUI

struct TaskSettingsView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var selectionID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            taskList
            Divider()
            if let task = selectedTask {
                taskForm(task)
            } else {
                VStack {
                    Spacer()
                    Text("Select a task")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if selectionID == nil {
                selectionID = taskStore.tasks.first?.id
            }
        }
    }

    private var selectedTask: PromptTask? {
        taskStore.task(withID: selectionID ?? UUID())
    }

    // MARK: - List

    private var taskList: some View {
        VStack(spacing: 0) {
            List(taskStore.tasks, selection: $selectionID) { task in
                HStack {
                    Text(task.name).lineLimit(1)
                    Spacer()
                    if task.autoInsert {
                        Image(systemName: "text.insert")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Auto-inserts its result at the cursor")
                    }
                }
                .tag(task.id)
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 6) {
                Button {
                    let task = taskStore.addTask()
                    selectionID = task.id
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Button {
                    if let id = selectionID {
                        taskStore.delete(id: id)
                        selectionID = taskStore.tasks.first?.id
                    }
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectionID == nil || taskStore.tasks.count <= 1)

                Spacer()

                Button {
                    if let id = selectionID { taskStore.move(id: id, offset: -1) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(selectionID == nil)
                .help("Move up in the palette")

                Button {
                    if let id = selectionID { taskStore.move(id: id, offset: 1) }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(selectionID == nil)
                .help("Move down in the palette")
            }
            .padding(8)
        }
        .frame(width: 250)
    }

    // MARK: - Form

    private func taskForm(_ task: PromptTask) -> some View {
        Form {
            Section("Task") {
                TextField("Name", text: taskBinding(task.id, \.name, fallback: ""))
                Picker("Provider", selection: taskBinding(task.id, \.providerProfileID, fallback: nil)) {
                    Text("App default").tag(UUID?.none)
                    ForEach(settings.profiles) { profile in
                        Text("\(profile.name) — \(profile.model)").tag(Optional(profile.id))
                    }
                }
                Toggle("Include glossary ({{glossary}})",
                       isOn: taskBinding(task.id, \.includeGlossary, fallback: true))
                Toggle("Auto-insert result at the cursor (⏎ confirms, esc dismisses)",
                       isOn: taskBinding(task.id, \.autoInsert, fallback: false))
            }

            Section("Prompt template") {
                TextEditor(text: taskBinding(task.id, \.template, fallback: ""))
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 240)
                Text("Placeholders: {{selected_text}} · {{context_before}} · {{context_after}} · {{app_name}} · {{glossary}}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Ask the model to end its response with a <reasoning>…</reasoning> block to show its reasoning in the result window; the reasoning is never inserted or copied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if task.seedKey != nil {
                    Button("Reset to Default Template") {
                        taskStore.resetToDefault(id: task.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func taskBinding<T>(_ id: UUID,
                                _ keyPath: WritableKeyPath<PromptTask, T>,
                                fallback: T) -> Binding<T> {
        Binding(
            get: { taskStore.task(withID: id)?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard var task = taskStore.task(withID: id) else { return }
                task[keyPath: keyPath] = newValue
                taskStore.update(task)
            }
        )
    }
}
