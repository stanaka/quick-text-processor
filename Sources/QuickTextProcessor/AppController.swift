import AppKit
import Combine
import QTPCore
import SwiftUI
import os

/// Central coordinator: owns the stores, the global hotkey, and the
/// hotkey → capture → palette → LLM → result/insert pipeline.
@MainActor
final class AppController: ObservableObject {

    let settings: SettingsStore
    let taskStore: TaskStore
    let historyStore: HistoryStore
    let glossaryStore: GlossaryStore

    private let hotkeyManager = HotkeyManager()
    private let paletteController = PaletteController()
    private let resultController = ResultController()

    private var tokenManagers: [UUID: OAuthTokenManager] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var hotkeyRun: Task<Void, Never>?
    private var playgroundRun: Task<Void, Never>?
    /// The capture the palette / result panel is currently working on.
    private var currentContext: CaptureContext?
    /// Guards the awaited capture: a press landing inside the Electron retry
    /// window must not start a second pipeline.
    private var captureInFlight = false

    init() {
        let directory = AppSupport.directory()
        let settings = SettingsStore()
        self.settings = settings
        self.taskStore = TaskStore(url: directory.appendingPathComponent("tasks.json"))
        self.historyStore = HistoryStore(url: directory.appendingPathComponent("history.json"),
                                         limit: settings.historyLimit)
        self.glossaryStore = GlossaryStore(url: directory.appendingPathComponent("glossary.json"))
    }

    func start() {
        hotkeyManager.onHotkey = { [weak self] in
            guard let self else { return }
            Task { await self.hotkeyPressed() }
        }
        hotkeyManager.register(settings.hotkey)

        settings.$hotkey
            .dropFirst()
            .sink { [weak self] combo in
                self?.hotkeyManager.register(combo)
            }
            .store(in: &cancellables)

        settings.$historyLimit
            .dropFirst()
            .sink { [weak self] limit in
                self?.historyStore.limit = limit
            }
            .store(in: &cancellables)
    }

    /// Used by the hotkey recorder so the current hotkey does not fire while
    /// a new one is being typed.
    func setHotkeyPaused(_ paused: Bool) {
        if paused {
            hotkeyManager.pause()
        } else {
            hotkeyManager.resume()
        }
    }

    var hotkeyRegistrationFailed: Bool {
        hotkeyManager.lastRegistrationStatus != noErr
    }

    // MARK: - Accessibility

    var accessibilityGranted: Bool {
        AXCapture.isTrusted(promptIfNeeded: false)
    }

    func requestAccessibility() {
        _ = AXCapture.isTrusted(promptIfNeeded: true)
    }

    // MARK: - Hotkey pipeline

    private func hotkeyPressed() async {
        // Second press toggles the palette away.
        if paletteController.isVisible {
            paletteController.dismiss()
            return
        }
        guard !captureInFlight else { return }

        // Snapshot the capture BEFORE showing any UI of our own.
        captureInFlight = true
        let context = await captureContext()
        captureInFlight = false
        currentContext = context

        let sourceLabel: String
        var preview = ""
        var before = ""
        var after = ""
        var emptyMessage: String?
        if let context {
            let appName = context.text.appName ?? "the frontmost app"
            sourceLabel = context.text.source == .clipboard
                ? "Clipboard text (no selection available)"
                : "Selection in \(appName)"
            preview = TextContext.preview(of: context.text.selected, maxLength: 60)
            before = TextContext.previewTail(of: context.text.before, maxLength: 40)
            after = TextContext.preview(of: context.text.after, maxLength: 40)
        } else {
            sourceLabel = "Nothing to process"
            emptyMessage = "No text is selected, and the clipboard has no text."
        }

        paletteController.show(
            tasks: taskStore.tasks,
            sourceLabel: sourceLabel,
            previewText: preview,
            beforeText: before,
            afterText: after,
            isClipboardSource: context?.text.source == .clipboard,
            emptyMessage: emptyMessage,
            onPick: { [weak self] task in
                self?.run(task: task)
            },
            onCancel: {}
        )
    }

