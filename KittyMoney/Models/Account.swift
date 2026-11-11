import Foundation
import SwiftData

enum AccountKind: String, CaseIterable, Codable, Identifiable {
    case savings = "Savings"
    case current = "Current"
    case card = "Card"
    case cash = "Cash"

    var id: String { rawValue }
}

/// A bank account, card or cash wallet.
@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var shortName: String = ""
    var last4: String = ""
    var kindRaw: String = AccountKind.savings.rawValue
    var balance: Double = 0
    var balanceUpdatedAt: Date?
    var colorHex: String = "#3A3A42"
    /// Website used to fetch a logo, e.g. "combank.lk".
    var logoDomain: String?
    @Attribute(.externalStorage) var logoData: Data?
    /// SMS sender ID the bank uses, e.g. "COMBANK". Used to route parsed messages.
    var smsSender: String?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    /// Whether this account counts towards the total balance on Home.
    var includeInTotal: Bool = true

    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.account)
    var transactions: [MoneyTransaction] = []

    @Relationship(deleteRule: .nullify, inverse: \SubscriptionPlan.account)
    var subscriptions: [SubscriptionPlan] = []

    @Relationship(deleteRule: .nullify, inverse: \InstallmentPlan.account)
    var installmentPlans: [InstallmentPlan] = []

    @Relationship(deleteRule: .nullify, inverse: \SavingsGoal.account)
    var savingsGoals: [SavingsGoal] = []

    init(
        name: String,
        shortName: String,
        last4: String = "",
        kind: AccountKind = .savings,
        balance: Double = 0,
        colorHex: String = "#3A3A42",
        logoDomain: String? = nil,
        smsSender: String? = nil,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.shortName = shortName
        self.last4 = last4
        self.kindRaw = kind.rawValue
        self.balance = balance
        self.colorHex = colorHex
        self.logoDomain = logoDomain
        self.smsSender = smsSender
        self.sortOrder = sortOrder
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .savings }
        set { kindRaw = newValue.rawValue }
    }
}
