import Foundation
import SwiftData

enum BillingCycle: String, CaseIterable, Codable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"

    var id: String { rawValue }

    func advance(_ date: Date, calendar: Calendar = .current) -> Date {
        let next: Date?
        switch self {
        case .weekly: next = calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly: next = calendar.date(byAdding: .month, value: 1, to: date)
        case .quarterly: next = calendar.date(byAdding: .month, value: 3, to: date)
        case .yearly: next = calendar.date(byAdding: .year, value: 1, to: date)
        }
        return next ?? date
    }
}

/// A recurring payment like Netflix or Spotify. Named to avoid clashing with Combine's `Subscription`.
@Model
final class SubscriptionPlan {
    var id: UUID = UUID()
    var name: String = ""
    var amount: Double = 0
    var cycleRaw: String = BillingCycle.monthly.rawValue
    /// The stored renewal date. Use `upcomingRenewal()` for the next real one.
    var nextRenewal: Date = Date()
    var colorHex: String = "#3A3A42"
    var logoDomain: String?
    @Attribute(.externalStorage) var logoData: Data?
    var isActive: Bool = true
    var createdAt: Date = Date()
    /// Currency `amount` is charged in. Foreign amounts are converted to LKR on renewal day.
    var currencyCode: String = Currency.lkr.rawValue
    /// Add an expense transaction automatically on each renewal day.
    var autoRecord: Bool = true

    var account: Account?

    init(name: String, amount: Double, cycle: BillingCycle = .monthly, nextRenewal: Date, colorHex: String = "#3A3A42", logoDomain: String? = nil, account: Account? = nil) {
        self.name = name
        self.amount = amount
        self.cycleRaw = cycle.rawValue
        self.nextRenewal = nextRenewal
        self.colorHex = colorHex
        self.logoDomain = logoDomain
        self.account = account
    }

    var currency: Currency {
        get { Currency(rawValue: currencyCode) ?? .lkr }
        set { currencyCode = newValue.rawValue }
    }

    /// Amount in rupees using the latest saved exchange rate. Nil if no rate has been fetched yet.
    var amountInLKR: Double? {
        guard let rate = ExchangeRates.cachedRate(for: currencyCode) else { return nil }
        return amount * rate
    }

    /// Rupee amount for totals and budgets (0 until a rate is available).
    var estimatedLKR: Double { amountInLKR ?? 0 }

    /// "Rs. 1,690" for rupee subscriptions, "USD 20.00" for foreign ones.
    var displayAmount: String { Money.format(amount, currency: currency) }

    /// "≈ Rs. 6,020" for foreign subscriptions, nil for rupee ones.
    var lkrEstimateText: String? {
        guard currency != .lkr else { return nil }
        guard let lkr = amountInLKR else { return "Rate not loaded yet" }
        return "≈ " + Money.format(lkr)
    }

    var cycle: BillingCycle {
        get { BillingCycle(rawValue: cycleRaw) ?? .monthly }
        set { cycleRaw = newValue.rawValue }
    }

    /// The next renewal on or after `date`, rolling past renewals forward by the billing cycle.
    func upcomingRenewal(onOrAfter date: Date = Date()) -> Date {
        let today = Calendar.current.startOfDay(for: date)
        var renewal = nextRenewal
        var steps = 0
        while renewal < today && steps < 600 {
            renewal = cycle.advance(renewal)
            steps += 1
        }
        return renewal
    }
}
