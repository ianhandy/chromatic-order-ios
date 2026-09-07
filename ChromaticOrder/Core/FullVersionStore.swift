import Foundation
import Observation
import StoreKit
import UserNotifications

enum FullVersionAccess {
    static let freeCampaignChapterCount = 4

    static var lastFreeCampaignLevel: Int {
        CampaignCatalog.chapters
            .prefix(freeCampaignChapterCount)
            .last?.last ?? 0
    }

    static func campaignLevelRequiresPurchase(_ index: Int) -> Bool {
        index > lastFreeCampaignLevel
    }

    static func modeRequiresPurchase(_ mode: GameMode) -> Bool {
        mode != .daily
    }

    static func sessionRequiresPurchase(
        campaignIndex: Int?,
        mode: GameMode,
        isCustomPuzzle: Bool = false,
        isTrialSession: Bool = false
    ) -> Bool {
        if isTrialSession { return false }
        if let campaignIndex {
            return campaignLevelRequiresPurchase(campaignIndex)
        }
        // Gallery puzzles and puzzles received through files or links are a
        // free sharing loop. They play on the Zen board, but they are not the
        // paid, procedurally-generated Zen mode.
        if isCustomPuzzle { return false }
        return modeRequiresPurchase(mode)
    }
}

enum FullVersionTrial: String, CaseIterable, Hashable {
    case zen
    case challenge
    case creator

    var feature: FullVersionFeature {
        switch self {
        case .zen: return .zen
        case .challenge: return .challenge
        case .creator: return .creator
        }
    }

    init?(mode: GameMode) {
        switch mode {
        case .zen: self = .zen
        case .challenge: self = .challenge
        case .daily: return nil
        }
    }

    var repeatsOnCooldown: Bool {
        self == .zen || self == .challenge
    }
}

enum FullVersionTrialStore {
    private static let completedKeyPrefix = "kromaFullVersionTrialCompleted_"
    private static let lastStartedKeyPrefix = "kromaFullVersionTrialLastStarted_v1_"
    static let cooldown: TimeInterval = 3 * 60 * 60

    static func hasCompleted(
        _ trial: FullVersionTrial,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: completedKeyPrefix + trial.rawValue)
    }

    static func complete(
        _ trial: FullVersionTrial,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: completedKeyPrefix + trial.rawValue)
    }

    static func lastStarted(
        _ trial: FullVersionTrial,
        defaults: UserDefaults = .standard
    ) -> Date? {
        defaults.object(forKey: lastStartedKeyPrefix + trial.rawValue) as? Date
    }

    static func begin(
        _ trial: FullVersionTrial,
        at date: Date,
        defaults: UserDefaults = .standard
    ) {
        guard trial.repeatsOnCooldown else { return }
        defaults.set(date, forKey: lastStartedKeyPrefix + trial.rawValue)
    }

    static func nextAvailability(
        _ trial: FullVersionTrial,
        calendar: Calendar,
        defaults: UserDefaults = .standard
    ) -> Date? {
        guard trial.repeatsOnCooldown,
              let lastStarted = lastStarted(trial, defaults: defaults) else {
            return nil
        }

        let cooldownEnd = lastStarted.addingTimeInterval(cooldown)
        let startOfDay = calendar.startOfDay(for: lastStarted)
        guard let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay),
              let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return cooldownEnd
        }
        let rollingBoundary = lastStarted < noon ? noon : nextMidnight
        return min(cooldownEnd, rollingBoundary)
    }

    #if DEBUG
    static func reset(defaults: UserDefaults = .standard) {
        for trial in FullVersionTrial.allCases {
            defaults.removeObject(forKey: completedKeyPrefix + trial.rawValue)
            defaults.removeObject(forKey: lastStartedKeyPrefix + trial.rawValue)
        }
    }
    #endif
}

enum TrialReminderStore {
    private static let identifierPrefix = "kroma.trialReady."

    static func identifier(for trial: FullVersionTrial) -> String {
        identifierPrefix + trial.rawValue
    }

    static func notificationCopy(for trial: FullVersionTrial) -> (title: String, body: String) {
        let mode = trial == .zen ? "zen" : "challenge"
        return ("wanna play?", "\(mode) is ready again")
    }

    static func schedule(
        _ trial: FullVersionTrial,
        at availableAt: Date,
        now: Date = Date()
    ) async -> Bool {
        guard trial.repeatsOnCooldown, availableAt > now else { return false }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }

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

            let identifier = identifier(for: trial)
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            let copy = notificationCopy(for: trial)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, availableAt.timeIntervalSince(now)),
                repeats: false
            )
            try await center.add(UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            ))
            return true
        } catch {
            return false
        }
    }

    static func remove(_ trial: FullVersionTrial) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: trial)]
        )
    }

    static func removeAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: FullVersionTrial.allCases.map { identifier(for: $0) }
        )
    }
}

