import Foundation

private let snapshotsKey = "dailySnapshots"

private let snapshotDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone.current
    return f
}()

func snapshotDateKey(for date: Date) -> String {
    snapshotDateFormatter.string(from: date)
}

func dateFromSnapshotKey(_ key: String) -> Date? {
    guard let midnight = snapshotDateFormatter.date(from: key) else { return nil }
    return Calendar.current.date(bySettingHour: 3, minute: 0, second: 0, of: midnight)
}

func loadDailySnapshots() -> [String: Int] {
    guard let data = UserDefaults.standard.data(forKey: snapshotsKey),
          let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
    return dict
}

func saveDailySnapshots(_ dict: [String: Int]) {
    if let data = try? JSONEncoder().encode(dict) {
        UserDefaults.standard.set(data, forKey: snapshotsKey)
    }
}

func recordDailySnapshot(for studyDayStart: Date, endIndex: Int) {
    var dict = loadDailySnapshots()
    dict[snapshotDateKey(for: studyDayStart)] = endIndex
    saveDailySnapshots(dict)
}
