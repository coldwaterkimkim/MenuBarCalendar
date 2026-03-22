import SwiftUI
import EventKit
import AppKit

struct MenuContent: View {
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var settings: SettingsManager
    @State private var showingSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Authorization check
            if calendarService.authorizationStatus != .authorized {
                AuthorizationView(calendarService: calendarService)
            } else {
                // Current/Next Event Section
                if let currentEvent = calendarService.currentEvent {
                    CurrentEventSection(event: currentEvent, calendarService: calendarService)
                } else if let nextEvent = calendarService.nextEvent {
                    NextEventSection(event: nextEvent, calendarService: calendarService)
                } else {
                    EmptyStateView()
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Upcoming Events List
                UpcomingEventsSection(calendarService: calendarService, settings: settings)
                
                Divider()
                    .padding(.vertical, 8)
                
                // Actions
                ActionsSection(calendarService: calendarService)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: - Authorization View

struct AuthorizationView: View {
    @ObservedObject var calendarService: CalendarService
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text("캘린더 접근 권한이 필요합니다")
                .font(.headline)
            
            Text("시스템 설정 > 개인 정보 보호 및 보안 > 캘린더에서 이 앱을 허용해주세요.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if calendarService.authorizationStatus == .notDetermined {
                Button("권한 요청") {
                    Task {
                        await calendarService.requestAccess()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("시스템 설정 열기") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

// MARK: - Current Event Section

struct CurrentEventSection: View {
    let event: CalendarEvent
    let calendarService: CalendarService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(cgColor: event.calendarColor ?? CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)))
                    .frame(width: 8, height: 8)
                
                Text("진행 중")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(4)
            }
            
            Text(event.title)
                .font(.headline)
            
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text(RelativeTimeFormatter.formatTimeRange(start: event.startDate, end: event.endDate))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(RelativeTimeFormatter.formatRemainingTime(event.endDate))
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .font(.caption)
            
            if let location = event.location, !location.isEmpty {
                HStack {
                    Image(systemName: "location")
                        .foregroundColor(.secondary)
                    Text(location)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
            
            Text(event.calendarTitle)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Button(action: {
                calendarService.openInCalendar(event: event)
            }) {
                Label("캘린더에서 열기", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Next Event Section

struct NextEventSection: View {
    let event: CalendarEvent
    let calendarService: CalendarService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(cgColor: event.calendarColor ?? CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)))
                    .frame(width: 8, height: 8)
                
                Text("다음 일정")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                
                Spacer()
                
                Text(RelativeTimeFormatter.formatTimeUntil(event.startDate))
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            Text(event.title)
                .font(.headline)
            
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text(RelativeTimeFormatter.formatTimeRange(start: event.startDate, end: event.endDate))
                    .foregroundColor(.secondary)
            }
            .font(.caption)
            
            if let location = event.location, !location.isEmpty {
                HStack {
                    Image(systemName: "location")
                        .foregroundColor(.secondary)
                    Text(location)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
            
            Text(event.calendarTitle)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Button(action: {
                calendarService.openInCalendar(event: event)
            }) {
                Label("캘린더에서 열기", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.title)
                .foregroundColor(.secondary)
            
            Text("다음 일정 없음")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("24시간 내 예정된 일정이 없습니다")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Upcoming Events Section

struct UpcomingEventsSection: View {
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var settings: SettingsManager
    
    private var todayEvents: [CalendarEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return calendarService.getUpcomingEvents(count: settings.upcomingEventsCount)
            .filter { !$0.isOngoing && $0.startDate < tomorrow }
    }
    
    private var tomorrowAndLaterEvents: [CalendarEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return calendarService.getUpcomingEvents(count: settings.upcomingEventsCount)
            .filter { !$0.isOngoing && $0.startDate >= tomorrow }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("다가오는 일정")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
            
            let allUpcoming = todayEvents + tomorrowAndLaterEvents
            
            if allUpcoming.isEmpty {
                Text("예정된 일정이 없습니다")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                // 오늘 일정
                ForEach(todayEvents) { event in
                    UpcomingEventRow(event: event, calendarService: calendarService)
                }
                
                // 내일 이후 일정이 있으면 구분선 표시
                if !todayEvents.isEmpty && !tomorrowAndLaterEvents.isEmpty {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)
                        
                        Text("내일의 나, 부탁한다")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize()
                        
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 6)
                }
                
                // 내일 이후 일정
                ForEach(tomorrowAndLaterEvents) { event in
                    UpcomingEventRow(event: event, calendarService: calendarService)
                }
            }
        }
    }
}

struct UpcomingEventRow: View {
    let event: CalendarEvent
    let calendarService: CalendarService
    
    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: event.startDate))–\(formatter.string(from: event.endDate))"
    }
    
    private var secondaryText: String {
        let category = event.calendarTitle
        let timeRange = timeRangeText
        let remaining = RelativeTimeFormatter.formatTimeUntil(event.startDate)
        return "\(category) | \(timeRange) | \(remaining)"
    }
    
    var body: some View {
        Button(action: {
            calendarService.openInCalendar(event: event)
        }) {
            HStack(spacing: 8) {
                // 좌측 세로 바 인디케이터
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(cgColor: event.calendarColor ?? CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)))
                    .frame(width: 3)
                
                VStack(alignment: .leading, spacing: 3) {
                    // Line 1: 일정 제목
                    Text(event.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    // Line 2: 캘린더 카테고리 | 시간 범위 | 남은 시간
                    Text(secondaryText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Actions Section

struct ActionsSection: View {
    @ObservedObject var calendarService: CalendarService
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        VStack(spacing: 4) {
            Button(action: {
                calendarService.refreshEvents()
            }) {
                Label("새로고침", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: {
                openSettings()
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }) {
                Label("설정...", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .padding(.vertical, 4)
            
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("종료", systemImage: "power")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    MenuContent(calendarService: CalendarService(), settings: SettingsManager.shared)
}
