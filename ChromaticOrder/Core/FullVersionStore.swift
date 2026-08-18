import Foundation
import Observation
import StoreKit

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

enum FullVersionTrial: String, CaseIterable {
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
}

enum FullVersionTrialStore {
    private static let keyPrefix = "kromaFullVersionTrialCompleted_"

    static func hasCompleted(_ trial: FullVersionTrial) -> Bool {
        UserDefaults.standard.bool(forKey: keyPrefix + trial.rawValue)
    }

    static func complete(_ trial: FullVersionTrial) {
        UserDefaults.standard.set(true, forKey: keyPrefix + trial.rawValue)
    }

    #if DEBUG
    static func reset() {
        for trial in FullVersionTrial.allCases {
            UserDefaults.standard.removeObject(forKey: keyPrefix + trial.rawValue)
        }
    }
    #endif
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

    func canTry(_ trial: FullVersionTrial) -> Bool {
        _ = trialRevision
        return !FullVersionTrialStore.hasCompleted(trial)
    }

    func hasTried(_ trial: FullVersionTrial) -> Bool {
        _ = trialRevision
        return FullVersionTrialStore.hasCompleted(trial)
    }

    func completeTrial(_ trial: FullVersionTrial) {
        guard !FullVersionTrialStore.hasCompleted(trial) else { return }
        FullVersionTrialStore.complete(trial)
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
