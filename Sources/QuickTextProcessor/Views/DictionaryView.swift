import QTPCore
import SwiftUI

/// Glossary editor. Entries are injected into prompts through the
/// {{glossary}} placeholder (for tasks with "Include glossary" enabled).
struct DictionaryView: View {
    @EnvironmentObject private var glossaryStore: GlossaryStore
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Terms the LLM must respect — product names, people, preferred translations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let entry = glossaryStore.addEntry()
                    selection = [entry.id]
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    glossaryStore.delete(ids: selection)
                    selection = []
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selection.isEmpty)
            }
            .padding(10)

            Divider()

            if glossaryStore.entries.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "character.book.closed")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No glossary entries")
                        .foregroundStyle(.secondary)
                    Text("Example: “Bengo4” → “弁護士ドットコム” (company name)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                Table(glossaryStore.entries, selection: $selection) {
                    TableColumn("Term") { (entry: GlossaryEntry) in
                        TextField("term as it appears", text: binding(for: entry.id, \.term))
                            .textFieldStyle(.plain)
                    }
                    TableColumn("Preferred spelling / translation") { (entry: GlossaryEntry) in
                        TextField("what the LLM should use", text: binding(for: entry.id, \.preferred))
                            .textFieldStyle(.plain)
                    }
                    TableColumn("Note (optional)") { (entry: GlossaryEntry) in
                        TextField("hint, e.g. “do not translate”", text: binding(for: entry.id, \.note))
                            .textFieldStyle(.plain)
                    }
                }
            }
        }
    }

    private func binding(for id: UUID,
                         _ keyPath: WritableKeyPath<GlossaryEntry, String>) -> Binding<String> {
        Binding(
            get: {
                glossaryStore.entries.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard var entry = glossaryStore.entries.first(where: { $0.id == id }) else { return }
                entry[keyPath: keyPath] = newValue
                glossaryStore.update(entry)
            }
        )
    }
}
