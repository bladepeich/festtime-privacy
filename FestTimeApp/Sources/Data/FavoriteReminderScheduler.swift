import Foundation
import UserNotifications

struct FestTimeNotificationItem: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let date: Date
}

protocol FavoriteReminderScheduling {
    func requestAuthorization() async -> Bool
    func hasNotificationPermission() async -> Bool
    func setAppBadgeCount(_ count: Int) async
    func clearReminders(for festivalID: String) async
    func clearAllFestTimeNotifications() async
    func pendingReminderCount(for festivalID: String) async -> Int
    func deliveredFestTimeNotifications() async -> [FestTimeNotificationItem]
    func markDeliveredNotificationsAsRead(ids: [String]) async
    func scheduleTestNotification(after seconds: TimeInterval) async throws
    func scheduleReminders(
        festival: FestivalDefinition,
        events: [FestivalEvent],
        favoriteIDs: Set<String>,
        reminderMinutes: [Int]
    ) async throws
}

struct FavoriteReminderScheduler: FavoriteReminderScheduling {
    private let center = UNUserNotificationCenter.current()
    private let notificationPrefix = "festtime."
    private let maxPendingReminders = 60

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func hasNotificationPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    continuation.resume(returning: true)
                default:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func setAppBadgeCount(_ count: Int) async {
        await withCheckedContinuation { continuation in
            center.setBadgeCount(max(0, count)) { _ in
                continuation.resume()
            }
        }
    }

    func clearReminders(for festivalID: String) async {
        let prefix = reminderPrefix(for: festivalID)
        let pending = await pendingRequestIDs()
        let removable = pending.filter { $0.hasPrefix(prefix) }

        center.removePendingNotificationRequests(withIdentifiers: removable)
        center.removeDeliveredNotifications(withIdentifiers: removable)
    }

    func clearAllFestTimeNotifications() async {
        let pending = await pendingRequestIDs()
        let delivered = await deliveredNotificationIDs()
        let pendingToRemove = pending.filter { $0.hasPrefix(notificationPrefix) }
        let deliveredToRemove = delivered.filter { $0.hasPrefix(notificationPrefix) }

        center.removePendingNotificationRequests(withIdentifiers: pendingToRemove)
        center.removeDeliveredNotifications(withIdentifiers: deliveredToRemove)
    }

    func pendingReminderCount(for festivalID: String) async -> Int {
        let prefix = reminderPrefix(for: festivalID)
        let pending = await pendingRequestIDs()
        return pending.filter { $0.hasPrefix(prefix) }.count
    }

    func deliveredFestTimeNotifications() async -> [FestTimeNotificationItem] {
        let delivered = await deliveredNotifications()
        let filtered = delivered.filter { $0.request.identifier.hasPrefix(notificationPrefix) }

        return filtered
            .map {
                FestTimeNotificationItem(
                    id: $0.request.identifier,
                    title: $0.request.content.title,
                    body: $0.request.content.body,
                    date: $0.date
                )
            }
            .sorted { $0.date > $1.date }
    }

    func markDeliveredNotificationsAsRead(ids: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func scheduleTestNotification(after seconds: TimeInterval) async throws {
        let safeSeconds = max(1, seconds)
        let deliveredCount = await deliveredFestTimeNotifications().count

        let content = UNMutableNotificationContent()
        content.title = "Prueba de aviso"
        content.body = "FestTime: notificaciones y alarma funcionando."
        content.sound = .default
        content.badge = NSNumber(value: deliveredCount + 1)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: safeSeconds, repeats: false)
        let identifier = "festtime.test.\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await addRequest(request)
    }

    func scheduleReminders(
        festival: FestivalDefinition,
        events: [FestivalEvent],
        favoriteIDs: Set<String>,
        reminderMinutes: [Int]
    ) async throws {
        await clearReminders(for: festival.id)

        let now = Date()
        let positiveOffsets = reminderMinutes.filter { $0 > 0 }
        var candidates: [(event: FestivalEvent, offset: Int, reminderDate: Date)] = []

        for event in events where favoriteIDs.contains(event.id) {
            guard let eventDate = eventDate(for: event, in: festival) else { continue }

            for offset in positiveOffsets {
                let reminderDate = eventDate.addingTimeInterval(TimeInterval(-offset * 60))
                guard reminderDate > now else { continue }
                candidates.append((event, offset, reminderDate))
            }
        }

        let sortedCandidates = candidates.sorted { $0.reminderDate < $1.reminderDate }
        let limitedCandidates = Array(sortedCandidates.prefix(maxPendingReminders))
        let deliveredCount = await deliveredFestTimeNotifications().count

        for (index, candidate) in limitedCandidates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "En \(candidate.offset) min: \(candidate.event.artista)"
            content.body = "\(festival.displayName) · \(candidate.event.escenario) · \(candidate.event.hora) h"
            content.sound = .default
            content.badge = NSNumber(value: deliveredCount + index + 1)

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let timeStamp = Int(candidate.reminderDate.timeIntervalSince1970)
            let identifier = "\(reminderPrefix(for: festival.id))\(timeStamp)-\(candidate.offset)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await addRequest(request)
            } catch {
                // Continue scheduling remaining reminders even if one request fails.
                continue
            }
        }
    }

    private func eventDate(for event: FestivalEvent, in festival: FestivalDefinition) -> Date? {
        guard let day = festival.days.first(where: { $0.id == event.dia }),
              let dayDateString = day.calendarDate,
              let startTime = event.startHourMinute else {
            return nil
        }

        let hour = startTime.hour
        let minute = startTime.minute

        let dateParser = DateFormatter()
        dateParser.calendar = Calendar(identifier: .gregorian)
        dateParser.locale = Locale(identifier: "es_ES")
        dateParser.timeZone = .current
        dateParser.dateFormat = "yyyy-MM-dd"

        guard let baseDate = dateParser.date(from: dayDateString) else {
            return nil
        }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute

        guard var fullDate = Calendar.current.date(from: components) else {
            return nil
        }

        // Festival nights continue after midnight as part of the same program day.
        if hour < 10 {
            fullDate = Calendar.current.date(byAdding: .day, value: 1, to: fullDate) ?? fullDate
        }

        return fullDate
    }

    private func reminderPrefix(for festivalID: String) -> String {
        "festtime.reminder.\(festivalID)."
    }

    private func pendingRequestIDs() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    private func deliveredNotificationIDs() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map { $0.request.identifier })
            }
        }
    }

    private func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }

    private func addRequest(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
