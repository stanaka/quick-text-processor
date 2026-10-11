import QTPCore
import SwiftUI

struct ProviderSettingsView: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var settings: SettingsStore

    @State private var selectionID: UUID?
    @State private var apiKeyDraft = ""
    @State private var apiKeyStored = false
    @State private var oauthTokens: OAuthTokens?
    /// Model lists fetched from the providers' catalog endpoints, keyed by
    /// profile id; transient by design (re-fetched per settings session).
    @State private var fetchedModels: [UUID: [String]] = [:]
    @State private var busy = false
    @State private var flowError: String?
    @State private var flowInfo: String?

    var body: some View {
        HStack(spacing: 0) {
            profileList
            Divider()
            if let profile = selectedProfile {
                profileForm(profile)
            } else {
                VStack {
                    Spacer()
                    Text("Select or add a provider profile")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if selectionID == nil {
                selectionID = settings.defaultProfileID ?? settings.profiles.first?.id
            }
            reloadSecrets()
        }
        .onChange(of: selectionID) { _, _ in
            flowError = nil
            flowInfo = nil
            reloadSecrets()
        }
    }

    private var selectedProfile: ProviderProfile? {
        settings.profile(withID: selectionID)
    }

    // MARK: - List

    private var profileList: some View {
        VStack(spacing: 0) {
            List(settings.profiles, selection: $selectionID) { profile in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(profile.name).lineLimit(1)
                        if profile.id == settings.defaultProfileID {
                            Text("default")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.2), in: Capsule())
                        }
                    }
                    Text(profile.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(profile.id)
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Menu {
                    ForEach(ProviderType.allCases, id: \.self) { type in
                        Button(type.displayName) { addProfile(type) }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    if let id = selectionID {
                        controller.deleteProfile(id: id)
                        selectionID = settings.profiles.first?.id
                    }
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectionID == nil || settings.profiles.count <= 1)

                Spacer()
            }
            .padding(8)
        }
        .frame(width: 250)
    }

    private func addProfile(_ type: ProviderType) {
        let baseURL = type == .openAICompatible ? "https://api.openai.com" : ""
        let name: String
        switch type {
        case .openAICompatible: name = "OpenAI-compatible"
        case .codexOAuth: name = "ChatGPT (Codex)"
        case .xaiOAuth: name = "Grok (xAI)"
        }
        let profile = ProviderProfile(name: name, type: type, baseURL: baseURL)
        settings.upsert(profile)
        selectionID = profile.id
    }

    // MARK: - Form

    private func profileForm(_ profile: ProviderProfile) -> some View {
        Form {
            Section("Profile") {
                TextField("Name", text: profileBinding(profile.id, \.name, fallback: ""))
                LabeledContent("Type", value: profile.type.displayName)
                modelRow(profile)
                Toggle("Use as default provider", isOn: Binding(
                    get: { settings.defaultProfileID == profile.id },
                    set: { isOn in
                        if isOn {
                            settings.defaultProfileID = profile.id
                        }
                    }
                ))
                .disabled(settings.defaultProfileID == profile.id)
            }

            switch profile.type {
            case .openAICompatible:
                apiKeySection(profile)
            case .codexOAuth:
                oauthSection(profile,
                             accountLabel: "ChatGPT",
                             cliName: "Codex CLI",
                             cliPath: CodexWire.cliAuthFileURL.path)
            case .xaiOAuth:
                oauthSection(profile,
                             accountLabel: "xAI / Grok",
                             cliName: "Grok CLI",
                             cliPath: XAIWire.cliAuthFileURL.path)
            }
        }
        .formStyle(.grouped)
    }

    private func modelRow(_ profile: ProviderProfile) -> some View {
        HStack(spacing: 6) {
            TextField("Model", text: profileBinding(profile.id, \.model, fallback: ""))
                .autocorrectionDisabled()
            if let candidates = modelCandidates(profile), !candidates.isEmpty {
                Menu {
                    ForEach(candidates, id: \.self) { candidate in
                        Button {
                            profileBinding(profile.id, \.model, fallback: "").wrappedValue = candidate
                        } label: {
                            if candidate == profile.model {
                                Label(candidate, systemImage: "checkmark")
                            } else {
                                Text(candidate)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Pick a model (free-text entry stays possible)")
            }
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    fetchModels(profile)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Fetch the provider's model list")
            }
        }
    }

    /// Fetched list when available, else the wire-level fallback candidates
    /// for the OAuth providers (their catalogs are fixed endpoints).
    private func modelCandidates(_ profile: ProviderProfile) -> [String]? {
        if let fetched = fetchedModels[profile.id] { return fetched }
        switch profile.type {
        case .openAICompatible: return nil
        case .codexOAuth: return CodexWire.fallbackModelCandidates
        case .xaiOAuth: return XAIWire.fallbackModelCandidates
        }
    }

    private func apiKeySection(_ profile: ProviderProfile) -> some View {
        Section("OpenAI-compatible endpoint") {
            TextField("Base URL", text: profileBinding(profile.id, \.baseURL, fallback: ""))
                .autocorrectionDisabled()
            Text("Examples: https://api.openai.com · https://api.x.ai · http://localhost:11434 (Ollama)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                SecureField("API key", text: $apiKeyDraft)
                Button("Save") {
                    Keychain.setAPIKey(apiKeyDraft, profileID: profile.id)
                    apiKeyStored = !apiKeyDraft.isEmpty
                    flowInfo = apiKeyDraft.isEmpty ? "API key removed." : "API key saved to the Keychain."
                }
            }
            if apiKeyStored {
                Label("An API key is stored in the Keychain for this profile.", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            feedback
        }
    }

    private func oauthSection(_ profile: ProviderProfile,
                              accountLabel: String,
                              cliName: String,
                              cliPath: String) -> some View {
        Section("\(accountLabel) account") {
            HStack(spacing: 8) {
                if let tokens = oauthTokens {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in")
                        if let expires = tokens.expiresAt {
                            Text("Access token expires \(expires, format: .relative(presentation: .named)) (refreshed automatically)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Sign in with Browser…") { signIn(profile) }
                    .disabled(busy)
                Button("Import from \(cliName)") { importCLI(profile) }
                    .disabled(busy)
                    .help("Reads \(cliPath) (never modified)")
                if oauthTokens != nil {
                    Button("Sign Out", role: .destructive) { signOut(profile) }
                        .disabled(busy)
                }
                if busy {
                    ProgressView().controlSize(.small)
                }
            }

            Text("Uses your \(accountLabel) subscription through the same endpoints as the official CLI. Check the provider's terms of service for this kind of use.")
                .font(.caption)
                .foregroundStyle(.secondary)

            feedback
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let flowError {
            Label(flowError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        if let flowInfo {
            Label(flowInfo, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func profileBinding<T>(_ id: UUID,
                                   _ keyPath: WritableKeyPath<ProviderProfile, T>,
                                   fallback: T) -> Binding<T> {
        Binding(
            get: { settings.profile(withID: id)?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard var profile = settings.profile(withID: id) else { return }
                profile[keyPath: keyPath] = newValue
                settings.upsert(profile)
            }
        )
    }

    // MARK: - Actions

    private func fetchModels(_ profile: ProviderProfile) {
        busy = true
        flowError = nil
        flowInfo = nil
        Task {
            do {
                let apiKeyOverride = profile.type == .openAICompatible
                    ? apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
                let models = try await controller.fetchModelCandidates(profile: profile,
                                                                       apiKeyOverride: apiKeyOverride)
                if models.isEmpty {
                    flowError = "The endpoint returned no models."
                } else {
                    fetchedModels[profile.id] = models
                    flowInfo = "Loaded \(models.count) model\(models.count == 1 ? "" : "s")."
                }
            } catch {
                flowError = friendlyErrorMessage(error)
            }
            busy = false
        }
    }

    private func signIn(_ profile: ProviderProfile) {
        busy = true
        flowError = nil
        flowInfo = "Complete the sign-in in your browser…"
        Task {
            do {
                try await controller.signInWithBrowser(profile: profile)
                flowInfo = "Signed in."
            } catch {
                flowError = friendlyErrorMessage(error)
                flowInfo = nil
            }
            busy = false
            await reloadTokens(profile)
        }
    }

    private func importCLI(_ profile: ProviderProfile) {
        busy = true
        flowError = nil
        flowInfo = nil
        Task {
            do {
                try await controller.importCLICredentials(profile: profile)
                flowInfo = "CLI credentials imported."
            } catch {
                flowError = friendlyErrorMessage(error)
            }
            busy = false
            await reloadTokens(profile)
        }
    }

    private func signOut(_ profile: ProviderProfile) {
        Task {
            await controller.signOut(profile: profile)
            flowInfo = "Signed out."
            await reloadTokens(profile)
        }
    }

    private func reloadSecrets() {
        guard let profile = selectedProfile else {
            apiKeyDraft = ""
            apiKeyStored = false
            oauthTokens = nil
            return
        }
        let stored = Keychain.apiKey(profileID: profile.id)
        apiKeyDraft = stored ?? ""
        apiKeyStored = stored?.isEmpty == false
        oauthTokens = nil
        Task { await reloadTokens(profile) }
    }

    private func reloadTokens(_ profile: ProviderProfile) async {
        guard profile.type.usesOAuth else { return }
        let tokens = await controller.oauthTokens(profile: profile)
        if selectionID == profile.id {
            oauthTokens = tokens
        }
    }
}
