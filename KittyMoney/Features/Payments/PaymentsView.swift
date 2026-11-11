import SwiftUI
import SwiftData

struct PaymentsView: View {
    private enum Segment: String, CaseIterable {
        case subscriptions = "Subscriptions"
        case installments = "Installments"
    }

    @Query(sort: \SubscriptionPlan.name) private var subscriptions: [SubscriptionPlan]
    @Query(sort: \InstallmentPlan.createdAt, order: .reverse) private var plans: [InstallmentPlan]

    @State private var segment: Segment = .subscriptions
    @State private var showingNewSubscription = false
    @State private var showingNewPlan = false
    @State private var editingSubscription: SubscriptionPlan?
    @State private var openPlan: InstallmentPlan?
    @State private var showCompleted = false

    private var activeSubscriptions: [SubscriptionPlan] {
        subscriptions.filter(\.isActive).sorted { $0.upcomingRenewal() < $1.upcomingRenewal() }
    }

    private var pausedSubscriptions: [SubscriptionPlan] {
        subscriptions.filter { !$0.isActive }
    }

    private var activePlans: [InstallmentPlan] {
        plans.filter { !$0.isComplete }.sorted { ($0.nextDue?.dueDate ?? .distantFuture) < ($1.nextDue?.dueDate ?? .distantFuture) }
    }

    private var completedPlans: [InstallmentPlan] {
        plans.filter(\.isComplete)
    }

    private var monthEnd: Date { Date().endOfMonth }

    private var monthName: String { Date().formatted(.dateTime.month(.wide)) }

    /// Payments still to come this calendar month (today to the last day), plus any overdue installments.
    private var dueThisMonth: Double {
        var total: Double = 0
        for subscription in activeSubscriptions {
            // Weekly subscriptions can renew more than once in a month.
            var renewal = subscription.upcomingRenewal()
            var steps = 0
            while renewal < monthEnd && steps < 6 {
                total += subscription.estimatedLKR
                renewal = subscription.cycle.advance(renewal)
                steps += 1
            }
        }
        total += plans.flatMap { $0.installments }
            .filter { !$0.isPaid && $0.dueDate < monthEnd }
            .reduce(0) { $0 + $1.amount }
        return total
    }

    private var owedOnPlans: Double {
        plans.reduce(0) { $0 + $1.remainingAmount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    ScreenTitle(text: "Payments")
                    Spacer()
                    addMenu
                }

                HStack(spacing: 8) {
                    summaryTile(label: "Still due in \(monthName)", value: dueThisMonth)
                    summaryTile(label: "Still owed on plans", value: owedOnPlans)
                }

                PillSegments(options: Segment.allCases, selection: $segment) { $0.rawValue }

                switch segment {
                case .subscriptions: subscriptionsList
                case .installments: plansList
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .sheet(isPresented: $showingNewSubscription) {
            SubscriptionEditorView()
        }
        .sheet(item: $editingSubscription) { subscription in
            SubscriptionEditorView(subscription: subscription)
        }
        .sheet(isPresented: $showingNewPlan) {
            InstallmentPlanEditorView()
        }
        .sheet(item: $openPlan) { plan in
            InstallmentPlanDetailView(plan: plan)
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                showingNewSubscription = true
            } label: {
                Label("New subscription", systemImage: "repeat")
            }
            Button {
                showingNewPlan = true
            } label: {
                Label("New installment plan", systemImage: "square.split.2x1")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: Circle())
        }
        .accessibilityLabel("Add payment")
    }

