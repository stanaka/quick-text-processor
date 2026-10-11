import QTPCore
import SwiftUI

@MainActor
final class PaletteModel: ObservableObject {
    @Published var tasks: [PromptTask] = []
    @Published var selectedIndex = 0
    @Published var sourceLabel = ""
    @Published var previewText = ""
    /// Truncated surrounding context, shown dimmed around the selection
    /// preview. Empty for clipboard/playground sources (nothing captured).
    @Published var beforeText = ""
    @Published var afterText = ""
    /// Non-nil when there is nothing to process; tasks cannot be picked.
    @Published var emptyMessage: String?
    @Published var isClipboardSource = false
}

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    var onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: model.isClipboardSource ? "doc.on.clipboard" : "text.cursor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let message = model.emptyMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 8)
            } else {
                previewLine
                    .font(.caption)
                    .lineLimit(3)
                    .truncationMode(.tail)
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                        row(index: index, task: task)
                    }
                }
            }
            Divider()
            Text("↑↓ select   1–9 jump   ⏎ run   esc cancel")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    /// Selection preview with its surrounding context flowing around it:
    /// dimmed tail-of-before + emphasized selection + dimmed head-of-after.
    /// Empty context strings contribute nothing, so clipboard/playground
    /// sources degrade to the plain selection preview.
    private var previewLine: Text {
        Text(model.beforeText).foregroundStyle(.tertiary)
            + Text(model.beforeText.isEmpty ? "" : " ")
            + Text(model.previewText).foregroundStyle(.primary.opacity(0.8))
            + Text(model.afterText.isEmpty ? "" : " ")
            + Text(model.afterText).foregroundStyle(.tertiary)
    }

    private func row(index: Int, task: PromptTask) -> some View {
        HStack(spacing: 8) {
            Text(index < 9 ? "\(index + 1)" : " ")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(task.name)
                .lineLimit(1)
            Spacer(minLength: 0)
            if task.autoInsert {
                Image(systemName: "text.insert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Result is inserted at the cursor")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            index == model.selectedIndex ? Color.accentColor.opacity(0.22) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture { onPick(index) }
    }
}
