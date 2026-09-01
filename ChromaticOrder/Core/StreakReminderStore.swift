import Foundation
import UserNotifications

enum StreakReminderStore {
    private static let enabledKey = "kromaDailyStreakReminder_v1"
    private static let timeKey = "kromaDailyStreakReminderMinuteOfDay_v2"
    private static let identifierPrefix = "kroma.dailyStreakReminder."
    private static let daysScheduled = 14
    private static let defaultMinuteOfDay = 20 * 60

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var reminderTime: Date {
        date(
            on: localCalendar.startOfDay(for: Date()),
            minuteOfDay: reminderMinuteOfDay,
            calendar: localCalendar
        )
    }

    static func setReminderTime(_ date: Date) async {
        let components = localCalendar.dateComponents([.hour, .minute], from: date)
        let raw = (components.hour ?? 20) * 60 + (components.minute ?? 0)
        let snapped = max(0, min(23 * 60 + 45, (raw / 15) * 15))
        UserDefaults.standard.set(snapped, forKey: timeKey)
        if isEnabled { await refresh() }
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
        let calendar = localCalendar
        let firstReminder = nextReminderDate(now: now)

        for offset in 0..<daysScheduled {
            guard let fireDate = calendar.date(
                byAdding: .day,
                value: offset,
                to: firstReminder
            ) else { continue }
            let key = Daily.dateKey(now: fireDate)
            guard !completed.contains(key) else { continue }

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
        nextReminderDate(
            now: now,
            minuteOfDay: reminderMinuteOfDay,
            calendar: localCalendar
        )
    }

    static func nextReminderDate(
        now: Date,
        minuteOfDay: Int,
        calendar: Calendar
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        let candidate = date(on: today, minuteOfDay: minuteOfDay, calendar: calendar)
        if candidate > now { return candidate }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return date(on: tomorrow, minuteOfDay: minuteOfDay, calendar: calendar)
    }

    private static func removePendingReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private static var reminderMinuteOfDay: Int {
        guard UserDefaults.standard.object(forKey: timeKey) != nil else {
            return defaultMinuteOfDay
        }
        let value = UserDefaults.standard.integer(forKey: timeKey)
        return max(0, min(23 * 60 + 45, value))
    }

    private static var localCalendar: Calendar { .autoupdatingCurrent }

    private static func date(
        on day: Date,
        minuteOfDay: Int,
        calendar: Calendar
    ) -> Date {
        let safe = max(0, min(23 * 60 + 45, minuteOfDay))
        return calendar.date(
            bySettingHour: safe / 60,
            minute: safe % 60,
            second: 0,
            of: day,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? day
    }
}
