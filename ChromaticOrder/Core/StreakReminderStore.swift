import Foundation
import UserNotifications

enum StreakReminderStore {
    private static let enabledKey = "kromaDailyStreakReminder_v1"
    private static let identifierPrefix = "kroma.dailyStreakReminder."
    private static let daysScheduled = 14
    private static let leadTime: TimeInterval = 2 * 60 * 60

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool) async -> Bool {
        if !enabled {
            UserDefaults.standard.set(false, forKey: enabledKey)
            await removePendingReminders()
            return true
        }

        #if targetEnvironment(simulator)
        // The simulator can grant notifications, so keep the real path.
        #endif
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let granted: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                granted = true
            case .notDetermined:
                granted = try await center.requestAuthorization(options: [.alert, .sound])
            case .denied:
                granted = false
            @unknown default:
                granted = false
            }
            guard granted else { return false }
            UserDefaults.standard.set(true, forKey: enabledKey)
            await refresh()
            return true
        } catch {
            return false
        }
    }

    static func refresh(now: Date = Date()) async {
        guard isEnabled else { return }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            await removePendingReminders()
            return
        }

        await removePendingReminders()
        let completed = Set(DailyHistoryStore.entries().filter(\.completed).map(\.dateKey))
        let calendar = utcCalendar
        let todayStart = calendar.startOfDay(for: now)

        for offset in 0..<daysScheduled {
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart),
                  let reset = calendar.date(byAdding: .day, value: 1, to: day)
            else { continue }
            let key = Daily.dateKey(now: day)
            let fireDate = reset.addingTimeInterval(-leadTime)
            guard fireDate > now, !completed.contains(key) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "keep your streak"
            content.body = "today’s daily is still waiting"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: fireDate.timeIntervalSince(now),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: identifierPrefix + key,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func markCompleted(_ dateKey: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifierPrefix + dateKey]
        )
        Task { await refresh() }
    }

    static func nextReminderDescription(now: Date = Date()) -> String {
        nextReminderDate(now: now)
            .formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func nextReminderDate(now: Date = Date()) -> Date {
        let start = utcCalendar.startOfDay(for: now)
        var reminder = start.addingTimeInterval(24 * 60 * 60 - leadTime)
        if reminder <= now { reminder.addTimeInterval(24 * 60 * 60) }
        return reminder
    }

    private static func removePendingReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private static var utcCalendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()
}
