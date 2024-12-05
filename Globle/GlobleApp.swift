import SwiftUI
import SwiftData

@main
struct GlobleApp: App {
    init() {
        // Disable CA Event warning
        UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // Add your model types here if needed for the globe app
            // For now, we'll keep Item.self as a placeholder
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.colorScheme, .dark) // Set dark mode for better globe visibility
        }
        .modelContainer(sharedModelContainer)
    }
}