/// StoreKit 2 owner for Kromatika's single, permanent full-game unlock.
/// Entitlement state always comes from a verified App Store transaction;
/// there is no local boolean that can drift from refunds or account changes.
@MainActor
@Observable
final class FullVersionStore {
    static let productID = "com.ianhandy.kroma.full_version"

    private(set) var isUnlocked = false
    private(set) var product: Product?
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var trialRevision = 0
    var notice: String?

    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func canTry(_ trial: FullVersionTrial, now: Date = Date()) -> Bool {
        _ = trialRevision
        if trial.repeatsOnCooldown {
            guard let next = FullVersionTrialStore.nextAvailability(
                trial,
                calendar: calendar,
                defaults: defaults
            ) else { return true }
            return now >= next
        }
        return !FullVersionTrialStore.hasCompleted(trial, defaults: defaults)
    }

    func hasTried(_ trial: FullVersionTrial) -> Bool {
        _ = trialRevision
        if trial.repeatsOnCooldown {
            return FullVersionTrialStore.lastStarted(trial, defaults: defaults) != nil
        }
        return FullVersionTrialStore.hasCompleted(trial, defaults: defaults)
    }

    @discardableResult
    func beginTrial(_ trial: FullVersionTrial, now: Date = Date()) -> Bool {
        guard trial.repeatsOnCooldown, canTry(trial, now: now) else { return false }
        TrialReminderStore.remove(trial)
        FullVersionTrialStore.begin(trial, at: now, defaults: defaults)
        trialRevision &+= 1
        return true
    }

    func canOfferReminder(_ trial: FullVersionTrial, now: Date = Date()) -> Bool {
        guard !isUnlocked,
              hasTried(trial),
              !canTry(trial, now: now),
              let availableAt = nextTrialAvailability(trial) else { return false }
        return availableAt > now
    }

    func scheduleReminder(_ trial: FullVersionTrial, now: Date = Date()) async -> Bool {
        guard canOfferReminder(trial, now: now),
              let availableAt = nextTrialAvailability(trial) else { return false }
        return await TrialReminderStore.schedule(trial, at: availableAt, now: now)
    }

    func nextTrialAvailability(_ trial: FullVersionTrial) -> Date? {
        _ = trialRevision
        return FullVersionTrialStore.nextAvailability(
            trial,
            calendar: calendar,
            defaults: defaults
        )
    }

    func completeTrial(_ trial: FullVersionTrial) {
        // Zen and Challenge are spent when a new run begins. Creator keeps
        // its one-time completion rule because it is not a play session.
        guard !trial.repeatsOnCooldown,
              !FullVersionTrialStore.hasCompleted(trial, defaults: defaults) else { return }
        FullVersionTrialStore.complete(trial, defaults: defaults)
        trialRevision &+= 1
    }

    func prepare() async {
        if !didStart {
            didStart = true
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { return }
                    await self?.consume(result)
                }
            }
        }

        await refreshEntitlement()
        await loadProduct()
    }

    func reloadProduct() async {
        notice = nil
        await loadProduct()
    }

    @discardableResult
    func purchase() async -> Bool {
        if product == nil { await loadProduct() }
        guard let product else {
            notice = "the full version isn’t available right now"
            return false
        }

        isPurchasing = true
        notice = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    notice = "the purchase couldn’t be verified"
                    return false
                }
                await transaction.finish()
                await refreshEntitlement()
                return isUnlocked
            case .pending:
                notice = "purchase pending approval"
                return false
            case .userCancelled:
                return false
            @unknown default:
                notice = "the purchase couldn’t be completed"
                return false
            }
        } catch {
            notice = "the purchase couldn’t be completed"
            return false
        }
    }

    func restore() async {
        isPurchasing = true
        notice = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
            notice = isUnlocked ? "purchase restored" : "no purchase found"
        } catch {
            notice = "restore couldn’t be completed"
        }
    }

    private func loadProduct() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil {
                notice = "the full version isn’t available right now"
            }
        } catch {
            product = nil
            notice = "the full version isn’t available right now"
        }
    }

    private func refreshEntitlement() async {
        guard let result = await Transaction.currentEntitlement(for: Self.productID),
              case .verified(let transaction) = result,
              transaction.revocationDate == nil else {
            isUnlocked = false
            return
        }
        isUnlocked = true
        TrialReminderStore.removeAll()
    }

    private func consume(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result,
              transaction.productID == Self.productID else { return }
        await transaction.finish()
        await refreshEntitlement()
    }

    deinit {
        updatesTask?.cancel()
    }
}
