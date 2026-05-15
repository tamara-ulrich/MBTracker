import SwiftData
import Foundation

@Model
final class StudySession {
    var date: Date
    var activity: String
    var durationSeconds: Double

    init(date: Date, activity: String, durationSeconds: Double) {
        self.date = date
        self.activity = activity
        self.durationSeconds = durationSeconds
    }
}
