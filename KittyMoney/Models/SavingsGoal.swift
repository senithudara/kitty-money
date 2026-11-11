import Foundation
import SwiftData

/// Something you're saving towards, with an optional monthly amount to put aside.
@Model
final class SavingsGoal {
    var id: UUID = UUID()
    var name: String = ""
    /// 0 means no overall target, just steady saving.
    var targetAmount: Double = 0
    /// How much you plan to put aside each month. 0 means no monthly plan.
    var monthlyAmount: Double = 0
    var colorHex: String = "#1F4D35"
    var createdAt: Date = Date()

    /// The account the savings sit in.
    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \SavingsDeposit.goal)
    var deposits: [SavingsDeposit] = []

    init(name: String, targetAmount: Double = 0, monthlyAmount: Double = 0, colorHex: String = "#1F4D35") {
        self.name = name
        self.targetAmount = targetAmount
        self.monthlyAmount = monthlyAmount
        self.colorHex = colorHex
    }

    var totalSaved: Double {
        deposits.reduce(0) { $0 + $1.amount }
    }

    var savedThisMonth: Double {
        let start = Date().startOfMonth
        return deposits.filter { $0.date >= start }.reduce(0) { $0 + $1.amount }
    }

    /// 0...1 progress towards the target (0 when there's no target).
    var progress: Double {
        targetAmount > 0 ? totalSaved / targetAmount : 0
    }

    var sortedDeposits: [SavingsDeposit] {
        deposits.sorted { $0.date > $1.date }
    }
}

/// One amount put into a savings goal.
@Model
final class SavingsDeposit {
    var id: UUID = UUID()
    /// Positive for a deposit, negative for a withdrawal.
    var amount: Double = 0
    var date: Date = Date()
    var note: String = ""
    /// The transfer transaction created for this deposit, if money moved between your accounts.
    var transactionID: UUID?

    var goal: SavingsGoal?

    init(amount: Double, date: Date = Date(), note: String = "") {
        self.amount = amount
        self.date = date
        self.note = note
    }
}
