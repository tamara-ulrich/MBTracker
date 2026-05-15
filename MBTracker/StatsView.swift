import SwiftUI
import SwiftData

enum StatsPeriod: String, CaseIterable {
    case week = "7 Days"
    case month = "Month"
    case allTime = "All Time"

    var startDate: Date {
        let cal = Calendar.current
        switch self {
        case .week:    return cal.date(byAdding: .day, value: -7, to: Date())!
        case .month:   return cal.date(byAdding: .day, value: -30, to: Date())!
        case .allTime: return .distantPast
        }
    }
}

struct StatsView: View {
    @Query(sort: \StudySession.date) private var allSessions: [StudySession]
    @AppStorage("lastLearnedIndex") private var lastLearnedIndex = 0
    @AppStorage("todayStartIndex") private var todayStartIndex = 0
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPeriod: StatsPeriod = .week

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(StatsPeriod.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                summarySection
                if !dayRecords.isEmpty {
                    dailySection
                }
                if !levelRecords.isEmpty {
                    levelSection
                }
            }
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: generateCSVFile()) {
                            Label("Export daily data as CSV", systemImage: "calendar")
                        }
                        ShareLink(item: generateLevelHistoryCSVFile()) {
                            Label("Export level history as CSV", systemImage: "list.number")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Snapshot entries from UserDefaults

    private var snapshotEntries: [(date: Date, endIdx: Int)] {
        loadDailySnapshots().compactMap { key, value in
            guard let date = dateFromSnapshotKey(key) else { return nil }
            return (date: date, endIdx: value)
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Filtered sessions

    private var periodStart: Date { selectedPeriod.startDate }

    private var filteredSessions: [StudySession] {
        allSessions.filter { $0.date >= periodStart }
    }

    private var periodStartIndex: Int {
        snapshotEntries.filter { $0.date < periodStart }.last?.endIdx ?? 0
    }

    private var periodItemsLearned: Int {
        max(0, lastLearnedIndex - periodStartIndex)
    }

    private func periodSeconds(_ activity: String) -> Double {
        filteredSessions.filter { $0.activity == activity }.reduce(0) { $0 + $1.durationSeconds }
    }

    // MARK: - Summary

    private var summarySection: some View {
        let build = periodSeconds("Build")
        let get = periodSeconds("Get")
        let activate = periodSeconds("Activate")
        let ratioTotal = build + get + activate

        return Section("Summary") {
            LabeledContent("Current level", value: "Level \(currentLevel)")
            LabeledContent("Study time", value: formatHours(filteredSessions.filter { $0.activity != "Immerse" }.reduce(0) { $0 + $1.durationSeconds }))
            if ratioTotal > 0 {
                LabeledContent("Ratios") {
                    HStack(spacing: 10) {
                        Text("Build \(Int((build / ratioTotal * 100).rounded()))%")
                            .foregroundStyle(.blue)
                        Text("Get \(Int((get / ratioTotal * 100).rounded()))%")
                            .foregroundStyle(.teal)
                        Text("Act \(Int((activate / ratioTotal * 100).rounded()))%")
                            .foregroundStyle(.indigo)
                    }
                    .font(.subheadline)
                }
            }
            LabeledContent("Items learned", value: "\(periodItemsLearned)")
            LabeledContent("Characters", value: "\(periodChars)")
            LabeledContent("Words", value: "\(periodWords)")
            let avgImmerseMins = periodSeconds("Immerse") / Double(periodDays) / 60
            LabeledContent("Avg immersion/day") {
                Text(String(format: "%.0f min", avgImmerseMins))
                    .foregroundStyle(avgImmerseMins >= 60 ? .green : .secondary)
            }
        }
    }

    private var currentLevel: Int {
        guard lastLearnedIndex > 0 else { return 1 }
        let idx = min(lastLearnedIndex - 1, allLearningItems.count - 1)
        return allLearningItems[idx].level
    }

    private var periodDays: Int {
        switch selectedPeriod {
        case .week:  return 7
        case .month: return 30
        case .allTime:
            guard let first = allSessions.first else { return 1 }
            let days = Calendar.current.dateComponents([.day], from: dayStart(for: first.date), to: Date()).day ?? 0
            return max(1, days + 1)
        }
    }

    private var periodChars: Int {
        let s = min(periodStartIndex, allLearningItems.count)
        let e = min(lastLearnedIndex, allLearningItems.count)
        guard s < e else { return 0 }
        return allLearningItems[s..<e].filter(\.isCharacter).count
    }
    private var periodWords: Int {
        let s = min(periodStartIndex, allLearningItems.count)
        let e = min(lastLearnedIndex, allLearningItems.count)
        guard s < e else { return 0 }
        return allLearningItems[s..<e].filter { !$0.isCharacter }.count
    }

    // MARK: - Daily breakdown

    private var dailySection: some View {
        Section("Daily breakdown") {
            ForEach(dayRecords) { record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(record.date, format: .dateTime.day().month(.abbreviated).year())
                            .fontWeight(.medium)
                        Spacer()
                        Text(formatHours(record.studySeconds))
                            .foregroundStyle(.secondary)
                    }
                    let ratioTotal = record.buildSeconds + record.getSeconds + record.activateSeconds
                    HStack(spacing: 8) {
                        if record.buildSeconds > 0 {
                            Text("Build \(formatMins(record.buildSeconds))").foregroundStyle(.blue)
                        }
                        if record.getSeconds > 0 {
                            Text("Get \(formatMins(record.getSeconds))").foregroundStyle(.teal)
                        }
                        if record.activateSeconds > 0 {
                            Text("Act \(formatMins(record.activateSeconds))").foregroundStyle(.indigo)
                        }
                        if record.immerseSeconds > 0 {
                            Text("Imm \(formatMins(record.immerseSeconds))").foregroundStyle(.purple)
                        }
                        Spacer()
                        if record.charsLearned > 0 || record.wordsLearned > 0 {
                            Text("\(record.charsLearned)c \(record.wordsLearned)w")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    if ratioTotal > 0 {
                        HStack(spacing: 8) {
                            if record.buildSeconds > 0 {
                                Text("Build \(Int((record.buildSeconds / ratioTotal * 100).rounded()))%").foregroundStyle(.blue)
                            }
                            if record.getSeconds > 0 {
                                Text("Get \(Int((record.getSeconds / ratioTotal * 100).rounded()))%").foregroundStyle(.teal)
                            }
                            if record.activateSeconds > 0 {
                                Text("Act \(Int((record.activateSeconds / ratioTotal * 100).rounded()))%").foregroundStyle(.indigo)
                            }
                            Spacer()
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Level history

    private var levelSection: some View {
        Section("Level history") {
            ForEach(levelRecords) { record in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Level \(record.level)")
                            .fontWeight(.medium)
                        if !record.isCompleted {
                            Text("in progress")
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Text("\(record.totalItems) items · \(record.charsLearned)c \(record.wordsLearned)w")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("\(record.calendarDays) day\(record.calendarDays == 1 ? "" : "s")")
                        Text("·")
                        Text(formatHours(record.buildSeconds)).foregroundStyle(.blue)
                        Text("Build")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Data helpers

    private func dayStart(for date: Date) -> Date {
        let cal = Calendar.current
        let at3am = cal.date(bySettingHour: 3, minute: 0, second: 0, of: date)!
        return date >= at3am ? at3am : cal.date(byAdding: .day, value: -1, to: at3am)!
    }

    // MARK: - Day records

    private struct DayRecord: Identifiable {
        let id: Date
        let date: Date
        let buildSeconds: Double
        let getSeconds: Double
        let activateSeconds: Double
        let immerseSeconds: Double
        let charsLearned: Int
        let wordsLearned: Int
        var totalSeconds: Double { buildSeconds + getSeconds + activateSeconds + immerseSeconds }
        var studySeconds: Double { buildSeconds + getSeconds + activateSeconds }
    }

    private var dayRecords: [DayRecord] {
        var byDay: [Date: [StudySession]] = [:]
        for session in filteredSessions {
            byDay[dayStart(for: session.date), default: []].append(session)
        }

        // Build per-day index ranges from snapshot entries + today
        var itemsByDay: [Date: (start: Int, end: Int)] = [:]
        let periodSnaps = snapshotEntries.filter { $0.date >= periodStart }
        var prev = periodStartIndex
        for snap in periodSnaps {
            itemsByDay[snap.date] = (start: prev, end: snap.endIdx)
            prev = snap.endIdx
        }
        itemsByDay[dayStart(for: Date())] = (start: todayStartIndex, end: lastLearnedIndex)

        return Set(byDay.keys).union(itemsByDay.keys).sorted(by: >).compactMap { day in
            let sessions = byDay[day] ?? []
            func sum(_ a: String) -> Double { sessions.filter { $0.activity == a }.reduce(0) { $0 + $1.durationSeconds } }

            var chars = 0, words = 0
            if let r = itemsByDay[day], r.end > r.start {
                let s = min(r.start, allLearningItems.count)
                let e = min(r.end, allLearningItems.count)
                if s < e {
                    chars = allLearningItems[s..<e].filter(\.isCharacter).count
                    words = allLearningItems[s..<e].filter { !$0.isCharacter }.count
                }
            }

            let build = sum("Build"), get = sum("Get"), activate = sum("Activate"), immerse = sum("Immerse")
            guard build + get + activate + immerse > 0 || chars > 0 || words > 0 else { return nil }

            return DayRecord(id: day, date: day,
                             buildSeconds: build, getSeconds: get,
                             activateSeconds: activate, immerseSeconds: immerse,
                             charsLearned: chars, wordsLearned: words)
        }
    }

    // MARK: - Level records

    private struct LevelRecord: Identifiable {
        let id: Int
        let level: Int
        let totalItems: Int
        let charsLearned: Int
        let wordsLearned: Int
        let buildSeconds: Double
        let calendarDays: Int
        let isCompleted: Bool
    }

    private var levelRecords: [LevelRecord] {
        guard lastLearnedIndex > 0 else { return [] }

        var bounds: [Int: (start: Int, end: Int)] = [:]
        for item in allLearningItems {
            if let b = bounds[item.level] {
                bounds[item.level] = (start: min(b.start, item.id), end: max(b.end, item.id + 1))
            } else {
                bounds[item.level] = (start: item.id, end: item.id + 1)
            }
        }

        let sortedSnaps = snapshotEntries

        func dateReaching(_ index: Int) -> Date? {
            guard lastLearnedIndex >= index else { return nil }
            return sortedSnaps.first(where: { $0.endIdx >= index })?.date ?? Date()
        }

        return (1...currentLevel).reversed().compactMap { level -> LevelRecord? in
            guard let b = bounds[level], let startDate = dateReaching(b.start) else { return nil }
            let endDate = dateReaching(b.end)
            let isCompleted = lastLearnedIndex >= b.end

            let calDays = Calendar.current.dateComponents([.day],
                from: startDate, to: endDate ?? Date()).day.map { max(0, $0) } ?? 0

            let buildSecs = allSessions.filter {
                $0.activity == "Build"
                && dayStart(for: $0.date) >= startDate
                && (endDate == nil || dayStart(for: $0.date) < endDate!)
            }.reduce(0.0) { $0 + $1.durationSeconds }

            let learnedEnd = min(lastLearnedIndex, b.end)
            let learnedRange = allLearningItems[b.start..<learnedEnd]
            let chars = learnedRange.filter(\.isCharacter).count
            let words = learnedRange.filter { !$0.isCharacter }.count

            return LevelRecord(id: level, level: level,
                               totalItems: b.end - b.start,
                               charsLearned: chars,
                               wordsLearned: words,
                               buildSeconds: buildSecs,
                               calendarDays: calDays,
                               isCompleted: isCompleted)
        }
    }

    // MARK: - Sample data

    private func loadSampleData() {
        let cal = Calendar.current
        let base = lastLearnedIndex  // offset all indices from current position

        // (daysAgo, build, get, activate, immerse, relative offset from base)
        let days: [(Int, Double, Double, Double, Double, Int)] = [
            (62, 85, 18,  8,   0,  22),
            (61, 90, 22, 10,   0,  48),
            (60,  0,  0,  0,   0,  48), // rest day — no tracking
            (59, 75, 20,  8,  30,  71),
            (58, 95, 25, 12,   0, 101),
            (57, 60, 18,  6,   0, 118),
            (56, 80, 20, 10,  45, 143),
            (54, 90, 24, 11,   0, 172),
            (53, 70, 18,  8,   0, 194),
            (52, 85, 22, 10,  30, 221),
            (51, 65, 16,  7,   0, 241),
            (50, 90, 25, 12,   0, 270),
            (48, 80, 20,  9,  60, 296),
            (47, 95, 26, 13,   0, 329),
            (46, 70, 18,  8,   0, 351),
            (45, 85, 22, 10,  30, 379),
            (44, 60, 15,  6,   0, 394),
            (43, 90, 24, 11,   0, 424),
            (41, 75, 20,  9,  45, 450),
            (40, 95, 25, 12,   0, 483),
            (39, 80, 21, 10,   0, 511),
            (38, 65, 17,  8,  30, 530),
            (37, 90, 23, 11,   0, 561),
            (35, 85, 22, 10,   0, 590),
            (34, 70, 18,  8,  60, 613),
            (33, 95, 25, 12,   0, 645),
            (32, 75, 20,  9,   0, 668),
            (31, 80, 21, 10,  30, 694),
            (29, 90, 24, 11,   0, 724),
            (28,  0, 22, 10,   0, 724), // no Build — only Get/Activate, 0 items
            (27, 85, 22, 10,  45, 769),
            (26, 95, 25, 12,   0, 801),
            (25, 70, 18,  8,   0, 822),
            (24, 80, 21, 10,  30, 849),
            (22, 90, 23, 11,   0, 879),
            (21, 75, 20,  9,   0, 902),
            (20, 85, 22, 10,  60, 930),
            (19, 95, 25, 12,   0, 962),
            (18, 65, 17,  8,   0, 980),
            (17, 80, 21, 10,  30, 1008),
            (15, 90, 24, 11,   0, 1038),
            (14, 70, 18,  8,   0, 1058),
            (13, 85, 22, 10,  45, 1085),
            (12, 95, 25, 12,   0, 1117),
            (11, 75, 20,  9,   0, 1139),
            (10, 80, 21, 10,  30, 1165),
            ( 8, 90, 24, 11,   0, 1195),
            ( 7,  0,  0,  0,   0, 1195), // rest day — no tracking
            ( 6, 85, 22, 10,  60, 1239),
            ( 5, 95, 25, 12,   0, 1271),
            ( 4, 70, 18,  8,   0, 1291),
            ( 3, 80, 21, 10,  30, 1317),
            ( 2, 90, 24, 11,   0, 1347),
            ( 1, 75, 20,  9,  45, 1369),
        ]

        var snapshotDict: [String: Int] = [:]

        for (daysAgo, build, get, activate, immerse, endIdx) in days {
            let dayBase = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
            let dayDate = cal.date(bySettingHour: 10, minute: 0, second: 0, of: dayBase)!

            func session(_ activity: String, _ mins: Double) {
                guard mins > 0 else { return }
                modelContext.insert(StudySession(date: dayDate, activity: activity, durationSeconds: mins * 60))
            }
            session("Build", build)
            session("Get", get)
            session("Activate", activate)
            session("Immerse", immerse)

            let snapDate = cal.date(bySettingHour: 3, minute: 0, second: 0, of: dayBase)!
            snapshotDict[snapshotDateKey(for: snapDate)] = min(base + endIdx, allLearningItems.count)
        }

        saveDailySnapshots(snapshotDict)
        todayStartIndex = min(base + 1369, allLearningItems.count)
        lastLearnedIndex = min(base + 1391, allLearningItems.count)
        try? modelContext.save()
    }

    // MARK: - CSV Export

    private func generateCSVFile() -> URL {
        var rows = ["Date,Level,Build (min),Get (min),Activate (min),Immerse (min),Build%,Get%,Act%,Items Learned,Characters,Words"]

        var byDay: [Date: [StudySession]] = [:]
        for session in allSessions {
            byDay[dayStart(for: session.date), default: []].append(session)
        }

        var itemsByDay: [Date: (start: Int, end: Int)] = [:]
        var prev = 0
        for snap in snapshotEntries {
            itemsByDay[snap.date] = (start: prev, end: snap.endIdx)
            prev = snap.endIdx
        }
        itemsByDay[dayStart(for: Date())] = (start: todayStartIndex, end: lastLearnedIndex)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for day in Set(byDay.keys).union(itemsByDay.keys).sorted() {
            let sessions = byDay[day] ?? []
            func sum(_ a: String) -> Double { sessions.filter { $0.activity == a }.reduce(0) { $0 + $1.durationSeconds } / 60 }

            let build = sum("Build"), get = sum("Get"), activate = sum("Activate"), immerse = sum("Immerse")
            let ratioTotal = build + get + activate
            let buildPct = ratioTotal > 0 ? Int((build / ratioTotal * 100).rounded()) : 0
            let getPct   = ratioTotal > 0 ? Int((get   / ratioTotal * 100).rounded()) : 0
            let actPct   = ratioTotal > 0 ? Int((activate / ratioTotal * 100).rounded()) : 0

            var chars = 0, words = 0, level = 0
            if let r = itemsByDay[day] {
                let endIdx = min(r.end, allLearningItems.count)
                if endIdx > 0 {
                    level = allLearningItems[endIdx - 1].level
                }
                if r.end > r.start {
                    let s = min(r.start, allLearningItems.count)
                    let e = endIdx
                    if s < e {
                        chars = allLearningItems[s..<e].filter(\.isCharacter).count
                        words = allLearningItems[s..<e].filter { !$0.isCharacter }.count
                    }
                }
            }

            rows.append("\(dateFormatter.string(from: day)),\(level),\(Int(build)),\(Int(get)),\(Int(activate)),\(Int(immerse)),\(buildPct),\(getPct),\(actPct),\(chars + words),\(chars),\(words)")
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mbtracker-export.csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func generateLevelHistoryCSVFile() -> URL {
        var rows = ["Level,Status,Total Items,Calendar Days,Build (min)"]

        for record in levelRecords.reversed() {
            let status = record.isCompleted ? "Completed" : "In Progress"
            rows.append("\(record.level),\(status),\(record.totalItems),\(record.calendarDays),\(Int(record.buildSeconds / 60))")
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mbtracker-levels.csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Formatting

    private func formatHours(_ secs: Double) -> String {
        let s = Int(secs)
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func formatMins(_ secs: Double) -> String { "\(Int(secs) / 60)m" }
}

