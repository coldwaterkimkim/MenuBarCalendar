import Foundation

struct RelativeTimeFormatter {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    /// 다음 일정까지의 상대시간 포맷
    static func formatTimeUntil(_ date: Date, from now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)

        if interval <= 0 {
            return "지금"
        }

        // 올림 처리: 10:11:30에 12:00 이벤트면 1시간 49분 (48.5분을 49분으로)
        let totalMinutes = Int(ceil(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        // 0~59분: N분 후
        if totalMinutes < 60 {
            return "\(max(1, totalMinutes))분 후"
        }

        // 1~23시간
        if hours < 24 {
            if minutes > 0 {
                return "\(hours)시간 \(minutes)분 후"
            }
            return "\(hours)시간 후"
        }

        // 내일 확인
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 1, to: tomorrow)!

        if date >= tomorrow && date < dayAfterTomorrow {
            return "내일 \(timeFormatter.string(from: date))"
        }

        // 2일 이상
        return shortDateTimeFormatter.string(from: date)
    }

    /// 진행중인 일정의 남은 시간 포맷
    static func formatRemainingTime(_ endDate: Date, from now: Date = Date()) -> String {
        let interval = endDate.timeIntervalSince(now)

        if interval <= 0 {
            return "종료됨"
        }

        // 올림 처리
        let totalMinutes = Int(ceil(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if totalMinutes < 60 {
            return "\(max(1, totalMinutes))분 남음"
        }

        if minutes > 0 {
            return "\(hours)시간 \(minutes)분 남음"
        }
        return "\(hours)시간 남음"
    }

    /// 메뉴바 타이틀 포맷
    static func formatMenuBarTitle(for event: CalendarEvent?, maxLength: Int = 24) -> String {
        guard let event = event else {
            return "다음 일정 없음"
        }

        let now = Date()
        let title = event.displayTitle(maxLength: maxLength)

        if event.isOngoing(at: now) {
            let remaining = formatRemainingTime(event.endDate, from: now)
            return "\(title) · 진행중 (\(remaining))"
        } else {
            let until = formatTimeUntil(event.startDate, from: now)
            return "\(title) · \(until)"
        }
    }

    /// 시간 범위 포맷 (HH:mm - HH:mm)
    static func formatTimeRange(start: Date, end: Date) -> String {
        return "\(timeFormatter.string(from: start)) - \(timeFormatter.string(from: end))"
    }
}
