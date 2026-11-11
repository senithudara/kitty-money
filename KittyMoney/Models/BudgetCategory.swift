import Foundation
import SwiftData

/// A spending category with an optional monthly limit.
@Model
final class BudgetCategory {
    var id: UUID = UUID()
    var name: String = ""
    /// Two-letter label shown in the category tile, e.g. "GR".
    var mono: String = ""
    /// 0 means no limit set.
    var monthlyLimit: Double = 0
    var sortOrder: Int = 0
    var isIncome: Bool = false
    /// Merchant text that auto-assigns this category, e.g. ["KEELLS", "CARGILLS"].
    var keywords: [String] = []

    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.category)
    var transactions: [MoneyTransaction] = []

    init(name: String, mono: String, monthlyLimit: Double = 0, sortOrder: Int = 0, isIncome: Bool = false, keywords: [String] = []) {
        self.name = name
        self.mono = mono
        self.monthlyLimit = monthlyLimit
        self.sortOrder = sortOrder
        self.isIncome = isIncome
        self.keywords = keywords
    }
}
