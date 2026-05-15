import SwiftUI
import SwiftData

@main
struct MBTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Tracker", systemImage: "timer") {
                    ContentView()
                }
                Tab("Stats", systemImage: "chart.bar") {
                    StatsView()
                }
                Tab("Settings", systemImage: "gearshape") {
                    SettingsView()
                }
            }
            .modelContainer(for: StudySession.self)
        }
    }
}
