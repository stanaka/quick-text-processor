import Combine
import Foundation

/// Observable sink for one streaming LLM run; drives both the floating result
/// panel and the Playground output area.
@MainActor
final class StreamRunModel: ObservableObject {

    enum State: Equatable {
        case idle
        case streaming
        case done
        case failed(String)
    }

    @Published var title = ""
    @Published var text = ""
    /// The model's explanation of its output (the prompt's <reasoning> block).
    /// Shown alongside the result but never inserted or copied.
    @Published var reasoning = ""
    @Published var state: State = .idle
    @Published var canInsert = false
    /// An auto-insert run finished and the result panel is waiting for the
    /// user to confirm (⏎ insert / esc dismiss) before anything is applied.
    @Published var awaitingConfirmation = false

    func begin(title: String, canInsert: Bool) {
        self.title = title
        self.canInsert = canInsert
        text = ""
        reasoning = ""
        state = .streaming
        awaitingConfirmation = false
    }

    func append(_ delta: String) {
        text += delta
    }

    func appendReasoning(_ delta: String) {
        reasoning += delta
    }

    func finish() {
        state = .done
    }

    func fail(_ message: String) {
        state = .failed(message)
    }

    var isStreaming: Bool { state == .streaming }
}
