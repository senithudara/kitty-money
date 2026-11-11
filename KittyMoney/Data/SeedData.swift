import Foundation
import SwiftData

/// Creates the starting accounts and categories the first time the app opens.
enum SeedData {
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        guard existing == 0 else { return }

        let accounts = [
            Account(name: "Bank of Ceylon", shortName: "BOC", kind: .savings, colorHex: "#B8860B", logoDomain: "boc.lk", sortOrder: 0),
            Account(name: "Commercial Bank", shortName: "ComBank", kind: .savings, colorHex: "#1E4FA8", logoDomain: "combank.lk", sortOrder: 1),
            Account(name: "People's Bank", shortName: "People's", kind: .current, colorHex: "#A3262B", logoDomain: "peoplesbank.lk", sortOrder: 2)
        ]
        accounts.forEach { context.insert($0) }

        let categories = [
            BudgetCategory(name: "Groceries", mono: "GR", sortOrder: 0, keywords: ["KEELLS", "CARGILLS", "GLOMARK", "ARPICO", "SPAR"]),
            BudgetCategory(name: "Eating out", mono: "EO", sortOrder: 1, keywords: ["UBER *EATS", "UBER EATS", "PICKME FOOD", "PIZZA HUT", "KFC"]),
            BudgetCategory(name: "Transport", mono: "TR", sortOrder: 2, keywords: ["PICKME", "UBER"]),
            BudgetCategory(name: "Subscriptions", mono: "SB", sortOrder: 3, keywords: ["NETFLIX", "SPOTIFY", "APPLE.COM", "YOUTUBE", "ADOBE"]),
            BudgetCategory(name: "Shopping", mono: "SH", sortOrder: 4, keywords: ["DARAZ", "ODEL", "NOLIMIT"]),
            BudgetCategory(name: "Bills and utilities", mono: "UT", sortOrder: 5, keywords: ["DIALOG", "MOBITEL", "SLT", "CEB"]),
            BudgetCategory(name: "Other", mono: "OT", sortOrder: 6)
        ]
        categories.forEach { context.insert($0) }

        try? context.save()
        ensureIncomeCategories(context)
    }

    /// Merchant words for automatic categories. Added once per version, so keywords you remove stay removed.
    private static let keywordsVersion = 1
    private static let defaultKeywords: [String: [String]] = [
        "Groceries": ["KEELLS", "CARGILLS", "FOOD CITY", "GLOMARK", "ARPICO", "SPAR", "LAUGFS SUPER", "SATHOSA"],
        "Eating out": ["UBER EATS", "UBER *EATS", "PICKME FOOD", "PIZZA HUT", "DOMINOS", "KFC", "MCDONALD", "BURGER KING",
                       "CARAVAN FRESH", "JAVA LOUNGE", "BARISTA", "STARBUCKS", "CAFE", "RESTAURANT", "BAKERY", "KITCHEN"],
        "Transport": ["PICKME", "UBER", "CEYPETCO", "LANKA IOC", "FUEL", "FILLING STATION", "PARKING", "HIGHWAY"],
        "Subscriptions": ["NETFLIX", "SPOTIFY", "APPLE.COM", "GOOGLE ONE", "YOUTUBE", "ADOBE", "CLAUDE", "ANTHROPIC",
                          "OPENAI", "CHATGPT", "CANVA", "ICLOUD"],
        "Shopping": ["DARAZ", "ODEL", "NOLIMIT", "KAPRUKA", "FASHION BUG", "COOL PLANET", "ABANS", "SINGER", "SOFTLOGIC"],
        "Bills and utilities": ["DIALOG", "MOBITEL", "SLT", "CEB", "LECO", "WATER BOARD", "HUTCH", "AIRTEL"]
    ]

    static func ensureDefaultKeywords(_ context: ModelContext) {
        let key = "defaultKeywordsVersion"
        guard UserDefaults.standard.integer(forKey: key) < keywordsVersion else { return }
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        for category in categories {
            guard let words = defaultKeywords[category.name] else { continue }
            let existing = Set(category.keywords.map { $0.uppercased() })
            category.keywords += words.filter { !existing.contains($0) }
        }
        try? context.save()
        UserDefaults.standard.set(keywordsVersion, forKey: key)
    }

    /// Makes sure the income categories exist. Also upgrades the old single "Income" category to "Salary".
    static func ensureIncomeCategories(_ context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        let income = all.filter(\.isIncome)

        if let legacy = income.first(where: { $0.name == "Income" }), !income.contains(where: { $0.name == "Salary" }) {
            legacy.name = "Salary"
            legacy.mono = "SA"
            if legacy.keywords.isEmpty { legacy.keywords = ["SALARY"] }
        }

        let existingNames = Set(all.filter(\.isIncome).map(\.name))
        var nextOrder = (all.map(\.sortOrder).max() ?? 0) + 1
        let defaults: [(name: String, mono: String, keywords: [String])] = [
            ("Salary", "SA", ["SALARY"]),
            ("Freelance", "FL", ["FIVERR", "UPWORK", "PAYONEER"]),
            ("Other income", "OI", [])
        ]
        for item in defaults where !existingNames.contains(item.name) {
            context.insert(BudgetCategory(name: item.name, mono: item.mono, sortOrder: nextOrder, isIncome: true, keywords: item.keywords))
            nextOrder += 1
        }
        try? context.save()
    }
}

