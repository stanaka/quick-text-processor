import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case playground
    case history
    case dictionary
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playground: return "Playground"
        case .history: return "History"
        case .dictionary: return "Dictionary"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .playground: return "wand.and.stars"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @State private var selection: SidebarSection? = .playground

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch selection ?? .playground {
            case .playground:
                PlaygroundView()
            case .history:
                HistoryView()
            case .dictionary:
                DictionaryView()
            case .settings:
                SettingsView()
            }
        }
        .navigationTitle("QuickTextProcessor")
    }
}
