import SwiftUI

@main
struct QuickTextProcessorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("QuickTextProcessor", id: "main") {
            MainView()
                .environmentObject(delegate.controller)
                .environmentObject(delegate.controller.settings)
                .environmentObject(delegate.controller.taskStore)
                .environmentObject(delegate.controller.historyStore)
                .environmentObject(delegate.controller.glossaryStore)
        }
        .defaultSize(width: 940, height: 640)
    }
}
