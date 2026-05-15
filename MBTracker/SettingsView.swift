import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("buildTargetMin") private var buildTargetMin = 0.70
    @AppStorage("buildTargetMax") private var buildTargetMax = 0.80
    @AppStorage("getTargetMin") private var getTargetMin = 0.15
    @AppStorage("getTargetMax") private var getTargetMax = 0.25
    @AppStorage("activateTargetMin") private var activateTargetMin = 0.05
    @AppStorage("activateTargetMax") private var activateTargetMax = 0.10
    @AppStorage("lastLearnedIndex") private var lastLearnedIndex = 0
    @AppStorage("todayStartIndex") private var todayStartIndex = 0
    @AppStorage("todayDateKey") private var todayDateKey = ""
    @AppStorage("onboardingDone") private var onboardingDone = false
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [StudySession]

    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Build") {
                    percentSlider("Min", value: $buildTargetMin)
                    percentSlider("Max", value: $buildTargetMax)
                }
                Section("Get") {
                    percentSlider("Min", value: $getTargetMin)
                    percentSlider("Max", value: $getTargetMax)
                }
                Section("Activate") {
                    percentSlider("Min", value: $activateTargetMin)
                    percentSlider("Max", value: $activateTargetMax)
                }
                Section {
                    Button("Clear all data", role: .destructive) {
                        showClearConfirmation = true
                    }
                } footer: {
                    Text("Deletes all sessions and snapshots and resets the app to its initial state.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Clear all data?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear everything", role: .destructive) { clearAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private func clearAllData() {
        for session in sessions { modelContext.delete(session) }
        try? modelContext.save()
        saveDailySnapshots([:])
        lastLearnedIndex = 0
        todayStartIndex = 0
        todayDateKey = ""
        onboardingDone = false
    }

    private func percentSlider(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0.01...0.99, step: 0.01)
        }
    }
}
