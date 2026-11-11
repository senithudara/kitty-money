import SwiftUI
import SwiftData

/// Savings goals and CSE investments.
struct WealthView: View {
    enum Segment: String, CaseIterable {
        case savings = "Savings"
        case investments = "Investments"
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query(sort: \Holding.symbol) private var holdings: [Holding]

    @State private var segment: Segment
    @State private var showingNewGoal = false
    @State private var openGoal: SavingsGoal?
    @State private var showingNewHolding = false
    @State private var editingHolding: Holding?
    @State private var isRefreshing = false
    @State private var refreshMessage: String?

    init(initialSegment: Segment = .savings) {
        _segment = State(initialValue: initialSegment)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PillSegments(options: Segment.allCases, selection: $segment) { $0.rawValue }
                switch segment {
                case .savings: savingsSection
                case .investments: investmentsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle("Savings and investments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showingNewGoal) {
            GoalEditorView()
        }
        .sheet(item: $openGoal) { goal in
            GoalDetailView(goal: goal)
        }
        .sheet(isPresented: $showingNewHolding) {
            HoldingEditorView()
        }
        .sheet(item: $editingHolding) { holding in
            HoldingEditorView(holding: holding)
        }
    }

    // MARK: Savings

    private var totalSaved: Double { goals.reduce(0) { $0 + $1.totalSaved } }
    private var savedThisMonth: Double { goals.reduce(0) { $0 + $1.savedThisMonth } }
    private var monthlyPlan: Double { goals.reduce(0) { $0 + $1.monthlyAmount } }

    @ViewBuilder
    private var savingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total saved")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Text(Money.format(totalSaved))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            if monthlyPlan > 0 {
                ProgressBar(value: savedThisMonth / monthlyPlan, height: 8)
                    .padding(.top, 4)
                Text("\(Money.format(savedThisMonth)) of \(Money.format(monthlyPlan)) saved this month")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .card(radius: Theme.radiusLarge, padding: 20)

        if goals.isEmpty {
            Text("Create a goal, like an emergency fund, and log what you put aside each month.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .card()
        }

        VStack(spacing: 10) {
            ForEach(goals) { goal in
                Button {
                    openGoal = goal
                } label: {
                    GoalCard(goal: goal)
                }
                .buttonStyle(.plain)
            }
        }

        dashedButton("+ New savings goal") { showingNewGoal = true }
    }

    // MARK: Investments

    private var portfolioValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    private var portfolioCost: Double { holdings.reduce(0) { $0 + $1.costBasis } }
    private var portfolioGain: Double { portfolioValue - portfolioCost }

    private var lastPriceUpdate: Date? {
        holdings.compactMap(\.priceUpdatedAt).max()
    }

    @ViewBuilder
    private var investmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CSE portfolio value")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    Text(Money.format(portfolioValue))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task { await refreshPrices() }
                } label: {
                    Group {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accentText)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(Theme.cardRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(holdings.isEmpty || isRefreshing)
                .accessibilityLabel("Refresh prices")
            }
            if portfolioCost > 0 {
                Text("\(portfolioGain >= 0 ? "+" : "")\(Money.format(portfolioGain)) (\(percent(portfolioGain / portfolioCost))) on \(Money.format(portfolioCost)) invested")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(portfolioGain >= 0 ? Theme.accentText : Theme.danger)
            }
            Text(refreshMessage ?? lastPriceUpdate.map { "Prices updated \($0.formatted(.relative(presentation: .named)))" } ?? "Tap refresh to load prices from cse.lk")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .card(radius: Theme.radiusLarge, padding: 20)

        if holdings.isEmpty {
            Text("Add the shares you hold on the CSE to see their value and gain or loss.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .card()
        } else {
            VStack(spacing: 0) {
                ForEach(holdings) { holding in
                    Button {
                        editingHolding = holding
                    } label: {
                        holdingRow(holding)
                    }
                    .buttonStyle(.plain)
                    if holding.id != holdings.last?.id {
                        Divider().overlay(Theme.separator)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        }

        dashedButton("+ Add holding") { showingNewHolding = true }
    }

    private func holdingRow(_ holding: Holding) -> some View {
        let ticker = String(holding.symbol.split(separator: ".").first ?? Substring(holding.symbol))
        return ListRow(
            leading: { CategoryTile(mono: String(ticker.prefix(4)), size: 42) },
            title: holding.displayName,
            subtitle: "\(Money.plain(holding.quantity)) × \(holding.lastPrice > 0 ? Money.format(holding.lastPrice, decimals: true) : "no price")",
            amount: Money.format(holding.marketValue),
            caption: holding.costBasis > 0 ? "\(holding.gain >= 0 ? "+" : "")\(percent(holding.gainPercent))" : nil,
            captionColor: holding.gain >= 0 ? Theme.accentText : Theme.danger
        )
    }

    private func refreshPrices() async {
        isRefreshing = true
        refreshMessage = nil
        var updated = 0
        for holding in holdings {
            if let quote = await CSEPrices.quote(for: holding.symbol) {
                holding.lastPrice = quote.price
                holding.priceUpdatedAt = Date()
                if holding.companyName.isEmpty, let name = quote.name { holding.companyName = name }
                updated += 1
            }
        }
        try? context.save()
        isRefreshing = false
        if updated < holdings.count {
            refreshMessage = "Updated \(updated) of \(holdings.count). Edit a holding to enter its price by hand."
        }
    }

    // MARK: Helpers

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func dashedButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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

struct GoalCard: View {
    let goal: SavingsGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LogoTile(name: goal.name, colorHex: goal.colorHex, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(goal.account.map { "In \($0.shortName)" } ?? "No account set")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.format(goal.totalSaved))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if goal.targetAmount > 0 {
                        Text("of \(Money.format(goal.targetAmount))")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if goal.targetAmount > 0 {
                ProgressBar(value: goal.progress, height: 6)
            }
            if goal.monthlyAmount > 0 {
                let done = goal.savedThisMonth >= goal.monthlyAmount
                Text(done
                     ? "This month's \(Money.format(goal.monthlyAmount)) is done"
                     : "\(Money.format(goal.savedThisMonth)) of \(Money.format(goal.monthlyAmount)) this month")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(done ? Theme.accentText : Theme.warning)
            }
        }
        .card(radius: Theme.radiusMedium, padding: 16)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        WealthView()
    }
    .modelContainer(PreviewData.container)
}