    private func summaryTile(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(Money.format(value))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .card(radius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: Subscriptions

    @ViewBuilder
    private var subscriptionsList: some View {
        if subscriptions.isEmpty {
            emptyCard(
                title: "No subscriptions yet",
                detail: "Add Netflix, Spotify, iCloud and the rest to get reminded before each renewal.",
                action: "Add subscription"
            ) { showingNewSubscription = true }
        } else {
            VStack(spacing: 0) {
                ForEach(activeSubscriptions) { subscription in
                    subscriptionRow(subscription)
                    if subscription.id != activeSubscriptions.last?.id {
                        Divider().overlay(Theme.separator)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))

            if !pausedSubscriptions.isEmpty {
                FieldLabel("Paused")
                VStack(spacing: 0) {
                    ForEach(pausedSubscriptions) { subscription in
                        subscriptionRow(subscription)
                            .opacity(0.55)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            }
        }
    }

    private func subscriptionRow(_ subscription: SubscriptionPlan) -> some View {
        let renewal = subscription.upcomingRenewal()
        let due = DueLabel(date: renewal)
        return Button {
            editingSubscription = subscription
        } label: {
            ListRow(
                leading: { LogoTile(name: subscription.name, colorHex: subscription.colorHex, logoData: subscription.logoData, size: 42) },
                title: subscription.name,
                subtitle: [subscription.cycle.rawValue, subscription.account?.shortName, subscription.lkrEstimateText].compactMap { $0 }.joined(separator: " · "),
                amount: subscription.displayAmount,
                caption: subscription.isActive ? due.text : "Paused",
                captionColor: subscription.isActive && due.isSoon ? Theme.warning : Theme.textSecondary
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Installments

    @ViewBuilder
    private var plansList: some View {
        if plans.isEmpty {
            emptyCard(
                title: "No installment plans yet",
                detail: "Add a Koko or Mintpay purchase and Kitty Money will remind you before each payment.",
                action: "Add installment plan"
            ) { showingNewPlan = true }
        } else {
            VStack(spacing: 10) {
                ForEach(activePlans) { plan in
                    Button {
                        openPlan = plan
                    } label: {
                        PlanCard(plan: plan)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !completedPlans.isEmpty {
                Button {
                    withAnimation { showCompleted.toggle() }
                } label: {
                    HStack {
                        FieldLabel("Completed (\(completedPlans.count))")
                        Spacer()
                        Image(systemName: showCompleted ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showCompleted {
                    VStack(spacing: 10) {
                        ForEach(completedPlans) { plan in
                            Button {
                                openPlan = plan
                            } label: {
                                PlanCard(plan: plan)
                                    .opacity(0.6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func emptyCard(title: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: perform) {
                Text(action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.onLime)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .card(radius: Theme.radiusMedium, padding: 18)
    }
}

/// "Due today", "In 3 days", "21 Nov" plus whether it's soon enough to highlight.
struct DueLabel {
    let date: Date

    private var daysAway: Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
    }

    var isSoon: Bool { daysAway <= 3 }

    var text: String {
        switch daysAway {
        case ..<0: return "Overdue"
        case 0: return "Due today"
        case 1: return "Tomorrow"
        case 2...7: return "In \(daysAway) days"
        default: return date.shortDayMonth
        }
    }
}

/// Installment plan card with a progress step per installment.
struct PlanCard: View {
    let plan: InstallmentPlan

    var body: some View {
        let installments = plan.sortedInstallments
        let next = plan.nextDue
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LogoTile(name: plan.provider.rawValue, colorHex: plan.colorHex, logoData: plan.logoData, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text([plan.provider.rawValue, plan.account?.shortName].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let next {
                    let due = DueLabel(date: next.dueDate)
                    Text(due.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(due.isSoon ? Theme.warning : Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Text("Paid off")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accentText)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: max(1, installments.count)), spacing: 6) {
                ForEach(installments) { installment in
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule()
                            .fill(color(for: installment, next: next))
                            .frame(height: 6)
                        Text(installment.dueDate.shortDayMonth)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }

            HStack {
                Text("\(Money.format(installments.first?.amount ?? 0)) each")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(plan.isComplete ? "All paid" : "\(Money.format(plan.remainingAmount)) left to pay")
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
            }
            .font(.system(size: 13))
        }
        .card(radius: Theme.radiusMedium, padding: 16)
        .accessibilityElement(children: .combine)
    }

    private func color(for installment: Installment, next: Installment?) -> Color {
        if installment.isPaid { return Theme.lime }
        if installment.id == next?.id { return Theme.warning }
        return Theme.track
    }
}

#Preview {
    PaymentsView()
        .modelContainer(PreviewData.container)
}
