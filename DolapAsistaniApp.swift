import SwiftUI
import SwiftData

@main
struct DolapAsistaniApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [ClothingItem.self, SavedOutfit.self])
    }
}
