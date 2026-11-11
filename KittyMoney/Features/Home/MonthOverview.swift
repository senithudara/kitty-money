import SwiftUI
import SwiftData
import Charts

/// Bottom of Home: this month's income and a donut chart of where the money went.
struct MonthOverview: View {
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @Query private var plans: [InstallmentPlan]

    @State private var showingLogIncome = false

    private var monthStart: Date { Date().startOfMonth }
    private var monthEnd: Date { Date().endOfMonth }

    /// "1–30 November"
    private var monthRange: String {
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: monthEnd) ?? monthEnd
        return "1–\(Calendar.current.component(.day, from: lastDay)) \(monthStart.formatted(.dateTime.month(.wide)))"
    }

    /// Everything dated in the current calendar month, from the 1st to the last day.
    private var thisMonth: [MoneyTransaction] {
        transactions.filter { $0.date >= monthStart && $0.date < monthEnd }
    }

    // MARK: Income

    private var incomeBySource: [IncomeSource] {
        var totals: [String: Double] = [:]
        for transaction in thisMonth where transaction.kind == .income {
            totals[transaction.category?.name ?? "Other income", default: 0] += transaction.amount
        }
        return totals.map { IncomeSource(name: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    private var totalIncome: Double {
        incomeBySource.reduce(0) { $0 + $1.amount }
    }

    // MARK: Spending

    private var slices: [SpendingSlice] {
        var totals: [String: Double] = [:]
        // Card payments matched to an installment are counted in the Installments slice instead.
        for transaction in thisMonth where transaction.kind == .expense && transaction.installmentID == nil {
            totals[transaction.category?.name ?? "Uncategorized", default: 0] += transaction.amount
        }
        // Installments marked paid this month count as their own slice.
        let installmentsPaid = plans
            .flatMap { $0.installments }
            .filter { paid in
                guard let paidAt = paid.paidAt else { return false }
                return paidAt >= monthStart && paidAt < monthEnd
            }
            .reduce(0) { $0 + $1.amount }
        if installmentsPaid > 0 {
            totals["Installments", default: 0] += installmentsPaid
        }

        let sorted = totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        var result: [SpendingSlice] = []
        var otherTotal: Double = 0
        var paletteIndex = 0
        for (index, entry) in sorted.enumerated() {
            let isPinned = entry.key == "Subscriptions" || entry.key == "Installments"
            if index < 5 || isPinned {
                let color: Color
                switch entry.key {
                case "Subscriptions": color = SpendingSlice.subscriptionsColor
                case "Installments": color = SpendingSlice.installmentsColor
                default:
                    color = SpendingSlice.palette[paletteIndex % SpendingSlice.palette.count]
                    paletteIndex += 1
                }
                result.append(SpendingSlice(name: entry.key, amount: entry.value, color: color))
            } else {
                otherTotal += entry.value
            }
        }
        if otherTotal > 0 {
            result.append(SpendingSlice(name: "Everything else", amount: otherTotal, color: SpendingSlice.otherColor))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            incomeCard
            spendingCard
        }
        .sheet(isPresented: $showingLogIncome) {
            AddTransactionView(initialKind: .income)
        }
    }

    private var incomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Income in \(monthStart.formatted(.dateTime.month(.wide)))") {
                Button("Log income") { showingLogIncome = true }
                    .foregroundStyle(Theme.accentText)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(Money.format(totalIncome))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(totalIncome > 0 ? Theme.accentText : Theme.textPrimary)
                if incomeBySource.isEmpty {
                    Text("Log salary, freelance work and other income to see it here.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(incomeBySource) { source in
                            HStack {
                                Text(source.name)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(Money.format(source.amount))
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .font(.system(size: 14))
                        }
                    }
                }
            }
            .card()
        }
    }

    private var spendingCard: some View {
        let data = slices
        let total = data.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Where it went") {
                Text(monthRange)
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 18) {
                if data.isEmpty {
                    Text("Your spending breakdown for \(Date().formatted(.dateTime.month(.wide))) will show here.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Chart(data) { slice in
                        SectorMark(
                            angle: .value("Amount", slice.amount),
                            innerRadius: .ratio(0.64),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .foregroundStyle(slice.color)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 200)
                    .overlay {
                        VStack(spacing: 2) {
                            Text("Spent")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                            Text(Money.compact(total))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        ForEach(data) { slice in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 10, height: 10)
                                Text(slice.name)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(Money.format(slice.amount))
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(String(format: "%.0f%%", total > 0 ? slice.amount / total * 100 : 0))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 42, alignment: .trailing)
                            }
                            .font(.system(size: 14))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .card(radius: Theme.radiusMedium, padding: 18)
        }
    }
}

struct IncomeSource: Identifiable {
    let name: String
    let amount: Double

    var id: String { name }
}

struct SpendingSlice: Identifiable {
    let name: String
    let amount: Double
    let color: Color

    var id: String { name }

    static let subscriptionsColor = Color(light: "#4C6FE0", dark: "#7C9CFF")
    static let installmentsColor = Color(light: "#C98A1C", dark: "#F0B44C")
    static let otherColor = Color(light: "#A3A3A8", dark: "#5C5C64")
    static let palette: [Color] = [
        Color(light: "#7FA300", dark: "#C6F432"),
        Color(light: "#D9534A", dark: "#FF7A6B"),
        Color(light: "#1E9A8C", dark: "#4FD1C5"),
        Color(light: "#8A5CD6", dark: "#B58CFF"),
        Color(light: "#C2569B", dark: "#F28DC8")
    ]
}

/// Home card summarizing savings and investments, opening the full screen.
struct WealthSummaryCard: View {
    @Query private var goals: [SavingsGoal]
    @Query private var holdings: [Holding]

    private var totalSaved: Double { goals.reduce(0) { $0 + $1.totalSaved } }
    private var savedThisMonth: Double { goals.reduce(0) { $0 + $1.savedThisMonth } }
    private var monthlyPlan: Double { goals.reduce(0) { $0 + $1.monthlyAmount } }
    private var portfolioValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Savings and investments") {
                NavigationLink("Open") { WealthView() }
                    .foregroundStyle(Theme.accentText)
            }
            HStack(spacing: 8) {
                NavigationLink {
                    WealthView(initialSegment: .savings)
                } label: {
                    tile(
                        label: "Saved",
                        value: Money.compact(totalSaved),
                        detail: monthlyPlan > 0 ? "\(Money.compact(savedThisMonth)) of \(Money.compact(monthlyPlan)) this month" : (goals.isEmpty ? "Set a goal" : "\(goals.count) \(goals.count == 1 ? "goal" : "goals")")
                    )
                }
                .buttonStyle(.plain)
                NavigationLink {
                    WealthView(initialSegment: .investments)
                } label: {
                    tile(
                        label: "CSE portfolio",
                        value: Money.compact(portfolioValue),
                        detail: holdings.isEmpty ? "Add holdings" : "\(holdings.count) \(holdings.count == 1 ? "holding" : "holdings")"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tile(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .card(radius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }
}
