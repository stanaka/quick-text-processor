import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProviderSettingsView()
                .tabItem { Label("Providers", systemImage: "brain") }
            TaskSettingsView()
                .tabItem { Label("Tasks", systemImage: "wand.and.stars") }
        }
        .padding(12)
    }
}
