import Foundation
import EventKit

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: CGColor?

    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier ?? "\(ekEvent.calendarItemIdentifier)-\(ekEvent.startDate.timeIntervalSinceReferenceDate)"
        self.title = ekEvent.title?.isEmpty == false ? ekEvent.title : "(제목 없음)"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay
        self.calendarColor = ekEvent.calendar?.cgColor
    }

    func displayTitle(maxLength: Int = 24) -> String {
        if title.count <= maxLength {
            return title
        }
        let endIndex = title.index(title.startIndex, offsetBy: maxLength - 1)
        return String(title[..<endIndex]) + "…"
    }

    func isOngoing(at now: Date) -> Bool {
        startDate <= now && now < endDate
    }

    func hasSameDisplayContent(as other: CalendarEvent?) -> Bool {
        guard let other else { return false }

        return id == other.id &&
            title == other.title &&
            startDate == other.startDate &&
            endDate == other.endDate &&
            isAllDay == other.isAllDay &&
            calendarColor?.hashValue == other.calendarColor?.hashValue
    }
}
