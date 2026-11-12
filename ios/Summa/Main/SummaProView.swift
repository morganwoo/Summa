import SwiftUI
import StoreKit

/// Why the subscription page is being shown. Only ever presented in response to
/// something the person tried to do, or when they open it themselves.
enum PaywallContext: String, Identifiable {
    case habits, reminders, widgets, friends, graduation, settings, reflections
    var id: String { rawValue }

    var headline: String {
        switch self {
        case .habits: return "Summa Free holds three active habits. Pro removes the limit."
        case .reminders: return "Summa Free includes one daily reminder. Pro adds reminders for every habit and a second time for each."
        case .widgets: return "Home-screen widgets are part of Summa Pro."
        case .friends: return "Summa Free holds two friends. Pro makes your circle unlimited."
        case .graduation: return "The graduation certificate and highlight reel are part of Summa Pro."
        case .settings: return "Everything in Summa Free, with the limits removed."
        case .reflections: return "Daily reflections, conversations with Summa, and \(Colosseum.title) are part of Summa Pro."
        }
    }
}

/// The Summa Pro subscription page.
struct SummaProView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var store = Store.shared
    let context: PaywallContext

    @State private var selectedID: String = Store.ProductID.annual

    private let featureIcons = ["infinity", "person.2", "bell.badge", "square.grid.2x2", "seal", "book.closed"]
    private let featureTexts = ["Unlimited active habits", "Unlimited friends (Free includes two)", "Reminders for every habit, with a second time for each",
                                "Home-screen widgets", "Graduation certificate and highlight reel",
                                "Daily reflections, with Summa to talk them through"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        LaurelWreath(size: 54, weight: .light).foregroundStyle(theme.gold).accessibilityHidden(true)
                        Text("Summa Pro")
                            .font(SummaFont.serif(42, relativeTo: .largeTitle))
                            .accessibilityAddTraits(.isHeader)
                        Text(context.headline).font(.body).foregroundStyle(theme.muted)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<featureTexts.count, id: \.self) { index in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: featureIcons[index]).foregroundStyle(theme.gold).frame(width: 24)
                                Text(featureTexts[index]).font(.subheadline)
                            }
                        }
                        Text("Friends, leaderboards, nudges, weekly reports, and the full 90-day program are free for everyone.")
                            .font(.footnote).foregroundStyle(theme.muted)
                    }
                    .card()

                    if store.isPro {
                        active
                    } else {
                        offers
                    }
                    outcomeNote
                    legal
                }
                .padding(20)
            }
            .marbleBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("pro.close")
                }
            }
        }
        .foregroundStyle(theme.text)
        .accessibilityIdentifier("pro.page")
        .task {
            store.outcome = .none
            if store.loadState != .loaded { await store.loadProducts() }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { Haptics.commit() }
        }
    }

    private var active: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("You have \(store.planName).", systemImage: "checkmark.seal.fill")
                .font(.headline).foregroundStyle(theme.gold)
            if let date = store.expirationDate {
                Text("Renews or ends on \(date.formatted(date: .long, time: .omitted)).").font(.footnote).foregroundStyle(theme.muted)
            }
            if store.activeProductID != Store.ProductID.lifetime, store.activeProductID != nil {
                Button("Manage subscription") {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
            }
            Button("Done") { dismiss() }.buttonStyle(.summaPrimary)
        }
        .card()
    }

    @ViewBuilder
    private var offers: some View {
        switch store.loadState {
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading plans from the App Store").font(.subheadline).foregroundStyle(theme.muted)
            }
            .card()
        case .unavailable:
            VStack(alignment: .leading, spacing: 8) {
                Text("Plans are not available right now.").font(.headline)
                Text("The App Store could not be reached, or purchases are not set up for this build. Nothing has been charged.")
                    .font(.footnote).foregroundStyle(theme.muted)
                Button("Try again") { Task { await store.loadProducts() } }
                    .buttonStyle(.summaSecondary)
                    .accessibilityIdentifier("pro.retry")
            }
            .card()
        case .loaded:
            VStack(spacing: 10) {
                ForEach(store.products, id: \.id) { product in
                    productRow(product)
                }
            }
            Button {
                guard let product = store.products.first(where: { $0.id == selectedID }) ?? store.products.first else { return }
                Task { await store.purchase(product) }
            } label: {
                if store.isWorking { ProgressView().tint(theme.onGold) } else { Text("Continue") }
            }
            .buttonStyle(.summaPrimary)
            .disabled(store.isWorking)
            .accessibilityIdentifier("pro.purchase")
        }
        Button("Restore purchases") { Task { await store.restore() } }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.gold)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(store.isWorking)
            .accessibilityIdentifier("pro.restore")
    }

    private func productRow(_ product: Product) -> some View {
        let isSelected = selectedID == product.id
        return Button {
            Haptics.select()
            selectedID = product.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? theme.gold : theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(.headline).foregroundStyle(theme.text)
                    Text(terms(for: product)).font(.footnote).foregroundStyle(theme.muted)
                }
                Spacer(minLength: 8)
                Text(product.displayPrice).font(.headline).foregroundStyle(theme.text)
            }
            .padding(16)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isSelected ? theme.gold : theme.divider, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice), \(terms(for: product))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pro.product.\(product.id)")
    }

    private func terms(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "One payment. Yours to keep." }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 7 ? "week" : "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        let length = period.value == 1 || (period.unit == .day && period.value == 7) ? "every \(unit)" : "every \(period.value) \(unit)s"
        return "Billed \(length). Renews until cancelled."
    }

    @ViewBuilder
    private var outcomeNote: some View {
        switch store.outcome {
        case .none, .cancelled, .purchased:
            EmptyView()
        case .pending:
            note("Your purchase is waiting for approval. Summa Pro unlocks automatically once it is approved.", icon: "clock")
        case .restored:
            note("Your purchases were restored.", icon: "checkmark.circle")
        case .nothingToRestore:
            note("No Summa Pro purchase was found for this Apple Account.", icon: "info.circle")
        case .failed(let message):
            note("The purchase did not go through. \(message)", icon: "exclamationmark.circle")
        }
    }

    private func note(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(theme.text)
            .card(padding: 14)
            .accessibilityIdentifier("pro.outcome")
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payment is charged to your Apple Account at confirmation. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel in your App Store account settings. The lifetime option is a single purchase that does not renew.")
                .font(.caption).foregroundStyle(theme.muted)
            Button("Terms of Use") {
                if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") { openURL(url) }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(theme.gold).frame(minHeight: 44)
        }
    }
}
