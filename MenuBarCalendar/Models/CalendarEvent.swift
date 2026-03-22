import Foundation
import EventKit

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let calendarColor: CGColor?
    let location: String?
    let ekEvent: EKEvent
    
    var isOngoing: Bool {
        let now = Date()
        return startDate <= now && now < endDate
    }
    
    var isUpcoming: Bool {
        return startDate > Date()
    }
    
    var duration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }
    
    var remainingTime: TimeInterval {
        return endDate.timeIntervalSince(Date())
    }
    
    var timeUntilStart: TimeInterval {
        return startDate.timeIntervalSince(Date())
    }
    
    init(from ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier ?? UUID().uuidString
        self.title = ekEvent.title?.isEmpty == false ? ekEvent.title : "(제목 없음)"
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.isAllDay = ekEvent.isAllDay
        self.calendarTitle = ekEvent.calendar?.title ?? ""
        self.calendarColor = ekEvent.calendar?.cgColor
        self.location = ekEvent.location
        self.ekEvent = ekEvent
    }
    
    func displayTitle(maxLength: Int = 24) -> String {
        if title.count <= maxLength {
            return title
        }
        let endIndex = title.index(title.startIndex, offsetBy: maxLength - 1)
        return String(title[..<endIndex]) + "…"
    }
}
