import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [StudySession]

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
    @AppStorage("timerActivity") private var storedTimerActivity = ""
    @AppStorage("timerStartTime") private var storedTimerStart: Double = 0

    @State private var runningActivity: String? = nil
    @State private var startTime: Date = Date()
    @State private var elapsed: Double = 0
    @State private var capturedElapsed: Double = 0
    @State private var showStopSheet = false
    @State private var pickerIndex: Int = 0
    @State private var editRequest: EditRequest? = nil
    @State private var showActivityInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ratioSection

                    if runningActivity == nil {
                        startButtonsSection
                    } else {
                        timerSection
                    }
                }
                .padding()
            }
            .navigationTitle("MBTracker")
            .sheet(isPresented: $showStopSheet) {
                stopBuildSheet
            }
            .sheet(item: $editRequest) { request in
                EditSheetView(
                    editingActivity: request.activity,
                    minDate: onboardingDate,
                    onCancel: { editRequest = nil },
                    onSave: { date, hours, minutes, itemIndex in
                        saveEditedTotal(activity: request.activity, date: date, hours: hours, minutes: minutes, itemIndex: itemIndex)
                        editRequest = nil
                    },
                    loadData: { activity, date in
                        loadDayDataForEdit(activity: activity, date: date)
                    },
                    buildRange: { date in
                        buildEditRange(for: date)
                    }
                )
            }
            .task {
                while true {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if runningActivity != nil {
                        elapsed = Date().timeIntervalSince(startTime)
                    }
                }
            }
            .onAppear {
                resetStartIndexIfNewDay()
                migrateOnboardingIfNeeded()
                restoreTimerIfNeeded()
            }
            .sheet(isPresented: Binding(
                get: { !onboardingDone },
                set: { if !$0 { onboardingDone = true } }
            )) {
                onboardingSheet
            }
            .sheet(isPresented: Binding(
                get: { onboardingDone && !onboardingIndexConfirmed },
                set: { if !$0 { onboardingIndexConfirmed = true } }
            )) {
                startingCharacterPrompt
            }
        }
    }

    // MARK: - Today's data

    // Calendar-day midnight of the onboarding day; .distantPast if not yet set.
    private var onboardingDate: Date {
        guard !onboardingDateKey.isEmpty,
              let d = dateFromSnapshotKey(onboardingDateKey) else { return .distantPast }
        return Calendar.current.startOfDay(for: d)
    }

    private func studyDayStart() -> Date { studyDayStart(for: Date()) }

    private func studyDayStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let at3am = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: date)!
        return date >= at3am ? at3am : calendar.date(byAdding: .day, value: -1, to: at3am)!
    }

    // Converts a calendar date (e.g. from DatePicker, which may return midnight) to the correct study day start
    private func studyDayStartForPickerDate(_ date: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = 12
        let noon = Calendar.current.date(from: comps)!
        return studyDayStart(for: noon)
    }

    private func resetStartIndexIfNewDay() {
        let key = studyDayStart().formatted(date: .abbreviated, time: .omitted)
        if todayDateKey != key {
            if !todayDateKey.isEmpty {
                let previousDayStart = Calendar.current.date(byAdding: .day, value: -1, to: studyDayStart())!
                recordDailySnapshot(for: previousDayStart, endIndex: lastLearnedIndex)
            }
            todayDateKey = key
            todayStartIndex = lastLearnedIndex
        }
    }

    // For users who onboarded before this field existed, infer onboarding date from
    // the earliest daily snapshot. onboardingLearnedIndex stays 0 as a safe fallback.
    private func migrateOnboardingIfNeeded() {
        guard onboardingDone && onboardingDateKey.isEmpty else { return }
        let snaps = loadDailySnapshots()
        if let earliest = snaps.keys.sorted().first {
            onboardingDateKey = earliest
        } else {
            onboardingDateKey = snapshotDateKey(for: studyDayStart())
        }
    }

    private var learnedTodayItems: [LearningItem] {
        guard lastLearnedIndex > todayStartIndex else { return [] }
        let end = min(lastLearnedIndex, allLearningItems.count)
        let start = min(todayStartIndex, end)
        return Array(allLearningItems[start..<end])
    }

    private var learnedTodayChars: Int { learnedTodayItems.filter(\.isCharacter).count }
    private var learnedTodayWords: Int { learnedTodayItems.filter { !$0.isCharacter }.count }

    private var todaySessions: [StudySession] {
        return sessions.filter { $0.date >= studyDayStart() }
    }

    private func todayMinutes(_ activity: String) -> Double {
        let saved = todaySessions
            .filter { $0.activity == activity }
            .reduce(0.0) { $0 + $1.durationSeconds }
        let live = (runningActivity == activity) ? elapsed : 0
        return (saved + live) / 60.0
    }

    private var totalMinutes: Double {
        todayMinutes("Build") + todayMinutes("Get") + todayMinutes("Activate")
    }

    private var currentLevel: Int {
        guard lastLearnedIndex > 0 else { return 1 }
        let idx = min(lastLearnedIndex - 1, allLearningItems.count - 1)
        return allLearningItems[idx].level
    }

    private var currentCharNumber: Int {
        allCharacters.filter { $0.id < lastLearnedIndex }.count
    }

    private func currentPct(_ activity: String) -> Double {
        guard totalMinutes > 0 else { return 0 }
        return todayMinutes(activity) / totalMinutes
    }

    private func minutesNeeded(activity: String, target: Double) -> Double? {
        let current = todayMinutes(activity)
        let total = totalMinutes
        guard total > 0 else { return nil }
        guard current / total < target else { return nil }
        let extra = (target * total - current) / (1 - target)
        return extra > 0 ? extra : nil
    }

    // MARK: - Ratio section

    private var ratioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's Ratios")
                    .font(.headline)
                Spacer()
                Button {
                    showActivityInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showActivityInfo) {
                activityInfoSheet
            }

            Text("Level \(currentLevel)  ·  Character \(currentCharNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            ratioRow(activity: "Build", color: .blue,
                     targetMin: buildTargetMin, targetMax: buildTargetMax)
            Divider()
            ratioRow(activity: "Get", color: .teal,
                     targetMin: getTargetMin, targetMax: getTargetMax)
            Divider()
            ratioRow(activity: "Activate", color: .indigo,
                     targetMin: activateTargetMin, targetMax: activateTargetMax)
            Divider()
            immerseRow
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var activityInfoSheet: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Build", systemImage: "circle.fill")
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                        Text("Going through Blueprint lessons · Making movies for new characters · Choosing sets, actors, and props · Generating living links for words · Doing flashcards from the lessons")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Get", systemImage: "circle.fill")
                            .foregroundStyle(.teal)
                            .fontWeight(.semibold)
                        Text("Reading Kickstarter or Blueprint sentences · Reading along while listening to the audio")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Activate", systemImage: "circle.fill")
                            .foregroundStyle(.indigo)
                            .fontWeight(.semibold)
                        Text("Shadowing · Basic recall flashcards (English → Chinese) · Tutoring sessions")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Immerse", systemImage: "circle.fill")
                            .foregroundStyle(.purple)
                            .fontWeight(.semibold)
                        Text("Passive listening while doing something else — e.g. driving or household chores. Usually Blueprint sentences. Goal: 1 hour per day.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Activity Types")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showActivityInfo = false }
                }
            }
        }
    }

    private var immerseRow: some View {
        HStack {
            Circle().fill(Color.purple).frame(width: 8, height: 8)
            Text("Immerse")
                .fontWeight(.medium)
            Spacer()
            Text(formatMinutes(todayMinutes("Immerse")))
                .font(.caption)
                .foregroundStyle(.secondary)
            editButton(for: "Immerse")
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func ratioRow(activity: String, color: Color, targetMin: Double, targetMax: Double) -> some View {
        let mins = todayMinutes(activity)
        let pct = currentPct(activity)
        let inRange = pct >= targetMin && pct <= targetMax
        let aboveRange = pct > targetMax
        let needed = minutesNeeded(activity: activity, target: targetMin)

        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(activity)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int((pct * 100).rounded()))%")
                    .fontWeight(.semibold)
                    .foregroundStyle(inRange ? .green : (aboveRange ? .orange : .red))
                Text("(\(Int(targetMin * 100))–\(Int(targetMax * 100))%)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                editButton(for: activity)
            }
            HStack {
                Text(formatMinutes(mins))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if activity == "Build" {
                    Text("· \(learnedTodayChars) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let n = needed {
                    Text("+\(Int(n.rounded(.up))) min to reach \(Int(targetMin * 100))%")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func editButton(for activity: String) -> some View {
        Button {
            editRequest = EditRequest(activity: activity)
        } label: {
            Image(systemName: "pencil.circle")
                .foregroundStyle(.blue)
                .font(.subheadline)
        }
        .disabled(runningActivity == activity)
    }

    // MARK: - Edit sheet helpers

    private func loadDayDataForEdit(activity: String, date: Date) -> (hours: Int, minutes: Int, itemIndex: Int) {
        let dayStart = studyDayStartForPickerDate(date)
        let nextDayStart = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let daySessions = sessions.filter { $0.activity == activity && $0.date >= dayStart && $0.date < nextDayStart }
        let totalSecs = daySessions.reduce(0.0) { $0 + $1.durationSeconds }
        let hours = Int(totalSecs) / 3600
        let minutes = (Int(totalSecs) % 3600) / 60
        var itemIndex = 0
        if activity == "Build" {
            let range = buildEditRange(for: date)
            let isToday = Calendar.current.isDateInToday(date)
            let storedExclusive = isToday
                ? lastLearnedIndex
                : (loadDailySnapshots()[snapshotDateKey(for: dayStart)] ?? (range.start + 1))
            let (lowerChar, upperChar) = charBoundsForPicker(range: range)
            let targetId = storedExclusive - 1
            let bestChar = allCharacters.last(where: { $0.id <= targetId && $0.id >= lowerChar.id && $0.id <= upperChar.id })
                ?? lowerChar
            itemIndex = bestChar.id
        }
        return (hours: hours, minutes: minutes, itemIndex: itemIndex)
    }

    // Returns an INCLUSIVE range of item ids the user can pick for the "last completed item" on a given day.
    // Picking the lower bound means 0 items learned that day; picking the upper bound means
    // all items up to the next day's start were completed.
    private func buildEditRange(for date: Date) -> (start: Int, end: Int) {
        let dayStart = studyDayStartForPickerDate(date)

        // Today: start = last item of yesterday (= todayStartIndex - 1 = "0 items today"),
        //         end = open-ended upward.
        if Calendar.current.isDateInToday(date) {
            return (start: max(0, todayStartIndex - 1), end: allLearningItems.count - 1)
        }

        let sorted = loadDailySnapshots().compactMap { key, value -> (date: Date, idx: Int)? in
            guard let d = dateFromSnapshotKey(key) else { return nil }
            return (d, value)
        }.sorted { $0.date < $1.date }

        // Upper bound: snapshot of next study day is exclusive → subtract 1 for inclusive picker.
        let nextDayStart = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let nextExclusive: Int
        if nextDayStart >= studyDayStart() {
            nextExclusive = todayStartIndex
        } else if let snap = sorted.filter({ $0.date >= nextDayStart }).first {
            nextExclusive = snap.idx
        } else {
            nextExclusive = min(allLearningItems.count, (sorted.last?.idx ?? 0) + 500)
        }
        let end = max(0, min(allLearningItems.count - 1, nextExclusive - 1))

        // Lower bound: snapshot of previous day is exclusive → subtract 1 for inclusive picker.
        // "Selecting start" means 0 items done this day (nextDay starts at same point as this day).
        if let prevSnap = sorted.filter({ $0.date < dayStart }).last {
            let start = max(0, prevSnap.idx - 1)
            return (start: min(start, end), end: max(start, end))
        } else {
            // No prior snapshot (first tracked day): onboarding value is the lower bound.
            let onboardingStart = max(0, onboardingLearnedIndex - 1)
            return (start: min(onboardingStart, end), end: end)
        }
    }

    private func saveEditedTotal(activity: String, date: Date, hours: Int, minutes: Int, itemIndex: Int) {
        let dayStart = studyDayStartForPickerDate(date)
        let nextDayStart = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let toDelete = sessions.filter { $0.activity == activity && $0.date >= dayStart && $0.date < nextDayStart }
        for s in toDelete { modelContext.delete(s) }
        let newDuration = Double(hours * 3600 + minutes * 60)
        if newDuration > 0 {
            modelContext.insert(StudySession(date: dayStart, activity: activity, durationSeconds: newDuration))
        }
        if activity == "Build" {
            let exclusiveValue = itemIndex + 1
            if Calendar.current.isDateInToday(date) {
                lastLearnedIndex = exclusiveValue
            } else {
                var snaps = loadDailySnapshots()
                snaps[snapshotDateKey(for: dayStart)] = exclusiveValue
                saveDailySnapshots(snaps)
            }
        }
    }

    // MARK: - Start buttons

    private var startButtonsSection: some View {
        VStack(spacing: 12) {
            Text("Start Tracking")
                .font(.headline)
            HStack(spacing: 12) {
                startButton("Build", color: .blue)
                startButton("Get", color: .teal)
            }
            HStack(spacing: 12) {
                startButton("Activate", color: .indigo)
                startButton("Immerse", color: .purple)
            }
        }
    }

    private func startButton(_ activity: String, color: Color) -> some View {
        Button(action: { startActivity(activity) }) {
            Text(activity)
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(color)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Running timer

    private var timerSection: some View {
        VStack(spacing: 16) {
            if let activity = runningActivity {
                Text(activity)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(formatElapsed(elapsed))
                    .font(.system(size: 52, weight: .light, design: .monospaced))

                Button(action: { stopActivity() }) {
                    Text("Stop")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Onboarding sheet

    private var onboardingSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Which character did you last complete?")
                        .font(.headline)
                    Text("Scroll to the last character you finished. We'll start counting from the next one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()

                Picker("Starting character", selection: $pickerIndex) {
                    ForEach(Array(allCharacters.enumerated()), id: \.element.id) { charIdx, item in
                        Text("\(charIdx + 1). \(item.simplified)")
                            .tag(item.id)
                    }
                }
                .pickerStyle(.wheel)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Start from beginning") {
                        if onboardingDateKey.isEmpty {
                            onboardingLearnedIndex = 0
                            onboardingDateKey = snapshotDateKey(for: studyDayStart())
                        }
                        lastLearnedIndex = 0
                        todayStartIndex = 0
                        onboardingDone = true
                        onboardingIndexConfirmed = true
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onboardingDateKey.isEmpty {
                            onboardingLearnedIndex = pickerIndex + 1
                            onboardingDateKey = snapshotDateKey(for: studyDayStart())
                        }
                        lastLearnedIndex = pickerIndex + 1
                        todayStartIndex = pickerIndex + 1
                        onboardingDone = true
                        onboardingIndexConfirmed = true
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Starting character prompt (shown once for users who migrated from old onboarding)

    private var startingCharacterPrompt: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("What character were you at when you started tracking?")
                        .font(.headline)
                    Text("Scroll to the last character you had completed before you began using MBTracker. Stored once and never changed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()

                Picker("Starting character", selection: $pickerIndex) {
                    ForEach(Array(allCharacters.enumerated()), id: \.element.id) { charIdx, item in
                        Text("\(charIdx + 1). \(item.simplified)")
                            .tag(item.id)
                    }
                }
                .pickerStyle(.wheel)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onboardingLearnedIndex = 0
                        onboardingIndexConfirmed = true
                    }
                    .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onboardingLearnedIndex = pickerIndex + 1
                        onboardingIndexConfirmed = true
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Stop Build sheet

    private var stopBuildSheet: some View {
        let lastCharIdx = allCharacters.lastIndex(where: { $0.id < lastLearnedIndex }) ?? 0
        let charWindowStart = max(0, lastCharIdx - 5)
        let charWindowEnd = min(allCharacters.count - 1, lastCharIdx + 300)
        let window = Array(allCharacters[charWindowStart...charWindowEnd])

        return NavigationStack {
            VStack(spacing: 0) {
                Text("Which character did you last complete?")
                    .font(.headline)
                    .padding()

                Picker("Last character", selection: $pickerIndex) {
                    ForEach(Array(window.enumerated()), id: \.element.id) { idx, item in
                        Text("\(charWindowStart + idx + 1). \(item.simplified)")
                            .tag(item.id)
                    }
                }
                .pickerStyle(.wheel)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showStopSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSession(activity: "Build", duration: capturedElapsed)
                        lastLearnedIndex = pickerIndex + 1
                        showStopSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func restoreTimerIfNeeded() {
        guard !storedTimerActivity.isEmpty, storedTimerStart > 0 else { return }
        runningActivity = storedTimerActivity
        startTime = Date(timeIntervalSinceReferenceDate: storedTimerStart)
        elapsed = Date().timeIntervalSince(startTime)
        if storedTimerActivity == "Build" {
            pickerIndex = allCharacters.last(where: { $0.id < lastLearnedIndex })?.id
                ?? allCharacters.first?.id ?? 0
        }
    }

    private func startActivity(_ activity: String) {
        runningActivity = activity
        startTime = Date()
        elapsed = 0
        storedTimerActivity = activity
        storedTimerStart = startTime.timeIntervalSinceReferenceDate
        if activity == "Build" {
            pickerIndex = allCharacters.last(where: { $0.id < lastLearnedIndex })?.id
                ?? allCharacters.first?.id ?? 0
        }
    }

    private func stopActivity() {
        guard let activity = runningActivity else { return }
        capturedElapsed = elapsed
        runningActivity = nil
        elapsed = 0
        storedTimerActivity = ""
        storedTimerStart = 0

        if activity == "Build" {
            showStopSheet = true
        } else {
            saveSession(activity: activity, duration: capturedElapsed)
        }
    }

    private func saveSession(activity: String, duration: Double) {
        let session = StudySession(date: Date(), activity: activity, durationSeconds: duration)
        modelContext.insert(session)
    }

    // MARK: - Formatting

    private func formatElapsed(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private func formatMinutes(_ mins: Double) -> String {
        let total = Int(mins)
        if total >= 60 {
            return "\(total / 60)h \(total % 60)m"
        }
        return "\(total)m"
    }
}

// Converts an item-ID range to the nearest character boundaries on each side.
// Lower character = "0 new chars this day" (same endpoint as previous day).
// Upper character = last character reachable by end of the next day.
func charBoundsForPicker(range: (start: Int, end: Int)) -> (lower: LearningItem, upper: LearningItem) {
    let lower = allCharacters.last(where: { $0.id <= range.start })
        ?? allCharacters.first(where: { $0.id > range.start })
        ?? allCharacters[0]
    let upper = allCharacters.last(where: { $0.id <= range.end }) ?? lower
    return (lower: lower, upper: upper.id >= lower.id ? upper : lower)
}

// MARK: - Edit sheet view

struct EditRequest: Identifiable {
    let id = UUID()
    let activity: String
}

struct EditSheetView: View {
    let editingActivity: String
    let minDate: Date
    let onCancel: () -> Void
    let onSave: (Date, Int, Int, Int) -> Void
    let loadData: (String, Date) -> (hours: Int, minutes: Int, itemIndex: Int)
    let buildRange: (Date) -> (start: Int, end: Int)

    @State private var editingDate: Date = Date()
    @State private var editHoursText: String = "0"
    @State private var editMinutesText: String = "0"
    @State private var editItemIndex: Int = 0
    @FocusState private var focused: Bool

    init(
        editingActivity: String,
        minDate: Date,
        onCancel: @escaping () -> Void,
        onSave: @escaping (Date, Int, Int, Int) -> Void,
        loadData: @escaping (String, Date) -> (hours: Int, minutes: Int, itemIndex: Int),
        buildRange: @escaping (Date) -> (start: Int, end: Int)
    ) {
        self.editingActivity = editingActivity
        self.minDate = minDate
        self.onCancel = onCancel
        self.onSave = onSave
        self.loadData = loadData
        self.buildRange = buildRange
        let data = loadData(editingActivity, Date())
        _editHoursText = State(initialValue: "\(data.hours)")
        _editMinutesText = State(initialValue: "\(data.minutes)")
        _editItemIndex = State(initialValue: data.itemIndex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $editingDate, in: minDate...Date(), displayedComponents: .date)
                        .onChange(of: editingDate) { _, newDate in
                            let data = loadData(editingActivity, newDate)
                            editHoursText = "\(data.hours)"
                            editMinutesText = "\(data.minutes)"
                            editItemIndex = data.itemIndex
                        }
                }
                let isToday = Calendar.current.isDateInToday(editingDate)
                let dateLabel = isToday ? "today" : editingDate.formatted(date: .abbreviated, time: .omitted)
                Section("Total time for \(editingActivity) \(dateLabel)") {
                    HStack {
                        Text("Hours")
                        Spacer()
                        TextField("0", text: $editHoursText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($focused)
                        Text("hr").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Minutes")
                        Spacer()
                        TextField("0", text: $editMinutesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($focused)
                        Text("min").foregroundStyle(.secondary)
                    }
                }
                if editingActivity == "Build" {
                    let range = buildRange(editingDate)
                    let (lowerChar, upperChar) = charBoundsForPicker(range: range)
                    let charsInRange = allCharacters.filter { $0.id >= lowerChar.id && $0.id <= upperChar.id }
                    if !charsInRange.isEmpty {
                        let centerIdx = charsInRange.firstIndex(where: { $0.id >= editItemIndex })
                            ?? (charsInRange.count - 1)
                        let charWindowStart = max(0, centerIdx - 10)
                        let charWindowEnd = min(charsInRange.count - 1, centerIdx + 300)
                        let window = Array(charsInRange[charWindowStart...charWindowEnd])
                        let globalOffset = allCharacters.firstIndex(where: { $0.id == window.first?.id }) ?? 0
                        Section("Last character completed") {
                            Picker("Last character", selection: $editItemIndex) {
                                ForEach(Array(window.enumerated()), id: \.element.id) { idx, item in
                                    Text("\(globalOffset + idx + 1). \(item.simplified)")
                                        .tag(item.id)
                                }
                            }
                            .pickerStyle(.wheel)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Edit \(editingActivity)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if focused {
                        Button("Done") { focused = false }
                    } else {
                        Button("Save") {
                            onSave(editingDate, Int(editHoursText) ?? 0, Int(editMinutesText) ?? 0, editItemIndex)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: StudySession.self, inMemory: true)
}
