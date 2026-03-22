import Foundation
import EventKit
import Combine
import AppKit

enum AuthorizationStatus {
    case authorized
    case denied
    case notDetermined
}

@MainActor
class CalendarService: ObservableObject {
    private let eventStore = EKEventStore()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published var events: [CalendarEvent] = []
    @Published var currentEvent: CalendarEvent?
    @Published var nextEvent: CalendarEvent?
    @Published var menuBarTitle: String = "다음 일정 없음"
    @Published var availableCalendars: [EKCalendar] = []
    
    private let settings = SettingsManager.shared
    
    init() {
        checkAuthorizationStatus()
        setupNotifications()
        setupSettingsObserver()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }
    
    private func setupSettingsObserver() {
        settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshEvents()
            }
        }.store(in: &cancellables)
    }
    
    @objc private func calendarChanged() {
        Task { @MainActor in
            refreshEvents()
        }
    }
    
    func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            authorizationStatus = .authorized
            loadCalendars()
            refreshEvents()
            startTimer()
        case .denied, .restricted:
            authorizationStatus = .denied
            menuBarTitle = "권한 필요"
        case .notDetermined, .writeOnly:
            authorizationStatus = .notDetermined
        @unknown default:
            authorizationStatus = .notDetermined
        }
    }
    
    func requestAccess() async {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            
            if granted {
                authorizationStatus = .authorized
                loadCalendars()
                refreshEvents()
                startTimer()
            } else {
                authorizationStatus = .denied
                menuBarTitle = "권한 필요"
            }
        } catch {
            authorizationStatus = .denied
            menuBarTitle = "권한 필요"
        }
    }
    
    private func loadCalendars() {
        availableCalendars = eventStore.calendars(for: .event)
    }
    
    private func startTimer() {
        timer?.invalidate()
        
        // Calculate time until next minute boundary
        let now = Date()
        let calendar = Calendar.current
        let seconds = calendar.component(.second, from: now)
        let nanoseconds = calendar.component(.nanosecond, from: now)
        let secondsUntilNextMinute = Double(60 - seconds) - Double(nanoseconds) / 1_000_000_000
        
        // First, schedule a one-shot timer to sync with minute boundary
        timer = Timer.scheduledTimer(withTimeInterval: secondsUntilNextMinute, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEvents()
                // Then start the repeating timer on minute boundaries
                self?.startMinuteTimer()
            }
        }
    }
    
    private func startMinuteTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEvents()
            }
        }
    }
    
    func refreshEvents() {
        guard authorizationStatus == .authorized else { return }
        
        // 외부 앱(Calendar.app)에서의 변경사항을 반영하기 위해 소스 갱신
        eventStore.refreshSourcesIfNecessary()
        
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: settings.lookaheadHours, to: now)!
        
        let predicate = eventStore.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: endDate, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
        
        // Filter events
        let filtered = ekEvents.filter { event in
            // Exclude calendars
            if let calendarID = event.calendar?.calendarIdentifier,
               settings.excludedCalendarIDs.contains(calendarID) {
                return false
            }
            
            // Filter all-day events
            if event.isAllDay && !settings.showAllDayEvents {
                return false
            }
            
            // Exclude cancelled/declined
            if event.status == .canceled {
                return false
            }
            
            return true
        }
        
        events = filtered.map { CalendarEvent(from: $0) }
            .sorted { $0.startDate < $1.startDate }
        
        // Find current event
        let ongoingEvents = events.filter { $0.isOngoing && !$0.isAllDay }
        
        if !ongoingEvents.isEmpty {
            switch settings.overlapRule {
            case .earliestEnd:
                currentEvent = ongoingEvents.min { $0.endDate < $1.endDate }
            case .earliestStart:
                currentEvent = ongoingEvents.min { $0.startDate < $1.startDate }
            }
        } else {
            currentEvent = nil
        }
        
        // Find next event
        let upcomingEvents = events.filter { $0.isUpcoming && !$0.isAllDay }
        nextEvent = upcomingEvents.first
        
        // Update menu bar title
        let displayEvent = currentEvent ?? nextEvent
        menuBarTitle = RelativeTimeFormatter.formatMenuBarTitle(for: displayEvent, maxLength: settings.titleMaxLength)
    }
    
    func openInCalendar(event: CalendarEvent) {
        // Use the ical:// URL scheme to open Calendar app
        // Format: ical://ekevent/[event-identifier]?method=show
        if let eventID = event.ekEvent.eventIdentifier,
           let url = URL(string: "ical://ekevent/\(eventID)?method=show") {
            NSWorkspace.shared.open(url)
        } else {
            // Fallback: just open Calendar app
            NSWorkspace.shared.open(URL(string: "ical://")!)
        }
    }
    
    func getUpcomingEvents(count: Int) -> [CalendarEvent] {
        let upcoming = events.filter { $0.isUpcoming || $0.isOngoing }
            .sorted { $0.startDate < $1.startDate }
        return Array(upcoming.prefix(count))
    }
    
    deinit {
        timer?.invalidate()
    }
}
