import Combine
import Foundation
import QTPCore
import ServiceManagement

/// App-wide settings, backed by UserDefaults. Provider profiles are stored as
/// JSON here; their secrets live in the Keychain (see Keychain.swift).
@MainActor
final class SettingsStore: ObservableObject {

    private enum Keys {
        static let schemaVersion = "schemaVersion"
        static let hotkey = "hotkey"
        static let contextRadius = "contextRadius"
        static let historyEnabled = "historyEnabled"
        static let historyLimit = "historyLimit"
        static let profiles = "providerProfiles"
        static let defaultProfileID = "defaultProviderProfileID"
    }

    private let defaults: UserDefaults

    @Published var hotkey: KeyCombo {
        didSet { defaults.set(try? JSONEncoder().encode(hotkey), forKey: Keys.hotkey) }
    }

    /// Context window per side, in UTF-16 units.
    @Published var contextRadius: Int {
        didSet { defaults.set(contextRadius, forKey: Keys.contextRadius) }
    }

    @Published var historyEnabled: Bool {
        didSet { defaults.set(historyEnabled, forKey: Keys.historyEnabled) }
    }

    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) }
    }

    @Published var profiles: [ProviderProfile] {
        didSet { defaults.set(try? JSONEncoder().encode(profiles), forKey: Keys.profiles) }
    }

    @Published var defaultProfileID: UUID? {
        didSet { defaults.set(defaultProfileID?.uuidString, forKey: Keys.defaultProfileID) }
    }

    /// Mirrors SMAppService registration.
    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Roll back so the toggle reflects reality.
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Keys.hotkey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            hotkey = combo
        } else {
            hotkey = .default
        }

        let radius = defaults.object(forKey: Keys.contextRadius) as? Int
        contextRadius = radius ?? 400

        historyEnabled = (defaults.object(forKey: Keys.historyEnabled) as? Bool) ?? true
        historyLimit = (defaults.object(forKey: Keys.historyLimit) as? Int) ?? 500

        var loadedProfiles: [ProviderProfile] = []
        if let data = defaults.data(forKey: Keys.profiles),
           let decoded = try? JSONDecoder().decode([ProviderProfile].self, from: data) {
            loadedProfiles = decoded
        }
        if loadedProfiles.isEmpty {
            loadedProfiles = [ProviderProfile(name: "OpenAI", type: .openAICompatible)]
        }
        profiles = loadedProfiles

        if let raw = defaults.string(forKey: Keys.defaultProfileID),
           let id = UUID(uuidString: raw),
           loadedProfiles.contains(where: { $0.id == id }) {
            defaultProfileID = id
        } else {
            defaultProfileID = loadedProfiles.first?.id
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled

        if defaults.object(forKey: Keys.schemaVersion) == nil {
            defaults.set(1, forKey: Keys.schemaVersion)
        }

        // didSet observers do not fire during init, so persist the seeded
        // profile explicitly — its UUID keys the Keychain entries and must
        // survive relaunches.
        if defaults.data(forKey: Keys.profiles) == nil {
            defaults.set(try? JSONEncoder().encode(loadedProfiles), forKey: Keys.profiles)
        }
        if defaults.string(forKey: Keys.defaultProfileID) == nil {
            defaults.set(defaultProfileID?.uuidString, forKey: Keys.defaultProfileID)
        }
    }

    // MARK: - Profile helpers

    func profile(withID id: UUID?) -> ProviderProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    var defaultProfile: ProviderProfile? {
        profile(withID: defaultProfileID) ?? profiles.first
    }

    /// The profile a task resolves to (its override, else the app default).
    func resolvedProfile(for task: PromptTask) -> ProviderProfile? {
        profile(withID: task.providerProfileID) ?? defaultProfile
    }

    func upsert(_ profile: ProviderProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        if defaultProfileID == nil {
            defaultProfileID = profile.id
        }
    }

    func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if defaultProfileID == id {
            defaultProfileID = profiles.first?.id
        }
    }
}
