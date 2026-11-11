import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @Query(filter: #Predicate<SubscriptionPlan> { $0.isActive }) private var subscriptions: [SubscriptionPlan]
    @Query private var plans: [InstallmentPlan]

    @Environment(\.modelContext) private var context
    @AppStorage(BudgetSettings.overallKey) private var overallBudget: Double = 0
    @State private var showingLimitPrompt = false
    @State private var limitText = ""
    @State private var monthOffset = 0
    @State private var editingCategory: BudgetCategory?
    @State private var addingCategory = false

    // MARK: Month maths

    private var monthStart: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Date().startOfMonth) ?? Date().startOfMonth
    }

    private var monthEnd: Date { monthStart.endOfMonth }

    private var isCurrentMonth: Bool { monthOffset == 0 }

    private var monthTitle: String {
        if Calendar.current.isDate(monthStart, equalTo: Date(), toGranularity: .year) {
            return monthStart.formatted(.dateTime.month(.wide))
        }
        return monthStart.formatted(.dateTime.month(.abbreviated).year())
    }

    private var expenses: [MoneyTransaction] {
        transactions.filter { $0.kind == .expense && $0.date >= monthStart && $0.date < monthEnd }
    }

    private var spendingCategories: [BudgetCategory] {
        categories.filter { !$0.isIncome }
    }

    private func spent(in category: BudgetCategory) -> Double {
        expenses.filter { $0.category?.id == category.id }.reduce(0) { $0 + $1.amount }
    }

    private var uncategorizedSpent: Double {
        expenses.filter { $0.category == nil && $0.installmentID == nil }.reduce(0) { $0 + $1.amount }
    }

    private var categoryLimitTotal: Double {
        spendingCategories.reduce(0) { $0 + $1.monthlyLimit }
    }

    /// The overall monthly limit if set, otherwise the category limits added up.
    private var totalLimit: Double {
        overallBudget > 0 ? overallBudget : categoryLimitTotal
    }

    private var totalSpent: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    /// Subscription renewals and unpaid installments still due before the month ends.
    private var committed: Double {
        guard isCurrentMonth else { return 0 }
        let renewals = subscriptions
            .filter { $0.upcomingRenewal() < monthEnd }
            .reduce(0) { $0 + $1.estimatedLKR }
        let installments = plans
            .flatMap { $0.installments }
            .filter { !$0.isPaid && $0.dueDate < monthEnd }
            .reduce(0) { $0 + $1.amount }
        return renewals + installments
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    ScreenTitle(text: "Budgets")
                    Spacer()
                    monthSwitcher
                }

                summaryCard

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Categories") {
                        Text("Tap to edit")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    VStack(spacing: 8) {
                        ForEach(spendingCategories) { category in
                            Button {
                                editingCategory = category
                            } label: {
                                categoryCard(category)
                            }
                            .buttonStyle(.plain)
                        }
                        if uncategorizedSpent > 0 {
                            uncategorizedCard
                        }
                    }
                    Button {
                        addingCategory = true
                    } label: {
                        Text("+ New category")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.track, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .sheet(item: $editingCategory) { category in
            CategoryEditorView(category: category)
        }
        .sheet(isPresented: $addingCategory) {
            CategoryEditorView()
        }
        .alert("Monthly spending limit", isPresented: $showingLimitPrompt) {
            TextField("Rs. 90,000", text: $limitText)
                .keyboardType(.numberPad)
            Button("Save") { saveLimit(Money.parse(limitText) ?? 0) }
            if overallBudget > 0 {
                Button("Use category limits instead", role: .destructive) { saveLimit(0) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The most you want to spend this month across everything. This drives the \"left to spend\" figure on Home and the widget.")
        }
    }

    private var monthSwitcher: some View {
        HStack(spacing: 0) {
            Button {
                monthOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Previous month")
            Text(monthTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 76)
            Button {
                monthOffset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 40, height: 40)
            }
            .disabled(monthOffset >= 0)
            .accessibilityLabel("Next month")
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .buttonStyle(.plain)
        .background(Theme.card, in: Capsule())
    }

    @ViewBuilder
    private var summaryCard: some View {
        if totalLimit > 0 {
            let left = totalLimit - totalSpent
            VStack(alignment: .leading, spacing: 12) {
                Text(left >= 0 ? "Left to spend" : "Over budget by")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Text(Money.format(abs(left)))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(left >= 0 ? Theme.accentText : Theme.danger)
                ProgressBar(value: totalSpent / totalLimit, tint: left >= 0 ? Theme.lime : Theme.danger, height: 10)
                HStack {
                    Text("\(Money.format(totalSpent)) spent")
                    Spacer()
                    Text("of \(Money.format(totalLimit))")
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                limitButton(overallBudget > 0 ? "Monthly limit \(Money.format(overallBudget)) · Edit" : "Set one overall monthly limit")
                if committed > 0 {
                    Divider().overlay(Theme.separator)
                    Text("\(Money.format(committed)) is already committed to subscriptions and installments due this month.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(radius: Theme.radiusLarge, padding: 20)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Spent this month")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Text(Money.format(totalSpent))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Set a limit for the whole month, or give categories their own limits below.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                limitButton("Set monthly limit")
                    .padding(.top, 6)
            }
            .card(radius: Theme.radiusLarge, padding: 20)
        }
    }

    private func limitButton(_ title: String) -> some View {
        Button {
            limitText = overallBudget > 0 ? Money.plain(overallBudget) : ""
            showingLimitPrompt = true
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
    }

    private func saveLimit(_ value: Double) {
        overallBudget = value
        WidgetSync.update(from: context)
    }

    private func categoryCard(_ category: BudgetCategory) -> some View {
        let spentAmount = spent(in: category)
        let limit = category.monthlyLimit
        let ratio = limit > 0 ? spentAmount / limit : 0
        let color: Color = limit <= 0 ? Theme.textSecondary : (ratio > 1 ? Theme.danger : (ratio > 0.85 ? Theme.warning : Theme.accentText))
        let barColor: Color = ratio > 1 ? Theme.danger : (ratio > 0.85 ? Theme.warning : Theme.lime)
        let status: String
        if limit <= 0 {
            status = "No limit"
        } else if spentAmount > limit {
            status = "\(Money.format(spentAmount - limit)) over"
        } else {
            status = "\(Money.format(limit - spentAmount)) left"
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CategoryTile(mono: category.mono)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(limit > 0 ? "\(Money.format(spentAmount)) of \(Money.format(limit))" : "\(Money.format(spentAmount)) spent")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            if limit > 0 {
                ProgressBar(value: ratio, tint: barColor, height: 6)
            }
        }
        .card(radius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var uncategorizedCard: some View {
        HStack(spacing: 12) {
            CategoryTile(mono: "··")
            VStack(alignment: .leading, spacing: 2) {
                Text("Uncategorized")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Edit these transactions to give them a category")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(Money.format(uncategorizedSpent))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .card(radius: 18, padding: 14)
    }
}

#Preview {
    BudgetsView()
        .modelContainer(PreviewData.container)
}
