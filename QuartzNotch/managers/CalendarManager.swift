import Defaults
import EventKit
import SwiftUI

// MARK: - CalendarManager

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var currentWeekStartDate: Date
    @Published var events: [EventModel] = []
    @Published var allCalendars: [CalendarModel] = []
    @Published var eventCalendars: [CalendarModel] = []
    @Published var reminderLists: [CalendarModel] = []
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    private var selectedCalendars: [CalendarModel] = []
    private let calendarService = CalendarService()

    private var eventStoreChangedObserver: NSObjectProtocol?

    private init() {
        self.currentWeekStartDate = CalendarManager.startOfDay(Date())
        setupEventStoreChangedObserver()
        Task {
            await reloadCalendarAndReminderLists()
        }
    }

    deinit {
        if let observer = eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupEventStoreChangedObserver() {
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.reloadCalendarAndReminderLists()
            }
        }
    }

    @MainActor
    func reloadCalendarAndReminderLists() async {
        let all = await calendarService.calendars()
        self.eventCalendars = all.filter { !$0.isReminder }
        self.reminderLists = all.filter { $0.isReminder }
        self.allCalendars = all // for legacy compatibility, can be removed if not needed
        updateSelectedCalendars()
        await updateEvents()
    }

    func refreshCalendarAuthorizationStatus() {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func refreshReminderAuthorizationStatus() {
        reminderAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func checkCalendarAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        self.calendarAuthorizationStatus = status

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .event) else {
                self.calendarAuthorizationStatus = .notDetermined
                return
            }
            self.calendarAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
                var calendar = Calendar.current
                calendar.timeZone = .autoupdatingCurrent
                let nextDay = calendar.date(byAdding: .day, value: 1, to: currentWeekStartDate)!
                let endDate = calendar.date(byAdding: .second, value: -1, to: nextDay)!
                events = await calendarService.events(
                    from: currentWeekStartDate,
                    to: endDate,
                    calendars: selectedCalendars.map { $0.id })
            }
        case .restricted, .denied:
            NSLog("Calendar access denied or restricted")
        case .fullAccess:
            NSLog("Full access")
            await reloadCalendarAndReminderLists()
            var calendar = Calendar.current
            calendar.timeZone = .autoupdatingCurrent
            let nextDay = calendar.date(byAdding: .day, value: 1, to: currentWeekStartDate)!
            let endDate = calendar.date(byAdding: .second, value: -1, to: nextDay)!
            events = await calendarService.events(
                from: currentWeekStartDate,
                to: endDate,
                calendars: selectedCalendars.map { $0.id })
        case .writeOnly:
            NSLog("Write only")
        @unknown default:
            print("Unknown authorization status")
        }
    }
    
    func checkReminderAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        self.reminderAuthorizationStatus = status

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .reminder) else {
                self.reminderAuthorizationStatus = .notDetermined
                return
            }
            self.reminderAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
            }
        case .restricted, .denied:
            NSLog("Reminder access denied or restricted")
        case .fullAccess:
            NSLog("Full access")
            await reloadCalendarAndReminderLists()
        case .writeOnly:
            NSLog("Write only")
        @unknown default:
            print("Unknown authorization status")
        }
    }
        

    func updateSelectedCalendars() {
        switch Defaults[.calendarSelectionState] {
        case .all:
            selectedCalendarIDs = Set(allCalendars.map { $0.id })
        case .selected(let identifiers):
            selectedCalendarIDs = identifiers
        }

        selectedCalendars = allCalendars.filter { selectedCalendarIDs.contains($0.id) }
    }

    func getCalendarSelected(_ calendar: CalendarModel) -> Bool {
        return selectedCalendarIDs.contains(calendar.id)
    }

    func setCalendarSelected(_ calendar: CalendarModel, isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.id }).subtracting([calendar.id])
                selectionState = .selected(identifiers)
            }

        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(calendar.id)
            } else {
                identifiers.remove(calendar.id)
            }

            selectionState =
                identifiers.isEmpty
                ? .all : identifiers.count == allCalendars.count ? .all : .selected(identifiers)  // if empty, select all
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents()
    }

    static func startOfDay(_ date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .autoupdatingCurrent
        return calendar.startOfDay(for: date)
    }

    func updateCurrentDate(_ date: Date) async {
        currentWeekStartDate = Self.startOfDay(date)
        await updateEvents()
    }

    private func updateEvents() async {
        let calendarIDs = selectedCalendars.map { $0.id }
        var calendar = Calendar.current
        calendar.timeZone = .autoupdatingCurrent
        
        let nextDay = calendar.date(byAdding: .day, value: 1, to: currentWeekStartDate)!
        let endDate = calendar.date(byAdding: .second, value: -1, to: nextDay)!
        
        let eventsResult = await calendarService.events(
            from: currentWeekStartDate,
            to: endDate,
            calendars: calendarIDs
        )
        self.events = eventsResult
    }
    
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
        var calendar = Calendar.current
        calendar.timeZone = .autoupdatingCurrent
        
        let nextDay = calendar.date(byAdding: .day, value: 1, to: currentWeekStartDate)!
        let endDate = calendar.date(byAdding: .second, value: -1, to: nextDay)!
        
        events = await calendarService.events(
            from: currentWeekStartDate,
            to: endDate,
            calendars: selectedCalendars.map { $0.id })
    }
}
