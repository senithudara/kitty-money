import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var selectedTab: AppTab

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(filter: #Predicate<SubscriptionPlan> { $0.isActive }) private var subscriptions: [SubscriptionPlan]
    @Query private var installmentPlans: [InstallmentPlan]
    @State private var editingTransaction: MoneyTransaction?
    @AppStorage("displayName") private var displayName = ""
    @Query(filter: #Predicate<MoneyTransaction> { $0.isSeen == false }) private var unseen: [MoneyTransaction]
    @AppStorage(BudgetSettings.overallKey) private var overallBudget: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    balanceCard
                    accountsSection
                    budgetCard
                    upcomingSection
                    WealthSummaryCard()
                    recentSection
                    MonthOverview()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingTransaction) { transaction in
                AddTransactionView(editing: transaction)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                ScreenTitle(text: "Overview")
            }
            Spacer()
            HStack(spacing: 10) {
                NavigationLink {
                    HistoryView()
                } label: {
                    headerIcon("clock.arrow.circlepath")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("History")

                NavigationLink {
                    ActivityView()
                } label: {
                    headerIcon("bell")
                        .overlay(alignment: .topTrailing) {
                            if !unseen.isEmpty {
                                Text(unseen.count > 99 ? "99+" : "\(unseen.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.onLime)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 20, minHeight: 20)
                                    .background(Theme.lime, in: Capsule())
                                    .offset(x: 4, y: -4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(unseen.isEmpty ? "New activity" : "New activity, \(unseen.count) unchecked")
            }
        }
    }

    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 44, height: 44)
            .background(Theme.card, in: Circle())
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        default: base = "Good evening"
        }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? base : "\(base), \(name)"
    }

    // MARK: Balance

    private var includedAccounts: [Account] {
        accounts.filter(\.includeInTotal)
    }

    private var totalBalance: Double {
        includedAccounts.reduce(0) { $0 + $1.balance }
    }

    /// "Total balance · 3 accounts", "BOC · 1 account" or "BOC + People's · 2 accounts".
    private var balanceLabel: String {
        let included = includedAccounts
        if included.isEmpty { return "No accounts selected" }
        let count = "\(included.count) \(included.count == 1 ? "account" : "accounts")"
        if included.count == accounts.count { return "Total balance · \(count)" }
        let names = included.map(\.shortName).joined(separator: " + ")
        return "\(names) · \(count)"
    }

    private var thisMonth: [MoneyTransaction] {
        let start = Date().startOfMonth
        return transactions.filter { $0.date >= start }
    }

    private var moneyIn: Double {
        thisMonth.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
    }

    private var moneyOut: Double {
        thisMonth.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(balanceLabel)
                .font(.system(size: 14, weight: .medium))
                .opacity(0.75)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(Money.format(totalBalance, decimals: true))
                .font(.system(size: 34, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 8) {
                balanceChip("In \(Money.format(moneyIn))")
                balanceChip("Out \(Money.format(moneyOut))")
            }
            .padding(.top, 6)
        }
        .foregroundStyle(Theme.onLime)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lime, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .contextMenu {
            Section("Include in total") {
                ForEach(accounts) { account in
                    Toggle(account.name, isOn: Binding(
                        get: { account.includeInTotal },
                        set: { account.includeInTotal = $0 }
                    ))
                }
            }
        }
        .accessibilityHint("Touch and hold to choose which accounts are included")
    }

    private func balanceChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.onLime.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Accounts") {
                NavigationLink("See all") { AccountsView() }
                    .foregroundStyle(Theme.accentText)
            }
            if accounts.isEmpty {
                Text("No accounts yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .card()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(accounts) { account in
                        NavigationLink {
                            AccountsView(initialSelection: account.id)
                        } label: {
                            accountTile(account)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func accountTile(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LogoTile(name: account.shortName, colorHex: account.colorHex, logoData: account.logoData, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.shortName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text(Money.compact(account.balance))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .card(radius: 16, padding: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Budget

    private var budgetTotal: Double {
        overallBudget > 0 ? overallBudget : categories.filter { !$0.isIncome }.reduce(0) { $0 + $1.monthlyLimit }
    }

    private var daysLeftInMonth: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let days = Calendar.current.dateComponents([.day], from: today, to: Date().endOfMonth).day ?? 0
        return max(0, days)
    }

    @ViewBuilder
    private var budgetCard: some View {
        Button {
            selectedTab = .budgets
        } label: {
            if budgetTotal > 0 {
                let left = budgetTotal - moneyOut
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(Date().formatted(.dateTime.month(.wide))) budget")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(daysLeftInMonth) days left")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ProgressBar(value: moneyOut / budgetTotal, tint: left < 0 ? Theme.danger : Theme.lime)
                    HStack {
                        Text("\(Money.format(moneyOut)) spent")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(left >= 0 ? "\(Money.format(left)) left" : "\(Money.format(-left)) over")
                            .fontWeight(.semibold)
                            .foregroundStyle(left >= 0 ? Theme.accentText : Theme.danger)
                    }
                    .font(.system(size: 14))
                }
                .card()
            } else {
                HStack(spacing: 12) {
                    CategoryTile(mono: "+")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set your monthly budgets")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Add limits per category to see what's left.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .card()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Upcoming

    private var upcoming: [UpcomingPayment] {
        let horizon = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let fromSubscriptions = subscriptions.map { subscription in
            UpcomingPayment(
                id: "sub-\(subscription.id)",
                title: subscription.name,
                subtitle: [subscription.cycle.rawValue, subscription.account?.shortName].compactMap { $0 }.joined(separator: " · "),
                amount: subscription.estimatedLKR,
                amountText: subscription.currency == .lkr ? Money.format(subscription.amount) : subscription.displayAmount,
                dueDate: subscription.upcomingRenewal(),
                colorHex: subscription.colorHex,
                logoData: subscription.logoData
            )
        }
        let fromPlans: [UpcomingPayment] = installmentPlans.compactMap { plan in
            guard let next = plan.nextDue else { return nil }
            return UpcomingPayment(
                id: "inst-\(next.id)",
                title: "\(plan.provider.rawValue) · \(plan.title)",
                subtitle: "Installment \(next.number) of \(plan.installments.count)" + (plan.account.map { " · \($0.shortName)" } ?? ""),
                amount: next.amount,
                amountText: Money.format(next.amount),
                dueDate: next.dueDate,
                colorHex: plan.colorHex,
                logoData: plan.logoData
            )
        }
        return (fromSubscriptions + fromPlans)
            .filter { $0.dueDate <= horizon }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Upcoming") {
                Button("All payments") { selectedTab = .payments }
                    .foregroundStyle(Theme.accentText)
            }
            let items = Array(upcoming.prefix(3))
            if items.isEmpty {
                Text("Nothing due in the next 30 days.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        ListRow(
                            leading: { LogoTile(name: item.title, colorHex: item.colorHex, logoData: item.logoData, size: 40) },
                            title: item.title,
                            subtitle: item.subtitle,
                            amount: item.amountText,
                            caption: item.dueLabel,
                            captionColor: item.isSoon ? Theme.warning : Theme.textSecondary
                        )
                        if item.id != items.last?.id {
                            Divider().overlay(Theme.separator)
                        }
                    }
                }
                .modifier(InnerPadding())
            }
        }
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent")
            let items = Array(transactions.prefix(5))
            if items.isEmpty {
                Text("No transactions yet. Tap + to add one.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { transaction in
                        Button {
                            editingTransaction = transaction
                        } label: {
                            TransactionRow(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                        if transaction.id != items.last?.id {
                            Divider().overlay(Theme.separator)
                        }
                    }
                }
                .modifier(InnerPadding())
            }
        }
    }
}

/// Card with horizontal inner padding for lists of rows.
private struct InnerPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
    }
}

struct UpcomingPayment: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    /// Rupee amount (converted for foreign subscriptions).
    let amount: Double
    /// What's shown in the list, in the payment's own currency.
    let amountText: String
    let dueDate: Date
    let colorHex: String
    let logoData: Data?

    private var daysAway: Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: dueDate)).day ?? 0
    }

    var isSoon: Bool { daysAway <= 3 }

    var dueLabel: String {
        switch daysAway {
        case ..<0: return "Overdue"
        case 0: return "Due today"
        case 1: return "Tomorrow"
        case 2...7: return "In \(daysAway) days"
        default: return dueDate.shortDayMonth
        }
    }
}

struct TransactionRow: View {
    let transaction: MoneyTransaction

    var body: some View {
        ListRow(
            leading: { CategoryTile(mono: transaction.category?.mono ?? "··", size: 40) },
            title: transaction.title,
            subtitle: subtitle,
            amount: amountText,
            amountColor: transaction.kind == .income ? Theme.accentText : (transaction.kind == .transfer ? Theme.textSecondary : Theme.textPrimary),
            caption: reviewCaption,
            captionColor: transaction.needsReview ? Theme.warning : Theme.textSecondary
        )
    }

    private var subtitle: String {
        [transaction.category?.name, transaction.account?.shortName, transaction.date.relativeDayLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var reviewCaption: String? {
        guard transaction.needsReview else {
            return transaction.categoryGuessed ? "Auto" : nil
        }
        if transaction.category == nil && transaction.kind != .transfer && transaction.installmentID == nil {
            return "Needs category"
        }
        return "Check amount"
    }

    private var amountText: String {
        switch transaction.kind {
        case .income: return "+ " + Money.format(transaction.amount)
        case .expense: return "- " + Money.format(transaction.amount)
        case .transfer: return Money.format(transaction.amount)
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewData.container)
}
