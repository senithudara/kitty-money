import Foundation
import SwiftData

/// Keeps account balances in step with transactions.
enum Ledger {
    static func apply(_ transaction: MoneyTransaction, in context: ModelContext) {
        adjust(transaction, by: 1, in: context)
    }

    static func reverse(_ transaction: MoneyTransaction, in context: ModelContext) {
        adjust(transaction, by: -1, in: context)
    }

    static func delete(_ transaction: MoneyTransaction, in context: ModelContext) {
        reverse(transaction, in: context)
        context.delete(transaction)
        try? context.save()
    }

    private static func adjust(_ transaction: MoneyTransaction, by sign: Double, in context: ModelContext) {
        let value = transaction.amount * sign
        switch transaction.kind {
        case .expense:
            transaction.account?.balance -= value
        case .income:
            transaction.account?.balance += value
        case .transfer:
            transaction.account?.balance -= value
            if let targetID = transaction.transferTargetID, let target = account(id: targetID, in: context) {
                target.balance += value
            }
        }
    }

    static func account(id: UUID, in context: ModelContext) -> Account? {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    /// Remembers that a merchant belongs in `category`, so future SMS from it are categorized automatically.
    /// Only learns from real merchant names, not generic bank wording like "Transfer".
    static func learn(merchant title: String, rawMessage: String?, category: BudgetCategory, allCategories: [BudgetCategory]) {
        let key = title.trimmingCharacters(in: .whitespaces).uppercased()
        guard key.count >= 3, !isGenericTitle(key) else { return }
        // The key must actually appear in the SMS, otherwise future messages can't match it.
        if let raw = rawMessage?.uppercased(), !raw.contains(key) { return }

        for other in allCategories where other.id != category.id {
            other.keywords.removeAll { $0.uppercased() == key }
        }
        if !category.keywords.contains(where: { $0.uppercased() == key }) {
            category.keywords.append(key)
        }
    }

    /// Bank wording rather than a real merchant, e.g. "Online transfer" or "Card or ATM payment".
    static func isGenericTitle(_ title: String) -> Bool {
        let upper = title.uppercased()
        let generic = ["TRANSFER", "DEPOSIT", "PAYMENT", "ATM", "MONEY IN", "CEFT", "LPAY", "TFR"]
        return generic.contains { upper.contains($0) }
    }

    /// The category whose keyword best matches `text` (longest keyword wins, so "UBER EATS" beats "UBER").
    static func suggestedCategory(for text: String, in categories: [BudgetCategory]) -> BudgetCategory? {
        let upper = text.uppercased()
        var best: BudgetCategory?
        var bestLength = 0
        for category in categories {
            for keyword in category.keywords where !keyword.isEmpty && upper.contains(keyword.uppercased()) {
                if keyword.count > bestLength {
                    best = category
                    bestLength = keyword.count
                }
            }
        }
        return best
    }
}
