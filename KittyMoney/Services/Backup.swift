import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A complete copy of everything in Kitty Money, saved as one JSON file.
struct BackupFile: Codable {
    var version: Int = 1
    var createdAt: Date = Date()
    var appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    var accounts: [AccountData] = []
    var categories: [CategoryData] = []
    var transactions: [TransactionData] = []
    var subscriptions: [SubscriptionData] = []
    var plans: [PlanData] = []
    var goals: [GoalData] = []
    var holdings: [HoldingData] = []

    struct AccountData: Codable {
        var id: UUID; var name: String; var shortName: String; var last4: String; var kindRaw: String
        var balance: Double; var balanceUpdatedAt: Date?; var colorHex: String; var logoDomain: String?
        var logoData: Data?; var smsSender: String?; var sortOrder: Int; var createdAt: Date; var includeInTotal: Bool
    }

    struct CategoryData: Codable {
        var id: UUID; var name: String; var mono: String; var monthlyLimit: Double; var sortOrder: Int
        var isIncome: Bool; var keywords: [String]
    }

    struct TransactionData: Codable {
        var id: UUID; var amount: Double; var kindRaw: String; var title: String; var note: String; var date: Date
        var sourceRaw: String; var rawMessage: String?; var needsReview: Bool; var categoryGuessed: Bool
        var transferTargetID: UUID?; var installmentID: UUID?; var subscriptionID: UUID?
        var accountID: UUID?; var categoryID: UUID?
        var isSeen: Bool?
    }

    struct SubscriptionData: Codable {
        var id: UUID; var name: String; var amount: Double; var cycleRaw: String; var nextRenewal: Date
        var colorHex: String; var logoDomain: String?; var logoData: Data?; var isActive: Bool; var createdAt: Date
        var currencyCode: String; var autoRecord: Bool; var accountID: UUID?
    }

    struct InstallmentData: Codable {
        var id: UUID; var number: Int; var amount: Double; var dueDate: Date; var paidAt: Date?
    }

    struct PlanData: Codable {
        var id: UUID; var title: String; var providerRaw: String; var totalAmount: Double; var colorHex: String
        var logoData: Data?; var createdAt: Date; var accountID: UUID?; var installments: [InstallmentData]
    }

    struct DepositData: Codable {
        var id: UUID; var amount: Double; var date: Date; var note: String; var transactionID: UUID?
    }

    struct GoalData: Codable {
        var id: UUID; var name: String; var targetAmount: Double; var monthlyAmount: Double; var colorHex: String
        var createdAt: Date; var accountID: UUID?; var deposits: [DepositData]
    }

    struct HoldingData: Codable {
        var id: UUID; var symbol: String; var companyName: String; var quantity: Double; var averageCost: Double
        var lastPrice: Double; var priceUpdatedAt: Date?; var note: String; var createdAt: Date
    }

    var summary: String {
        "\(accounts.count) accounts, \(transactions.count) transactions, \(subscriptions.count) subscriptions, \(plans.count) installment plans, \(goals.count) goals, \(holdings.count) holdings"
    }
}

enum Backup {
    static let lastBackupKey = "lastBackupDate"

    // MARK: Create