/// Fake data for SwiftUI previews only. Never touches the real store.
enum PreviewData {
    @MainActor
    static let container: ModelContainer = {
        let container = AppSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        SeedData.seedIfNeeded(context)

        let accounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        func category(_ name: String) -> BudgetCategory? { categories.first { $0.name == name } }

        guard accounts.count == 3 else { return container }
        let boc = accounts[0], combank = accounts[1], peoples = accounts[2]
        boc.balance = 120_400; boc.last4 = "4821"
        combank.balance = 98_100; combank.last4 = "0937"
        peoples.balance = 30_000; peoples.last4 = "5512"

        let limits: [String: Double] = ["Groceries": 25_000, "Eating out": 12_000, "Transport": 10_000, "Subscriptions": 6_000, "Shopping": 20_000, "Bills and utilities": 9_000]
        for (name, limit) in limits { category(name)?.monthlyLimit = limit }

        let day: (Int) -> Date = { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) ?? Date() }
        let samples: [MoneyTransaction] = [
            MoneyTransaction(amount: 6_240, kind: .expense, title: "Keells Super", date: day(0), source: .sms, account: combank, category: category("Groceries")),
            MoneyTransaction(amount: 890, kind: .expense, title: "PickMe", date: day(1), source: .sms, account: peoples, category: category("Transport")),
            MoneyTransaction(amount: 85_000, kind: .income, title: "Salary", date: day(2), source: .sms, account: boc, category: category("Salary")),
            MoneyTransaction(amount: 3_100, kind: .expense, title: "Pizza Hut", date: day(4), source: .manual, account: peoples, category: category("Eating out")),
            MoneyTransaction(amount: 1_690, kind: .expense, title: "Netflix", date: day(5), source: .sms, account: boc, category: category("Subscriptions"))
        ]
        samples.forEach { context.insert($0) }

        let soon = Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date()
        context.insert(SubscriptionPlan(name: "Netflix", amount: 1_690, nextRenewal: soon, colorHex: "#5A1A1E", logoDomain: "netflix.com", account: boc))
        context.insert(SubscriptionPlan(name: "Spotify", amount: 649, nextRenewal: soon.addingTimeInterval(86_400 * 6), colorHex: "#1F4D35", logoDomain: "spotify.com", account: combank))

        let plan = InstallmentPlan(title: "Daraz order", provider: .mintpay, totalAmount: 13_500, account: combank)
        context.insert(plan)
        let firstDue = Calendar.current.date(byAdding: .month, value: -1, to: Date().addingTimeInterval(86_400 * 2)) ?? Date()
        plan.buildSchedule(count: 3, firstDue: firstDue, in: context)
        plan.sortedInstallments.first?.paidAt = firstDue

        try? context.save()
        return container
    }()
}
