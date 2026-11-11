import Foundation
import SwiftData

/// Turns subscription renewals that have come due into expense transactions,
/// converting foreign currencies at that day's rate, then moves each renewal date forward.
/// Runs when the app opens or comes back to the foreground.
enum RenewalProcessor {
    @MainActor
    static func run(in context: ModelContext) async {
        let now = Date()
        let descriptor = FetchDescriptor<SubscriptionPlan>(predicate: #Predicate { $0.isActive && $0.autoRecord })
        let subscriptions = (try? context.fetch(descriptor)) ?? []
        let due = subscriptions.filter { $0.nextRenewal <= now }
        guard !due.isEmpty else { return }

        // Foreign renewals need a fresh rate for the day they're recorded.
        if due.contains(where: { $0.currency != .lkr }) {
            await ExchangeRates.refreshIfNeeded(maxAge: 3 * 3600)
        }

        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        let subscriptionCategory = categories.first { $0.name == "Subscriptions" && !$0.isIncome }
        let calendar = Calendar.current

        for subscription in due {
            let firstRecordableDay = calendar.startOfDay(for: subscription.createdAt)
            var steps = 0
            while subscription.nextRenewal <= now && steps < 24 {
                // Renewals from before the subscription was added to the app are skipped, not back-filled.
                if subscription.nextRenewal >= firstRecordableDay {
                    let recorded = record(subscription, on: subscription.nextRenewal, category: subscriptionCategory, in: context)
                    // No exchange rate available (offline): try again next time the app opens.
                    if !recorded { break }
                }
                subscription.nextRenewal = subscription.cycle.advance(subscription.nextRenewal)
                steps += 1
            }
        }
        try? context.save()
    }

    @MainActor
    private static func record(_ subscription: SubscriptionPlan, on date: Date, category: BudgetCategory?, in context: ModelContext) -> Bool {
        guard let rate = ExchangeRates.cachedRate(for: subscription.currencyCode) else { return false }
        let isForeign = subscription.currency != .lkr
        let lkrAmount = (subscription.amount * rate * 100).rounded() / 100

        let note: String
        if isForeign {
            note = "\(Money.format(subscription.amount, currency: subscription.currency)) at Rs. \(String(format: "%.2f", rate)). Edit if your bank charged a different amount."
        } else {
            note = "Subscription renewal"
        }

        let transaction = MoneyTransaction(amount: lkrAmount, kind: .expense, title: subscription.name, date: date, note: note, source: .subscription)
        context.insert(transaction)
        transaction.account = subscription.account
        transaction.category = category
        transaction.needsReview = isForeign
        transaction.isSeen = false
        Ledger.apply(transaction, in: context)
        return true
    }
}
