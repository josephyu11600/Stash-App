import SwiftUI
import SwiftData

@main
struct StashApp: App {
    @State private var tracker = EnrichmentTracker()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(tracker)
        }
        .modelContainer(for: Item.self)
    }
}