    private func captureContext() async -> CaptureContext? {
        switch AXCapture.capture(contextRadius: settings.contextRadius) {
        case .success(let axContext):
            Log.capture.notice("Captured \(axContext.text.selected.count, privacy: .public) chars from \(axContext.text.bundleID ?? "unknown", privacy: .public)")
            return axContext
        case .failure(let reason):
            Log.capture.notice("AX capture failed: \(String(describing: reason), privacy: .public)")
            if let retried = await captureAfterEnablingAccessibility(reason: reason) {
                return retried
            }
        }
        // Fallback: current clipboard text (deliberately NOT a synthesized ⌘C).
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let clipboard = NSPasteboard.general.string(forType: .string),
           !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = CapturedText(selected: clipboard,
                                    appName: frontmost?.localizedName,
                                    bundleID: frontmost?.bundleIdentifier,
                                    source: .clipboard)
            return CaptureContext(text: text, element: nil, app: frontmost)
        }
        return nil
    }

    /// Chromium apps (VS Code, Slack, ...) expose no text attributes until an
    /// assistive technology asks for their AX tree. Switch it on and re-capture
    /// while it is built; nil when this cannot help or did not.
    ///
    /// Electron accepts the attribute immediately but debounces the actual
    /// switch-on by 2 seconds, so a newly enabled app gets a budget long
    /// enough to outlast that, ended early the moment the tree reports ready.
    /// An app enabled earlier only gets a short re-check.
    private func captureAfterEnablingAccessibility(reason: CaptureFailure) async -> CaptureContext? {
        guard CaptureRetryPolicy.shouldAttemptAccessibilityEnable(after: reason),
              let frontmost = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let pid = frontmost.processIdentifier

        let budgetMilliseconds: Int
        switch ElectronAccessibility.enable(pid: pid) {
        case .newlyEnabled:
            budgetMilliseconds = CaptureRetryPolicy.firstEnableBudgetMilliseconds
        case .alreadyEnabled:
            // The tree is up, so an empty selection is the real answer; only
            // the tree-shaped failures are worth another look.
            guard CaptureRetryPolicy.shouldRetryWhenAlreadyEnabled(after: reason) else { return nil }
            budgetMilliseconds = CaptureRetryPolicy.alreadyEnabledBudgetMilliseconds
        case .unsupported:
            // A native app: a failed capture is the real answer.
            return nil
        }

        var waitedMilliseconds = 0
        var lastFailure = reason
        var treeReadyAtMilliseconds: Int?
        while waitedMilliseconds < budgetMilliseconds {
            let step = min(CaptureRetryPolicy.pollIntervalMilliseconds,
                           budgetMilliseconds - waitedMilliseconds)
            try? await Task.sleep(nanoseconds: UInt64(step) * 1_000_000)
            waitedMilliseconds += step

            switch AXCapture.capture(contextRadius: settings.contextRadius) {
            case .success(let context):
                Log.capture.notice("Capture succeeded \(waitedMilliseconds, privacy: .public)ms after enabling AXManualAccessibility")
                return context
            case .failure(let failure):
                lastFailure = failure
                guard ElectronAccessibility.isTreeReady(pid: pid) else { continue }

                // The tree is up, so the element exposing the attribute and
                // answering "" is the app's real answer, not a race. This is
                // the observed shape of a VS Code editor at default settings:
                // the element is there, Monaco just leaves it empty unless it
                // believes a screen reader is attached.
                if failure == .emptySelection {
                    Log.capture.notice("Tree ready after \(waitedMilliseconds, privacy: .public)ms but nothing selected")
                    return nil
                }
                // Still no text attributes at all with the tree up. Give it a
                // grace period to finish populating, then stop rather than
                // stalling the palette for the whole budget. (Not the VS Code
                // case — that one answers with an empty string above.)
                let readyAt = treeReadyAtMilliseconds ?? waitedMilliseconds
                treeReadyAtMilliseconds = readyAt
                if waitedMilliseconds - readyAt >= CaptureRetryPolicy.postTreeReadyGraceMilliseconds {
                    Log.capture.notice("Tree ready after \(readyAt, privacy: .public)ms but still no text attributes; giving up")
                    return nil
                }
            }
        }
        Log.capture.notice("No AX selection after \(waitedMilliseconds, privacy: .public)ms; last failure \(String(describing: lastFailure), privacy: .public); tree ready: \(ElectronAccessibility.isTreeReady(pid: pid), privacy: .public)")
        return nil
    }

    private func run(task: PromptTask) {
        guard let context = currentContext else { return }
        guard let profile = settings.resolvedProfile(for: task) else {
            resultController.presentError(taskName: task.name,
                                          message: "No provider is configured. Open Settings → Providers.")
            return
        }
        let prompt = renderPrompt(task: task, captured: context.text)
        let client = makeClient(profile: profile)
        let autoInsert = task.autoInsert && context.canInsert

        resultController.present(taskName: task.name, canInsert: context.canInsert)
        resultController.onInsert = { [weak self] text in
            self?.insertResult(text)
        }
        resultController.onRetry = { [weak self] in
            // Never auto-insert on retry: a successful auto-insert run has
            // already pasted once, and the target's cursor may have moved —
            // show the result and let the user insert manually.
            self?.startHotkeyRun(task: task, prompt: prompt, context: context,
                                 client: client, autoInsert: false)
        }
        startHotkeyRun(task: task, prompt: prompt, context: context,
                       client: client, autoInsert: autoInsert)
    }

    private func startHotkeyRun(task: PromptTask,
                                prompt: String,
                                context: CaptureContext,
                                client: LLMClient,
                                autoInsert: Bool) {
        if resultController.model.state != .streaming {
            resultController.model.begin(title: task.name, canInsert: context.canInsert)
        }
        hotkeyRun?.cancel()
        hotkeyRun = streamTask(prompt: prompt, client: client, into: resultController.model) { [weak self] output, reasoning in
            guard let self else { return }
            self.recordHistory(task: task, context: context, output: output,
                               reasoning: reasoning, client: client)
            if autoInsert {
                // Never apply the result without the user's response: keep the
                // panel up and wait for ⏎ (insert) or esc (dismiss).
                self.resultController.beginConfirmation()
            }
        }
    }

    private func insertResult(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let context = currentContext
        // Hide our panels first: while one of them is key, the synthesized ⌘V
        // of the paste fallback would land in this app.
        resultController.hide()
        Task {
            await TextInsertion.insert(text, into: context)
        }
    }

    // MARK: - Shared run plumbing

    /// Streams one prompt into a StreamRunModel on the main actor, splitting
    /// the response into the answer and an optional <reasoning> block.
    @discardableResult
    private func streamTask(prompt: String,
                            client: LLMClient,
                            into model: StreamRunModel,
                            onSuccess: ((_ output: String, _ reasoning: String) -> Void)? = nil) -> Task<Void, Never> {
        Task {
            var parser = ReasoningStreamParser()
            var output = ""
            var reasoning = ""
            @MainActor
            func apply(_ update: ReasoningStreamParser.Update) {
                if !update.answerDelta.isEmpty {
                    output += update.answerDelta
                    model.append(update.answerDelta)
                }
                if !update.reasoningDelta.isEmpty {
                    reasoning += update.reasoningDelta
                    model.appendReasoning(update.reasoningDelta)
                }
            }
            do {
                let stream = try await client.stream(prompt: prompt)
                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .delta(let delta):
                        apply(parser.feed(delta))
                    case .done:
                        apply(parser.finish())
                        model.finish()
                        onSuccess?(output, reasoning)
                        return
                    case .failed(let message):
                        model.fail(message)
                        return
                    }
                }
                if !Task.isCancelled {
                    apply(parser.finish())
                    model.finish()
                    onSuccess?(output, reasoning)
                }
            } catch is CancellationError {
                // Superseded by a newer run; leave the model to that run.
            } catch {
                if !Task.isCancelled {
                    model.fail(friendlyErrorMessage(error))
                }
            }
        }
    }

    func renderPrompt(task: PromptTask, captured: CapturedText) -> String {
        let glossary = task.includeGlossary ? glossaryStore.promptBlock() : ""
        return TemplateRenderer.render(task.template,
                                       values: captured.templateValues(glossary: glossary))
    }

    private func recordHistory(task: PromptTask,
                               context: CaptureContext?,
                               output: String,
                               reasoning: String,
                               client: LLMClient) {
        guard settings.historyEnabled else { return }
        historyStore.append(HistoryEntry(taskName: task.name,
                                         appName: context?.text.appName,
                                         bundleID: context?.text.bundleID,
                                         input: context?.text.selected ?? "",
                                         contextBefore: context?.text.before ?? "",
                                         contextAfter: context?.text.after ?? "",
                                         output: output,
                                         reasoning: reasoning,
                                         providerName: client.providerName,
                                         model: client.modelName))
    }

    // MARK: - Playground

    func runPlayground(input: String,
                       task: PromptTask,
                       profileID: UUID?,
                       model: StreamRunModel) {
        let profile = settings.profile(withID: profileID) ?? settings.resolvedProfile(for: task)
        guard let profile else {
            model.begin(title: task.name, canInsert: false)
            model.fail("No provider is configured. Open Settings → Providers.")
            return
        }
        let captured = CapturedText(selected: input,
                                    appName: "Playground",
                                    source: .playground)
        let prompt = renderPrompt(task: task, captured: captured)
        let client = makeClient(profile: profile)
        model.begin(title: task.name, canInsert: false)
        playgroundRun?.cancel()
        playgroundRun = streamTask(prompt: prompt, client: client, into: model) { [weak self] output, reasoning in
            guard let self, self.settings.historyEnabled else { return }
            self.historyStore.append(HistoryEntry(taskName: task.name,
                                                  appName: nil,
                                                  bundleID: nil,
                                                  input: input,
                                                  output: output,
                                                  reasoning: reasoning,
                                                  providerName: client.providerName,
                                                  model: client.modelName))
        }
    }

    func stopPlayground(model: StreamRunModel) {
        playgroundRun?.cancel()
        playgroundRun = nil
        if model.isStreaming {
            model.finish()
        }
    }

    // MARK: - Providers & OAuth

    func makeClient(profile: ProviderProfile) -> LLMClient {
        switch profile.type {
        case .openAICompatible:
            return OpenAICompatClient(profile: profile,
                                      apiKey: Keychain.apiKey(profileID: profile.id) ?? "")
        case .codexOAuth:
            return CodexClient(profile: profile, manager: tokenManager(for: profile))
        case .xaiOAuth:
            return XAIClient(profile: profile, manager: tokenManager(for: profile))
        }
    }

    func tokenManager(for profile: ProviderProfile) -> OAuthTokenManager {
        if let existing = tokenManagers[profile.id], existing.type == profile.type {
            return existing
        }
        let manager = OAuthTokenManager(profileID: profile.id, type: profile.type)
        tokenManagers[profile.id] = manager
        return manager
    }

    /// Browser sign-in for an OAuth profile; stores tokens in the Keychain.
    func signInWithBrowser(profile: ProviderProfile) async throws {
        let tokens: OAuthTokens
        switch profile.type {
        case .codexOAuth:
            tokens = try await CodexAuthFlow.signIn()
        case .xaiOAuth:
            tokens = try await XAIAuthFlow.signIn()
        case .openAICompatible:
            throw AuthFlowError.notAnOAuthProvider
        }
        await tokenManager(for: profile).store(tokens)
        objectWillChange.send()
    }

    /// Imports an existing CLI login (~/.codex/auth.json or ~/.grok/auth.json).
    func importCLICredentials(profile: ProviderProfile) async throws {
        let fileURL: URL
        let tokens: OAuthTokens?
        switch profile.type {
        case .codexOAuth:
            fileURL = CodexWire.cliAuthFileURL
            guard let data = try? Data(contentsOf: fileURL) else {
                throw AuthFlowError.cliCredentialsNotFound(fileURL.path)
            }
            tokens = CodexWire.importCLITokens(json: data)
        case .xaiOAuth:
            fileURL = XAIWire.cliAuthFileURL
            guard let data = try? Data(contentsOf: fileURL) else {
                throw AuthFlowError.cliCredentialsNotFound(fileURL.path)
            }
            tokens = XAIWire.importCLITokens(json: data)
        case .openAICompatible:
            throw AuthFlowError.notAnOAuthProvider
        }
        guard let tokens else {
            throw AuthFlowError.cliCredentialsUnreadable(fileURL.path)
        }
        await tokenManager(for: profile).store(tokens)
        objectWillChange.send()
    }

    func signOut(profile: ProviderProfile) async {
        await tokenManager(for: profile).clear()
        objectWillChange.send()
    }

    func oauthTokens(profile: ProviderProfile) async -> OAuthTokens? {
        await tokenManager(for: profile).currentTokens()
    }

    /// Fetches the model candidates the provider's catalog endpoint offers.
    /// `apiKeyOverride` lets the settings view pass its unsaved draft key for
    /// API-key profiles; OAuth profiles resolve tokens via their manager.
    func fetchModelCandidates(profile: ProviderProfile,
                              apiKeyOverride: String? = nil) async throws -> [String] {
        switch profile.type {
        case .openAICompatible:
            let apiKey = apiKeyOverride ?? Keychain.apiKey(profileID: profile.id) ?? ""
            let request = try OpenAICompatWire.modelsRequest(baseURL: profile.baseURL,
                                                             apiKey: apiKey)
            return OpenAICompatWire.modelIDs(fromModelsResponse: try await modelsData(request))
        case .codexOAuth:
            let data = try await modelsData(manager: tokenManager(for: profile)) { tokens in
                try CodexWire.modelsRequest(tokens: tokens, clientVersion: AppVersion.short)
            }
            return CodexWire.modelIDs(fromModelsResponse: data)
        case .xaiOAuth:
            let data = try await modelsData(manager: tokenManager(for: profile)) { tokens in
                try XAIWire.modelsRequest(tokens: tokens, clientVersion: AppVersion.short)
            }
            return XAIWire.modelIDs(fromModelsResponse: data)
        }
    }

    /// Executes a models request; non-200 becomes a readable LLMError.http.
    private func modelsData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LLMError.http(status: http.statusCode,
                                message: OpenAICompatWire.errorMessage(status: http.statusCode,
                                                                       body: data))
        }
        return data
    }

    /// OAuth variant: on 401, force-refresh once and retry (same shape as
    /// `streamWithRefresh`).
    private func modelsData(manager: OAuthTokenManager,
                            makeRequest: @Sendable (OAuthTokens) throws -> URLRequest)
        async throws -> Data {
        var tokens = try await manager.validTokens()
        do {
            return try await modelsData(try makeRequest(tokens))
        } catch LLMError.http(let status, _) where status == 401 {
            tokens = try await manager.forceRefresh()
            return try await modelsData(try makeRequest(tokens))
        }
    }

    func deleteProfile(id: UUID) {
        Keychain.purge(profileID: id)
        tokenManagers[id] = nil
        settings.removeProfile(id: id)
    }
}

func friendlyErrorMessage(_ error: Error) -> String {
    if let llmError = error as? LLMError {
        return llmError.errorDescription ?? String(describing: error)
    }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        return "Network error: \(nsError.localizedDescription)"
    }
    return nsError.localizedDescription
}
