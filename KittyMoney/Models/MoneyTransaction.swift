import Foundation
import SwiftData

enum TransactionKind: String, CaseIterable, Codable, Identifiable {
    case expense = "Expense"
    case income = "Income"
    case transfer = "Transfer"

    var id: String { rawValue }
}

enum TransactionSource: String, Codable {
    case manual
    case sms
    case email
    /// Created automatically on a subscription's renewal day.
    case subscription
}

/// One money movement. Named `MoneyTransaction` to avoid clashing with SwiftUI's `Transaction`.
@Model
final class MoneyTransaction {
    var id: UUID = UUID()
    /// Always positive. `kind` decides the direction.
    var amount: Double = 0
    var kindRaw: String = TransactionKind.expense.rawValue
    var title: String = ""
    var note: String = ""
    var date: Date = Date()
    var sourceRaw: String = TransactionSource.manual.rawValue
    /// Original SMS or email text, kept so a bad parse can be fixed later.
    var rawMessage: String?
    var needsReview: Bool = false
    /// The category was guessed from Apple Maps or Apple Intelligence (shows an "Auto" label).
    var categoryGuessed: Bool = false
    /// False for transactions the app added on its own (SMS, renewals) until you've looked at them.
    var isSeen: Bool = true
    /// For transfers: the account money moved into.
    var transferTargetID: UUID?
    /// The Koko / Mintpay installment this payment settled, if matched.
    var installmentID: UUID?
    /// The subscription this payment belongs to, if matched.
    var subscriptionID: UUID?

    var account: Account?
    var category: BudgetCategory?

    init(
        amount: Double,
        kind: TransactionKind,
        title: String,
        date: Date = Date(),
        note: String = "",
        source: TransactionSource = .manual,
        account: Account? = nil,
        category: BudgetCategory? = nil
    ) {
        self.amount = amount
        self.kindRaw = kind.rawValue
        self.title = title
        self.date = date
        self.note = note
        self.sourceRaw = source.rawValue
        self.account = account
        self.category = category
    }

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// Positive for money in, negative for money out of `account`.
    var signedAmount: Double {
        kind == .income ? amount : -amount
    }
}
