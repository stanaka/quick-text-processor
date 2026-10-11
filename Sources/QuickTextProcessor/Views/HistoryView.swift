import QTPCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var query = ""
    @State private var selectionID: UUID?
    @State private var confirmClear = false
    @StateObject private var rerunModel = StreamRunModel()

    private var filtered: [HistoryEntry] {
        historyStore.filtered(query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Search history…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Toggle("Save new runs", isOn: $settings.historyEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button("Clear All", role: .destructive) { confirmClear = true }
                    .disabled(historyStore.entries.isEmpty)
            }
            .padding(10)

            Divider()

            if historyStore.entries.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    List(filtered, selection: $selectionID) { entry in
                        row(entry).tag(entry.id)
                    }
                    .listStyle(.inset)
                    .frame(minWidth: 280, maxWidth: 360)

                    Divider()

                    if let entry = filtered.first(where: { $0.id == selectionID })
                        ?? historyStore.entries.first(where: { $0.id == selectionID }) {
                        detail(entry)
                    } else {
                        VStack {
                            Spacer()
                            Text("Select an entry")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .confirmationDialog("Delete all history entries?",
                            isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                selectionID = nil
                historyStore.clear()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No history yet")
                .foregroundStyle(.secondary)
            Text("Runs from the hotkey palette and the Playground appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.taskName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(TextContext.preview(of: entry.input, maxLength: 70))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let appName = entry.appName {
                Text(appName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func detail(_ entry: HistoryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.taskName).font(.headline)
                        Text("\(entry.providerName) · \(entry.model)"
                             + (entry.appName.map { " · \($0)" } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.date, format: .dateTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Re-run") { rerun(entry) }
                        .disabled(rerunModel.isStreaming || rerunTask(for: entry) == nil)
                        .help(rerunTask(for: entry) == nil
                              ? "The task “\(entry.taskName)” no longer exists"
                              : "Run this input again with the current template and provider")
                    Button("Delete", role: .destructive) {
                        selectionID = nil
                        historyStore.delete(ids: [entry.id])
                    }
                }

                if rerunModel.isStreaming {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Re-running… the result will be added as a new entry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if case .failed(let message) = rerunModel.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !entry.contextBefore.isEmpty {
                    section(title: "Context before", text: entry.contextBefore)
                }
                section(title: "Input", text: entry.input)
                if !entry.contextAfter.isEmpty {
                    section(title: "Context after", text: entry.contextAfter)
                }
                section(title: "Output", text: entry.output)
                if !entry.reasoning.isEmpty {
                    section(title: "Reasoning", text: entry.reasoning)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
    }

    private func section(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .controlSize(.small)
            }
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }

    private func rerunTask(for entry: HistoryEntry) -> PromptTask? {
        taskStore.tasks.first { $0.name == entry.taskName }
    }

    private func rerun(_ entry: HistoryEntry) {
        guard let task = rerunTask(for: entry) else { return }
        controller.runPlayground(input: entry.input, task: task, profileID: nil, model: rerunModel)
    }
}
