import Foundation
import SwiftData
import UIKit
import WidgetKit

/// What the widget shows. The app writes this to the shared App Group folder;
/// the widget only reads it, so your database never has to move.
/// Keep in sync with the copy in KittyMoneyWidget.swift.
struct WidgetSnapshot: Codable {
    struct Payment: Codable {
        var id: String
        var title: String
        var amountText: String
        var dueDate: Date
        var colorHex: String
        var initial: String
        var logoFile: String?
    }

    var updatedAt: Date
    var hideAmounts: Bool
    var balance: Double
    /// "3 accounts" or "BOC + People's"
    var balanceLabel: String
    var budgetTotal: Double
    var spent: Double
    var payments: [Payment]
}

enum WidgetSync {
    static let appGroupID = "group.com.senithudara.kittymoney.shared"
    static let hideAmountsKey = "hideWidgetAmounts"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Rebuilds the widget's data and asks iOS to redraw it.
    @MainActor
    static func update(from context: ModelContext) {
        guard let folder else { return }
        let logosFolder = folder.appendingPathComponent("logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: logosFolder, withIntermediateDirectories: true)

        // Balance: same accounts as the Home total.
        let accounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let included = accounts.filter(\.includeInTotal)
        let balance = included.reduce(0) { $0 + $1.balance }
        let label: String
        if included.count == accounts.count {
            label = "\(included.count) \(included.count == 1 ? "account" : "accounts")"
        } else if included.isEmpty {
            label = "No accounts selected"
        } else {
            label = included.map(\.shortName).joined(separator: " + ")
        }

        // Budget: same figures as Home.
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        let overall = UserDefaults.standard.double(forKey: BudgetSettings.overallKey)
        let budgetTotal = overall > 0 ? overall : categories.filter { !$0.isIncome }.reduce(0) { $0 + $1.monthlyLimit }
        let monthStart = Date().startOfMonth
        let expense = TransactionKind.expense.rawValue
        let monthExpenses = (try? context.fetch(FetchDescriptor<MoneyTransaction>(
            predicate: #Predicate { $0.date >= monthStart && $0.kindRaw == expense }
        ))) ?? []
        let spent = monthExpenses.reduce(0) { $0 + $1.amount }

        // Upcoming payments in the next 30 days.
        let horizon = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        var payments: [WidgetSnapshot.Payment] = []

        let subscriptions = (try? context.fetch(FetchDescriptor<SubscriptionPlan>(predicate: #Predicate { $0.isActive }))) ?? []
        for subscription in subscriptions {
            let due = subscription.upcomingRenewal()
            guard due <= horizon else { continue }
            let key = "sub-\(subscription.id.uuidString)"
            payments.append(.init(
                id: key,
                title: subscription.name,
                amountText: shortAmount(subscription.amount, currency: subscription.currency),
                dueDate: due,
                colorHex: subscription.colorHex,
                initial: LogoTile.initial(of: subscription.name),
                logoFile: writeLogo(subscription.logoData, key: key, in: logosFolder)
            ))
        }

        let plans = (try? context.fetch(FetchDescriptor<InstallmentPlan>())) ?? []
        for plan in plans {
            guard let next = plan.nextDue, next.dueDate <= horizon else { continue }
            let key = "plan-\(plan.id.uuidString)"
            payments.append(.init(
                id: key,
                title: "\(plan.provider.rawValue) · \(plan.title)",
                amountText: shortAmount(next.amount, currency: .lkr),
                dueDate: next.dueDate,
                colorHex: plan.colorHex,
                initial: LogoTile.initial(of: plan.provider.rawValue),
                logoFile: writeLogo(plan.logoData ?? plan.provider.cachedLogo, key: key, in: logosFolder)
            ))
        }

        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            hideAmounts: UserDefaults.standard.bool(forKey: hideAmountsKey),
            balance: balance,
            balanceLabel: label,
            budgetTotal: budgetTotal,
            spent: spent,
            payments: Array(payments.sorted { $0.dueDate < $1.dueDate }.prefix(6))
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: folder.appendingPathComponent("widget.json"), options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// "Rs. 4,500" or "$2.99": short enough for a widget row.
    private static func shortAmount(_ amount: Double, currency: Currency) -> String {
        if currency == .lkr { return Money.format(amount) }
        return currency.symbol + String(format: "%.2f", amount)
    }

    /// Saves a small copy of a logo for the widget. Widgets can't download images themselves.
    private static func writeLogo(_ data: Data?, key: String, in folder: URL) -> String? {
        guard let data, let image = UIImage(data: data), let small = image.fitted(in: 96).pngData() else { return nil }
        let name = "\(key).png"
        try? small.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }
}

/// One overall monthly spending limit. When set, it's used instead of adding up the category limits.
enum BudgetSettings {
    static let overallKey = "overallMonthlyBudget"
}
