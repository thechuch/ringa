import Combine
import EventKit
import SwiftUI
import UserNotifications

@MainActor
final class MeetingStore: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var upcomingMeetings: [Meeting] = []
    @Published var errorMessage: String?
    @Published private(set) var notificationsEnabled: Bool = false
    @Published private(set) var canEnableNotifications: Bool = false
    @Published private(set) var notificationLeadTimeMinutes: Double = 5

    private let eventStore = EKEventStore()
    private let notificationCenter = UNUserNotificationCenter.current()
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 300
    private var cachedAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    private let defaults = UserDefaults.standard
    private let notificationsPreferenceKey = "MeetingAlert.notificationsEnabled"
    private let leadTimePreferenceKey = "MeetingAlert.leadTimeMinutes"
    private var storedNotificationsPreference = false

    override init() {
        super.init()
        notificationCenter.delegate = self
        loadStoredPreferences()
    }

    func bootstrap() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        evaluateNotificationAuthorization()

        switch authorizationStatus {
        case .authorized:
            refreshMeetings()
            startRefreshTimer()
        case .restricted, .denied:
            errorMessage = "Meeting Alert does not have access to your calendars."
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func requestCalendarAccess() {
        eventStore.requestAccess(to: .event) { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)

                if let error {
                    self.errorMessage = error.localizedDescription
                }

                if granted {
                    self.errorMessage = nil
                    self.refreshMeetings()
                    self.startRefreshTimer()
                } else {
                    self.errorMessage = "Calendar access is required to read meetings."
                }
            }
        }
    }

    func refreshMeetings() {
        guard authorizationStatus == .authorized else { return }
        let meetings = fetchMeetings()
        upcomingMeetings = meetings

        if notificationsEnabled {
            scheduleNotifications(for: meetings)
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled != notificationsEnabled else { return }

        if enabled {
            if cachedAuthorizationStatus == .authorized {
                notificationsEnabled = true
                canEnableNotifications = true
                storedNotificationsPreference = true
                defaults.set(true, forKey: notificationsPreferenceKey)
                errorMessage = nil
                scheduleNotifications(for: upcomingMeetings)
                return
            }

            Task { @MainActor in
                let granted = await requestNotificationAuthorization()
                self.notificationsEnabled = granted
                self.canEnableNotifications = self.cachedAuthorizationStatus != .denied
                self.defaults.set(granted, forKey: self.notificationsPreferenceKey)
                self.storedNotificationsPreference = granted

                if granted {
                    self.errorMessage = nil
                    self.scheduleNotifications(for: self.upcomingMeetings)
                } else {
                    self.errorMessage = "Notifications are disabled. Enable them in System Settings."
                }
            }
        } else {
            notificationCenter.removeAllPendingNotificationRequests()
            notificationsEnabled = false
            canEnableNotifications = cachedAuthorizationStatus == .authorized
            storedNotificationsPreference = false
            defaults.set(false, forKey: notificationsPreferenceKey)
            errorMessage = nil
        }
    }

    func updateLeadTime(to minutes: Double) {
        notificationLeadTimeMinutes = minutes
        defaults.set(minutes, forKey: leadTimePreferenceKey)
        if notificationsEnabled {
            scheduleNotifications(for: upcomingMeetings)
        }
    }

    private func evaluateNotificationAuthorization() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                guard let self else { return }
                self.cachedAuthorizationStatus = settings.authorizationStatus
                self.canEnableNotifications = settings.authorizationStatus != .denied
                let authorized = settings.authorizationStatus == .authorized
                let shouldEnable = authorized && self.storedNotificationsPreference
                self.notificationsEnabled = shouldEnable

                if shouldEnable {
                    self.scheduleNotifications(for: self.upcomingMeetings)
                } else if !authorized {
                    self.storedNotificationsPreference = false
                    self.defaults.set(false, forKey: self.notificationsPreferenceKey)
                }
            }
        }
    }

    private func requestNotificationAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            cachedAuthorizationStatus = granted ? .authorized : .denied
            defaults.set(granted, forKey: notificationsPreferenceKey)
            storedNotificationsPreference = granted
            return granted
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func fetchMeetings() -> [Meeting] {
        let calendars = eventStore.calendars(for: .event).filter { !$0.isSubscribed }
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: 24, to: startDate) ?? startDate

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay else { return false }
                if event.hasAttendees { return true }
                if let location = event.location, !location.isEmpty { return true }
                let keywords = ["meeting", "sync", "standup", "retro"]
                return keywords.contains { keyword in
                    event.title.localizedCaseInsensitiveContains(keyword)
                }
            }
            .sorted(by: { $0.startDate < $1.startDate })

        return events.map { event in
            Meeting(
                identifier: event.eventIdentifier,
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                attendeeCount: event.attendees?.count ?? 0
            )
        }
    }

    private func scheduleNotifications(for meetings: [Meeting]) {
        notificationCenter.removeAllPendingNotificationRequests()

        let leadTime = notificationLeadTimeMinutes * 60
        let now = Date()

        for meeting in meetings {
            let triggerDate = meeting.startDate.addingTimeInterval(-leadTime)
            guard triggerDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Meeting starting soon"
            content.body = "\(meeting.title) begins at \(meeting.startDate.formattedTime())."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: triggerDate.timeIntervalSince(now), repeats: false)
            let request = UNNotificationRequest(identifier: meeting.identifier, content: content, trigger: trigger)
            notificationCenter.add(request) { [weak self] error in
                guard let self, let error else { return }
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshMeetings()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func loadStoredPreferences() {
        if defaults.object(forKey: notificationsPreferenceKey) != nil {
            storedNotificationsPreference = defaults.bool(forKey: notificationsPreferenceKey)
        }

        let storedLeadTime = defaults.double(forKey: leadTimePreferenceKey)
        if storedLeadTime >= 1 {
            notificationLeadTimeMinutes = storedLeadTime
        }
    }
}

extension MeetingStore {
    var authorizationMessage: String {
        switch authorizationStatus {
        case .authorized:
            return "Calendar access granted."
        case .denied:
            return "Access denied. Request access to see meetings."
        case .restricted:
            return "Calendar access is restricted."
        case .notDetermined:
            return "Calendar access not determined."
        @unknown default:
            return "Unknown authorization status."
        }
    }

    var authorizationIconName: String {
        switch authorizationStatus {
        case .authorized:
            return "checkmark.shield"
        case .denied, .restricted:
            return "shield.slash"
        case .notDetermined:
            return "questionmark.shield"
        @unknown default:
            return "questionmark"
        }
    }

    var authorizationTint: Color {
        switch authorizationStatus {
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    @MainActor static var preview: MeetingStore {
        let store = MeetingStore()
        store.authorizationStatus = .authorized
        store.upcomingMeetings = [
            Meeting(
                identifier: UUID().uuidString,
                title: "Design Sync",
                startDate: Date().addingTimeInterval(60 * 20),
                endDate: Date().addingTimeInterval(60 * 50),
                location: "Conference Room A",
                attendeeCount: 5
            ),
            Meeting(
                identifier: UUID().uuidString,
                title: "Sprint Planning",
                startDate: Date().addingTimeInterval(60 * 120),
                endDate: Date().addingTimeInterval(60 * 180),
                location: "Zoom",
                attendeeCount: 9
            )
        ]
        store.notificationsEnabled = true
        store.canEnableNotifications = true
        store.notificationLeadTimeMinutes = 10
        return store
    }
}

extension MeetingStore: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .sound])
    }
}
