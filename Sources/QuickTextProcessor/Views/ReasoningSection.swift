import SwiftUI

/// Collapsible, secondary-styled display of the model's reasoning, shown
/// under the answer in the result panel and the Playground.
struct ReasoningSection: View {
    let reasoning: String
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(reasoning)
                .textSelection(.enabled)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } label: {
            Text("Reasoning")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
