import QTPCore
import SwiftUI

/// Try tasks/prompts/providers without leaving the app: paste text, pick a
/// task and provider, run, watch the streamed result.
struct PlaygroundView: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var settings: SettingsStore

    @StateObject private var model = StreamRunModel()
    @State private var input = ""
    @State private var taskID: UUID?
    @State private var profileID: UUID?
    @State private var showReasoning = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Task", selection: $taskID) {
                    ForEach(taskStore.tasks) { task in
                        Text(task.name).tag(Optional(task.id))
                    }
                }
                .frame(maxWidth: 260)

                Picker("Provider", selection: $profileID) {
                    Text("Task default").tag(UUID?.none)
                    ForEach(settings.profiles) { profile in
                        Text("\(profile.name) — \(profile.model)").tag(Optional(profile.id))
                    }
                }
                .frame(maxWidth: 300)

                Spacer()

                if model.isStreaming {
                    Button("Stop") {
                        controller.stopPlayground(model: model)
                    }
                }
                Button("Run") { run() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(runDisabled)
            }

            TextEditor(text: $input)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("Paste or type the text to process…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 10)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 130, maxHeight: 220)

            HStack {
                Text("Result")
                    .font(.headline)
                if model.isStreaming {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.text, forType: .string)
                }
                .disabled(model.text.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if case .failed(let message) = model.state {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                        Text(model.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !model.reasoning.isEmpty {
                            ReasoningSection(reasoning: model.reasoning,
                                             isExpanded: $showReasoning)
                        }
                        Color.clear.frame(height: 1).id("playground-bottom")
                    }
                    .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                .onChange(of: model.text) { _, _ in
                    proxy.scrollTo("playground-bottom", anchor: .bottom)
                }
                .onChange(of: model.reasoning) { _, _ in
                    proxy.scrollTo("playground-bottom", anchor: .bottom)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .onAppear {
            if taskID == nil {
                taskID = taskStore.tasks.first?.id
            }
        }
    }

    private var selectedTask: PromptTask? {
        taskStore.tasks.first { $0.id == taskID } ?? taskStore.tasks.first
    }

    private var runDisabled: Bool {
        model.isStreaming
            || selectedTask == nil
            || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run() {
        guard let task = selectedTask else { return }
        controller.runPlayground(input: input, task: task, profileID: profileID, model: model)
    }
}