    @MainActor
    static func make(from context: ModelContext) -> BackupFile {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        var file = BackupFile()

        file.accounts = all(Account.self).map {
            BackupFile.AccountData(id: $0.id, name: $0.name, shortName: $0.shortName, last4: $0.last4, kindRaw: $0.kindRaw,
                  balance: $0.balance, balanceUpdatedAt: $0.balanceUpdatedAt, colorHex: $0.colorHex, logoDomain: $0.logoDomain,
                  logoData: $0.logoData, smsSender: $0.smsSender, sortOrder: $0.sortOrder, createdAt: $0.createdAt,
                  includeInTotal: $0.includeInTotal)
        }
        file.categories = all(BudgetCategory.self).map {
            BackupFile.CategoryData(id: $0.id, name: $0.name, mono: $0.mono, monthlyLimit: $0.monthlyLimit, sortOrder: $0.sortOrder,
                  isIncome: $0.isIncome, keywords: $0.keywords)
        }
        file.transactions = all(MoneyTransaction.self).map {
            BackupFile.TransactionData(id: $0.id, amount: $0.amount, kindRaw: $0.kindRaw, title: $0.title, note: $0.note, date: $0.date,
                  sourceRaw: $0.sourceRaw, rawMessage: $0.rawMessage, needsReview: $0.needsReview, categoryGuessed: $0.categoryGuessed,
                  transferTargetID: $0.transferTargetID, installmentID: $0.installmentID, subscriptionID: $0.subscriptionID,
                  accountID: $0.account?.id, categoryID: $0.category?.id, isSeen: $0.isSeen)
        }
        file.subscriptions = all(SubscriptionPlan.self).map {
            BackupFile.SubscriptionData(id: $0.id, name: $0.name, amount: $0.amount, cycleRaw: $0.cycleRaw, nextRenewal: $0.nextRenewal,
                  colorHex: $0.colorHex, logoDomain: $0.logoDomain, logoData: $0.logoData, isActive: $0.isActive,
                  createdAt: $0.createdAt, currencyCode: $0.currencyCode, autoRecord: $0.autoRecord, accountID: $0.account?.id)
        }
        file.plans = all(InstallmentPlan.self).map { plan in
            BackupFile.PlanData(id: plan.id, title: plan.title, providerRaw: plan.providerRaw, totalAmount: plan.totalAmount,
                  colorHex: plan.colorHex, logoData: plan.logoData, createdAt: plan.createdAt, accountID: plan.account?.id,
                  installments: plan.installments.map {
                      BackupFile.InstallmentData(id: $0.id, number: $0.number, amount: $0.amount, dueDate: $0.dueDate, paidAt: $0.paidAt)
                  })
        }
        file.goals = all(SavingsGoal.self).map { goal in
            BackupFile.GoalData(id: goal.id, name: goal.name, targetAmount: goal.targetAmount, monthlyAmount: goal.monthlyAmount,
                  colorHex: goal.colorHex, createdAt: goal.createdAt, accountID: goal.account?.id,
                  deposits: goal.deposits.map {
                      BackupFile.DepositData(id: $0.id, amount: $0.amount, date: $0.date, note: $0.note, transactionID: $0.transactionID)
                  })
        }
        file.holdings = all(Holding.self).map {
            BackupFile.HoldingData(id: $0.id, symbol: $0.symbol, companyName: $0.companyName, quantity: $0.quantity, averageCost: $0.averageCost,
                  lastPrice: $0.lastPrice, priceUpdatedAt: $0.priceUpdatedAt, note: $0.note, createdAt: $0.createdAt)
        }
        return file
    }

    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    static var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "KittyMoney-backup-\(formatter.string(from: Date()))"
    }

    // MARK: Restore

    /// Replaces everything in the app with the backup's contents.
    @MainActor
    static func restore(_ file: BackupFile, into context: ModelContext) throws {
        func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
            for item in try context.fetch(FetchDescriptor<T>()) { context.delete(item) }
        }
        try deleteAll(SavingsDeposit.self)
        try deleteAll(SavingsGoal.self)
        try deleteAll(Installment.self)
        try deleteAll(InstallmentPlan.self)
        try deleteAll(MoneyTransaction.self)
        try deleteAll(SubscriptionPlan.self)
        try deleteAll(Holding.self)
        try deleteAll(BudgetCategory.self)
        try deleteAll(Account.self)
        try context.save()

        var accounts: [UUID: Account] = [:]
        for item in file.accounts {
            let account = Account(name: item.name, shortName: item.shortName, last4: item.last4, balance: item.balance,
                                  colorHex: item.colorHex, logoDomain: item.logoDomain, smsSender: item.smsSender, sortOrder: item.sortOrder)
            account.id = item.id
            account.kindRaw = item.kindRaw
            account.balanceUpdatedAt = item.balanceUpdatedAt
            account.logoData = item.logoData
            account.createdAt = item.createdAt
            account.includeInTotal = item.includeInTotal
            context.insert(account)
            accounts[item.id] = account
        }

        var categories: [UUID: BudgetCategory] = [:]
        for item in file.categories {
            let category = BudgetCategory(name: item.name, mono: item.mono, monthlyLimit: item.monthlyLimit,
                                          sortOrder: item.sortOrder, isIncome: item.isIncome, keywords: item.keywords)
            category.id = item.id
            context.insert(category)
            categories[item.id] = category
        }

        for item in file.transactions {
            let transaction = MoneyTransaction(amount: item.amount, kind: .expense, title: item.title, date: item.date, note: item.note)
            transaction.id = item.id
            transaction.kindRaw = item.kindRaw
            transaction.sourceRaw = item.sourceRaw
            transaction.rawMessage = item.rawMessage
            transaction.needsReview = item.needsReview
            transaction.categoryGuessed = item.categoryGuessed
            transaction.transferTargetID = item.transferTargetID
            transaction.installmentID = item.installmentID
            transaction.subscriptionID = item.subscriptionID
            transaction.isSeen = item.isSeen ?? true
            context.insert(transaction)
            transaction.account = item.accountID.flatMap { accounts[$0] }
            transaction.category = item.categoryID.flatMap { categories[$0] }
        }

        for item in file.subscriptions {
            let subscription = SubscriptionPlan(name: item.name, amount: item.amount, nextRenewal: item.nextRenewal,
                                                colorHex: item.colorHex, logoDomain: item.logoDomain)
            subscription.id = item.id
            subscription.cycleRaw = item.cycleRaw
            subscription.logoData = item.logoData
            subscription.isActive = item.isActive
            subscription.createdAt = item.createdAt
            subscription.currencyCode = item.currencyCode
            subscription.autoRecord = item.autoRecord
            context.insert(subscription)
            subscription.account = item.accountID.flatMap { accounts[$0] }
        }

        for item in file.plans {
            let plan = InstallmentPlan(title: item.title, provider: InstallmentProvider(rawValue: item.providerRaw) ?? .other,
                                       totalAmount: item.totalAmount)
            plan.id = item.id
            plan.providerRaw = item.providerRaw
            plan.colorHex = item.colorHex
            plan.logoData = item.logoData ?? plan.logoData
            plan.createdAt = item.createdAt
            context.insert(plan)
            plan.account = item.accountID.flatMap { accounts[$0] }
            for entry in item.installments {
                let installment = Installment(number: entry.number, amount: entry.amount, dueDate: entry.dueDate)
                installment.id = entry.id
                installment.paidAt = entry.paidAt
                context.insert(installment)
                installment.plan = plan
            }
        }

        for item in file.goals {
            let goal = SavingsGoal(name: item.name, targetAmount: item.targetAmount, monthlyAmount: item.monthlyAmount, colorHex: item.colorHex)
            goal.id = item.id
            goal.createdAt = item.createdAt
            context.insert(goal)
            goal.account = item.accountID.flatMap { accounts[$0] }
            for entry in item.deposits {
                let deposit = SavingsDeposit(amount: entry.amount, date: entry.date, note: entry.note)
                deposit.id = entry.id
                deposit.transactionID = entry.transactionID
                context.insert(deposit)
                deposit.goal = goal
            }
        }

        for item in file.holdings {
            let holding = Holding(symbol: item.symbol, companyName: item.companyName, quantity: item.quantity,
                                  averageCost: item.averageCost, lastPrice: item.lastPrice)
            holding.id = item.id
            holding.priceUpdatedAt = item.priceUpdatedAt
            holding.note = item.note
            holding.createdAt = item.createdAt
            context.insert(holding)
        }

        try context.save()
    }
}

/// Wraps backup data for SwiftUI's file exporter.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
