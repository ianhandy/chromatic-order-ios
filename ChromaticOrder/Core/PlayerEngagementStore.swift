import Foundation
import Observation

enum EnjoymentResponse: String {
    case yes
    case no
    case stopTalking
}

enum MenuNudge: String {
    case rate
    case feedback
}

/// Local-only engagement bookkeeping for the one-time enjoyment prompt.
///
/// This deliberately stores only aggregate gameplay seconds, a distinct-day
/// count plus the most recent local calendar day, and the player's response.
/// Nothing leaves the device and no per-session or per-day history is kept.
@MainActor
@Observable
final class PlayerEngagementStore {
    static let gameplayThreshold: TimeInterval = 60 * 60
    static let openedDayThreshold = 3

    private enum Key {
        static let gameplaySeconds = "kromaEngagementGameplaySeconds_v1"
        static let openedDayCount = "kromaEngagementOpenedDayCount_v1"
        static let lastOpenedDay = "kromaEngagementLastOpenedDay_v1"
        static let response = "kromaEngagementResponse_v1"
        static let pendingNudge = "kromaEngagementPendingNudge_v1"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var gameplayStartedAt: Date?
    private var appIsActive = false
    private var menuIsVisible = false

    private(set) var isPromptPresented = false
    private(set) var activeMenuNudge: MenuNudge?

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    var response: EnjoymentResponse? {
        defaults.string(forKey: Key.response).flatMap(EnjoymentResponse.init(rawValue:))
    }

    var cumulativeGameplaySeconds: TimeInterval {
        defaults.double(forKey: Key.gameplaySeconds)
    }

    var openedDayCount: Int {
        defaults.integer(forKey: Key.openedDayCount)
    }

    var rateUsLabel: String {
        response == .yes ? Strings.Menu.rateUsPlease : Strings.Menu.rateUs
    }

    func appDidBecomeActive(now: Date = Date()) {
        appIsActive = true
        registerOpenedDay(now)
        if menuIsVisible { presentIfEligibleAtMenu(now: now) }
    }

    func appDidResignActive(now: Date = Date()) {
        appIsActive = false
        stopGameplayClock(now: now)
    }

    func gameplayDidStart(now: Date = Date()) {
        guard appIsActive, gameplayStartedAt == nil else { return }
        gameplayStartedAt = now
    }

    func gameplayDidEnd(now: Date = Date()) {
        stopGameplayClock(now: now)
    }

    func menuDidAppear(now: Date = Date()) {
        menuIsVisible = true
        if let raw = defaults.string(forKey: Key.pendingNudge),
           let pending = MenuNudge(rawValue: raw) {
            activeMenuNudge = pending
        }
        presentIfEligibleAtMenu(now: now)
    }

    /// A response's glow lasts for exactly the first menu visit that follows
    /// it. If the app is killed before that visit ends, the persisted pending
    /// value intentionally makes the glow reappear next launch.
    func menuDidDisappear() {
        menuIsVisible = false
        guard activeMenuNudge != nil else { return }
        activeMenuNudge = nil
        defaults.removeObject(forKey: Key.pendingNudge)
    }

    func consumeMenuNudge(_ nudge: MenuNudge) {
        guard activeMenuNudge == nudge else { return }
        activeMenuNudge = nil
        defaults.removeObject(forKey: Key.pendingNudge)
    }

    func recordResponse(_ response: EnjoymentResponse) {
        defaults.set(response.rawValue, forKey: Key.response)
        switch response {
        case .yes:
            setPendingNudge(.rate)
        case .no:
            setPendingNudge(.feedback)
        case .stopTalking:
            activeMenuNudge = nil
            defaults.removeObject(forKey: Key.pendingNudge)
        }
    }

    func dismissPrompt() {
        isPromptPresented = false
    }

    func isEligible(now: Date = Date()) -> Bool {
        guard response == nil else { return false }
        let liveSeconds = gameplayStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return cumulativeGameplaySeconds + liveSeconds >= Self.gameplayThreshold
            || openedDayCount >= Self.openedDayThreshold
    }

    #if DEBUG
    func debugMakeEligible() {
        defaults.set(Self.gameplayThreshold, forKey: Key.gameplaySeconds)
        if menuIsVisible { presentIfEligibleAtMenu() }
    }
    #endif

    private func setPendingNudge(_ nudge: MenuNudge) {
        defaults.set(nudge.rawValue, forKey: Key.pendingNudge)
        if menuIsVisible { activeMenuNudge = nudge }
    }

    private func presentIfEligibleAtMenu(now: Date = Date()) {
        guard !isPromptPresented, isEligible(now: now) else { return }
        isPromptPresented = true
    }

    private func stopGameplayClock(now: Date) {
        guard let gameplayStartedAt else { return }
        let elapsed = max(0, now.timeIntervalSince(gameplayStartedAt))
        defaults.set(cumulativeGameplaySeconds + elapsed, forKey: Key.gameplaySeconds)
        self.gameplayStartedAt = nil
    }

    private func registerOpenedDay(_ date: Date) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return }
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        guard defaults.string(forKey: Key.lastOpenedDay) != key else { return }
        defaults.set(key, forKey: Key.lastOpenedDay)
        defaults.set(openedDayCount + 1, forKey: Key.openedDayCount)
    }
}
