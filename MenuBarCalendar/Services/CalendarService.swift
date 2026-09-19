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
    private var lastFetchDate: Date?
    private var cachedLookaheadHours: Int?
    private var cachedExcludedCalendarIDs: Set<String> = []
    private var lastMenuBarTitle = ""
    private let minimumFetchIntervalSeconds: TimeInterval = 300

    @Published var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published var currentEvent: CalendarEvent?
    @Published var nextEvent: CalendarEvent?
    @Published var menuBarTitle: String = "다음 일정 없음"
    @Published var availableCalendars: [EKCalendar] = []
    private var events: [CalendarEvent] = []

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
        settings.eventDisplayChanged
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshEvents(forceFetch: false, refreshSources: false)
                }
            }
            .store(in: &cancellables)
    }

    @objc private func calendarChanged() {
        Task { @MainActor in
            loadCalendars()
            refreshEvents(forceFetch: true, refreshSources: true)
        }
    }

    func checkAuthorizationStatus(refreshIfAuthorized: Bool = true) {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            let becameAuthorized = authorizationStatus != .authorized
            authorizationStatus = .authorized
            if becameAuthorized || refreshIfAuthorized {
                loadCalendars()
            }
            if refreshIfAuthorized {
                refreshEvents(forceFetch: true, refreshSources: true)
            }
            if becameAuthorized {
                startTimer()
            }
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
                refreshEvents(forceFetch: true, refreshSources: true)
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
        timer?.tolerance = max(1, secondsUntilNextMinute * 0.1)
    }

    private func startMinuteTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEvents()
            }
        }
        timer?.tolerance = 5
    }

    func refreshEvents(forceFetch: Bool = false, refreshSources: Bool = false) {
        guard authorizationStatus == .authorized else { return }

        let now = Date()
        let shouldFetch = forceFetch || shouldFetchEvents(now: now)

        if shouldFetch {
            if refreshSources {
                eventStore.refreshSourcesIfNecessary()
            }
            fetchEvents(now: now)
        }

        updateCurrentAndNextEvent()
        updateMenuBarTitleIfNeeded()
    }

    private func shouldFetchEvents(now: Date) -> Bool {
        if lastFetchDate == nil {
            return true
        }

        if cachedLookaheadHours != settings.lookaheadHours ||
            cachedExcludedCalendarIDs != settings.excludedCalendarIDs {
            return true
        }

        return now.timeIntervalSince(lastFetchDate ?? .distantPast) >= minimumFetchIntervalSeconds
    }

    private func fetchEvents(now: Date) {
        let lookaheadHours = settings.lookaheadHours
        let excludedCalendarIDs = settings.excludedCalendarIDs
        let endDate = Calendar.current.date(byAdding: .hour, value: lookaheadHours, to: now)!

        let predicate = eventStore.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: endDate, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)

        let fetchedEvents = ekEvents.lazy.filter { event in
            if let calendarID = event.calendar?.calendarIdentifier,
               excludedCalendarIDs.contains(calendarID) {
                return false
            }

            if event.isAllDay {
                return false
            }

            if event.status == .canceled {
                return false
            }

            return true
        }.map { CalendarEvent(from: $0) }
            .sorted { $0.startDate < $1.startDate }

        if !eventsHaveSameDisplayContent(events, fetchedEvents) {
            events = fetchedEvents
        }

        lastFetchDate = now
        cachedLookaheadHours = lookaheadHours
        cachedExcludedCalendarIDs = excludedCalendarIDs
    }

    private func eventsHaveSameDisplayContent(_ lhs: [CalendarEvent], _ rhs: [CalendarEvent]) -> Bool {
        guard lhs.count == rhs.count else { return false }

        return zip(lhs, rhs).allSatisfy { existingEvent, newEvent in
            existingEvent.hasSameDisplayContent(as: newEvent)
        }
    }

    private func updateCurrentAndNextEvent() {
        let now = Date()
        var selectedCurrentEvent: CalendarEvent?
        var selectedNextEvent: CalendarEvent?

        for event in events {
            if event.startDate <= now && now < event.endDate {
                switch settings.overlapRule {
                case .earliestEnd:
                    if selectedCurrentEvent == nil || event.endDate < selectedCurrentEvent!.endDate {
                        selectedCurrentEvent = event
                    }
                case .earliestStart:
                    if selectedCurrentEvent == nil {
                        selectedCurrentEvent = event
                    }
                }
            } else if selectedNextEvent == nil && event.startDate > now {
                selectedNextEvent = event
                break
            }
        }

        setCurrentEvent(selectedCurrentEvent)
        setNextEvent(selectedNextEvent)
    }

    private func setCurrentEvent(_ event: CalendarEvent?) {
        if !(event?.hasSameDisplayContent(as: currentEvent) ?? (currentEvent == nil)) {
            currentEvent = event
        }
    }

    private func setNextEvent(_ event: CalendarEvent?) {
        if !(event?.hasSameDisplayContent(as: nextEvent) ?? (nextEvent == nil)) {
            nextEvent = event
        }
    }

    private func updateMenuBarTitleIfNeeded() {
        // Update menu bar title
        let displayEvent = currentEvent ?? nextEvent
        let newTitle = RelativeTimeFormatter.formatMenuBarTitle(for: displayEvent, maxLength: settings.titleMaxLength)
        if newTitle != lastMenuBarTitle {
            menuBarTitle = newTitle
            lastMenuBarTitle = newTitle
        }
    }

    func openCalendarApp() {
        NSWorkspace.shared.open(URL(string: "ical://")!)
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
