import SwiftUI

struct ResultView: View {
    @ObservedObject var model: StreamRunModel
    var onCopy: () -> Void
    var onInsert: () -> Void
    var onRetry: () -> Void
    var onClose: () -> Void

    @State private var showReasoning = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if case .failed(let message) = model.state {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                        Text(model.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !model.reasoning.isEmpty {
                            ReasoningSection(reasoning: model.reasoning,
                                             isExpanded: $showReasoning)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(12)
                }
                .onChange(of: model.text) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: model.reasoning) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            Divider()

            HStack(spacing: 8) {
                if model.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.awaitingConfirmation {
                    Text("⏎ insert · esc dismiss")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Retry", action: onRetry)
                    .disabled(model.isStreaming)
                Button("Copy", action: onCopy)
                    .disabled(model.text.isEmpty)
                if model.canInsert {
                    if model.awaitingConfirmation {
                        Button("Insert", action: onInsert)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Insert", action: onInsert)
                            .disabled(model.state != .done || model.text.isEmpty)
                    }
                }
                Button("Close", action: onClose)
            }
            .padding(10)
        }
        .frame(minWidth: 400, minHeight: 240)
    }
}
