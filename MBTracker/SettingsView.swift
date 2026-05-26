import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct AppBackup: Codable {
    var exportDate: Date
    var sessions: [SessionBackup]
    var snapshots: [String: Int]
    var lastLearnedIndex: Int
    var todayStartIndex: Int
    var todayDateKey: String
    var onboardingDone: Bool
    var onboardingLearnedIndex: Int
    var onboardingDateKey: String
    var onboardingIndexConfirmed: Bool
    var buildTargetMin: Double
    var buildTargetMax: Double
    var getTargetMin: Double
    var getTargetMax: Double
    var activateTargetMin: Double
    var activateTargetMax: Double
}

private struct SessionBackup: Codable {
    var date: Date
    var activity: String
    var durationSeconds: Double
}

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
    @AppStorage("onboardingLearnedIndex") private var onboardingLearnedIndex = 0
    @AppStorage("onboardingDateKey") private var onboardingDateKey = ""
    @AppStorage("onboardingIndexConfirmed") private var onboardingIndexConfirmed = false
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [StudySession]

    @State private var showClearConfirmation = false
    @State private var showImportPicker = false
    @State private var showImportSuccess = false
    @State private var importErrorMessage: String? = nil

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
                    ShareLink(item: generateBackupFile()) {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Import backup", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export saves all sessions, progress, and settings to a JSON file. Import restores everything from a previous export.")
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
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importBackup(from: url)
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                }
            }
            .alert("Import successful", isPresented: $showImportSuccess) {
                Button("OK") {}
            } message: {
                Text("All sessions, progress, and settings have been restored.")
            }
            .alert("Import failed", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(importErrorMessage ?? "")
            }
        }
    }

    // MARK: - Export

    private func generateBackupFile() -> URL {
        let backup = AppBackup(
            exportDate: Date(),
            sessions: sessions.map { SessionBackup(date: $0.date, activity: $0.activity, durationSeconds: $0.durationSeconds) },
            snapshots: loadDailySnapshots(),
            lastLearnedIndex: lastLearnedIndex,
            todayStartIndex: todayStartIndex,
            todayDateKey: todayDateKey,
            onboardingDone: onboardingDone,
            onboardingLearnedIndex: onboardingLearnedIndex,
            onboardingDateKey: onboardingDateKey,
            onboardingIndexConfirmed: onboardingIndexConfirmed,
            buildTargetMin: buildTargetMin,
            buildTargetMax: buildTargetMax,
            getTargetMin: getTargetMin,
            getTargetMax: getTargetMax,
            activateTargetMin: activateTargetMin,
            activateTargetMax: activateTargetMax
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = (try? encoder.encode(backup)) ?? Data()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "mbtracker-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }

    // MARK: - Import

    private func importBackup(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importErrorMessage = "Could not access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            importErrorMessage = "Could not read the file."
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(AppBackup.self, from: data) else {
            importErrorMessage = "The file is not a valid MBTracker backup."
            return
        }

        // Clear existing sessions
        for session in sessions { modelContext.delete(session) }
        try? modelContext.save()

        // Restore sessions
        for s in backup.sessions {
            modelContext.insert(StudySession(date: s.date, activity: s.activity, durationSeconds: s.durationSeconds))
        }
        try? modelContext.save()

        // Restore snapshots and AppStorage
        saveDailySnapshots(backup.snapshots)
        lastLearnedIndex = backup.lastLearnedIndex
        todayStartIndex = backup.todayStartIndex
        todayDateKey = backup.todayDateKey
        onboardingDone = backup.onboardingDone
        onboardingLearnedIndex = backup.onboardingLearnedIndex
        onboardingDateKey = backup.onboardingDateKey
        onboardingIndexConfirmed = backup.onboardingIndexConfirmed
        buildTargetMin = backup.buildTargetMin
        buildTargetMax = backup.buildTargetMax
        getTargetMin = backup.getTargetMin
        getTargetMax = backup.getTargetMax
        activateTargetMin = backup.activateTargetMin
        activateTargetMax = backup.activateTargetMax

        showImportSuccess = true
    }

    // MARK: - Clear

    private func clearAllData() {
        for session in sessions { modelContext.delete(session) }
        try? modelContext.save()
        saveDailySnapshots([:])
        lastLearnedIndex = 0
        todayStartIndex = 0
        todayDateKey = ""
        onboardingDone = false
        onboardingLearnedIndex = 0
        onboardingDateKey = ""
        onboardingIndexConfirmed = false
    }

    // MARK: - Helpers

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
