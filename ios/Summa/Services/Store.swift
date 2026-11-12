import Foundation
import Combine
import StoreKit

/// Summa Pro purchases and entitlement, using StoreKit 2.
///
/// Entitlement is always derived from verified transactions on this device's Apple account.
/// Nothing here trusts a flag that the app itself could set.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    enum ProductID {
        static let monthly = "app.summa.pro.monthly"
        static let annual = "app.summa.pro.annual"
        static let lifetime = "app.summa.pro.lifetime"
        static let all = [annual, monthly, lifetime]
    }

    enum LoadState: Equatable { case loading, loaded, unavailable }

    enum Outcome: Equatable {
        case none, purchased, pending, cancelled, restored, nothingToRestore
        case failed(String)
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var isPro: Bool
    @Published private(set) var activeProductID: String?
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isWorking = false
    /// The signed transaction behind the current entitlement. The social backend verifies it itself.
    private(set) var latestTransactionJWS: String?
    @Published var outcome: Outcome = .none

    private var updates: Task<Void, Never>?
    private static let cacheKey = "summa.pro.cached"
    /// Test-only override; never set in a shipping configuration.
    private let forcedPro = AppEnvironment.arguments.contains("-proUnlocked")

    /// The answer from StoreKit, kept apart from any developer preview override.
    private var verifiedPro = false

    #if DEBUG
    /// Developer preview only: shows the app as Free or Pro without touching StoreKit, the cached
    /// entitlement, or any subscription. Held in memory, cleared when the preview closes, and
    /// compiled out of Release builds.
    private(set) var debugOverride: Bool?
    func setDebugOverride(_ value: Bool?) {
        debugOverride = value
        let now = value ?? verifiedPro
        if now != isPro { isPro = now }
    }
    var isDebugPro: Bool { forcedPro || debugOverride == true }
    #endif

    private init() {
        // The cached value only avoids a flash of the free state at launch; it is replaced
        // by the verified answer from StoreKit as soon as `start()` runs.
        isPro = forcedPro || UserDefaults.standard.bool(forKey: Self.cacheKey)
        verifiedPro = isPro
    }

    /// Begins listening for renewals, refunds, and purchases approved outside the app.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    func loadProducts() async {
        loadState = .loading
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = loaded.sorted { (ProductID.all.firstIndex(of: $0.id) ?? 9) < (ProductID.all.firstIndex(of: $1.id) ?? 9) }
            loadState = loaded.isEmpty ? .unavailable : .loaded
        } catch {
            products = []
            loadState = .unavailable
        }
    }

    func purchase(_ product: Product) async {
        guard !isWorking else { return }
        guard !DevSandbox.isActive else { outcome = .failed("Purchases are off in the developer preview."); return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    outcome = .failed("The App Store could not verify this purchase. You have not been charged for an unverified purchase.")
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                outcome = .purchased
            case .pending:
                // Ask to Buy or a bank check. Access starts when it is approved.
                outcome = .pending
            case .userCancelled:
                outcome = .cancelled
            @unknown default:
                outcome = .failed("The purchase did not complete.")
            }
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        guard !isWorking else { return }
        guard !DevSandbox.isActive else { outcome = .failed("Purchases are off in the developer preview."); return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            outcome = (isPro && !forcedPro) ? .restored : .nothingToRestore
        } catch {
            // Thrown when the person cancels the App Store sign-in, among other things.
            outcome = .failed(error.localizedDescription)
        }
    }

    /// Recomputes Pro from current, verified, unrevoked entitlements. Expired subscriptions
    /// are no longer listed by StoreKit, so an expiry simply returns the account to Free.
    func refreshEntitlements() async {
        var best: StoreKit.Transaction?
        var bestJWS: String?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                  ProductID.all.contains(transaction.productID) else { continue }
            if transaction.productID == ProductID.lifetime || best == nil {
                best = transaction
                bestJWS = result.jwsRepresentation
            }
        }
        latestTransactionJWS = bestJWS
        activeProductID = best?.productID
        expirationDate = best?.expirationDate
        UserDefaults.standard.set(best != nil, forKey: Self.cacheKey)
        verifiedPro = best != nil || forcedPro
        var now = verifiedPro
        #if DEBUG
        now = debugOverride ?? verifiedPro
        #endif
        if now != isPro { isPro = now }
    }

    var planName: String {
        switch activeProductID {
        case ProductID.monthly: return "Summa Pro, monthly"
        case ProductID.annual: return "Summa Pro, annual"
        case ProductID.lifetime: return "Summa Pro, lifetime"
        default: return isPro ? "Summa Pro" : "Summa Free"
        }
    }
}
