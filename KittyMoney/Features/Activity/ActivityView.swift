import SwiftUI
import SwiftData

/// Transactions the app added on its own (from SMS or subscription renewals) that you haven't checked yet.
struct ActivityView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<MoneyTransaction> { $0.isSeen == false }, sort: \MoneyTransaction.date, order: .reverse)
    private var unseen: [MoneyTransaction]

    @State private var editing: MoneyTransaction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if unseen.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Theme.accentText)
                        Text("You're all caught up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("New transactions from bank SMS and subscription renewals show up here until you've checked them.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    Text("Tap one to fix the amount, category or account. Tap the tick if it's right.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ForEach(unseen) { transaction in
                            HStack(spacing: 4) {
                                Button {
                                    editing = transaction
                                } label: {
                                    TransactionRow(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    withAnimation { transaction.isSeen = true }
                                    try? context.save()
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Theme.accentText)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Looks right")
                            }
                            if transaction.id != unseen.last?.id {
                                Divider().overlay(Theme.separator)
                            }
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 6)
                    .padding(.vertical, 4)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle("New activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !unseen.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all as seen") {
                        for transaction in unseen { transaction.isSeen = true }
                        try? context.save()
                    }
                }
            }
        }
        .sheet(item: $editing) { transaction in
            AddTransactionView(editing: transaction)
        }
    }
}

/// Every transaction, newest first, grouped by day, with filters and search.
struct HistoryView: View {
    enum Filter: String, CaseIterable {
        case all = "All"
        case spent = "Spent"
        case received = "Received"
        case transfers = "Transfers"
    }

    private struct DaySection: Identifiable {
        let day: Date
        let items: [MoneyTransaction]
        var id: Date { day }
    }

    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var filter: Filter = .all
    @State private var accountID: UUID?
    @State private var search = ""
    @State private var editing: MoneyTransaction?

    private var filtered: [MoneyTransaction] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return transactions.filter { transaction in
            switch filter {
            case .all: break
            case .spent: if transaction.kind != .expense { return false }
            case .received: if transaction.kind != .income { return false }
            case .transfers: if transaction.kind != .transfer { return false }
            }
            if let accountID {
                let touchesAccount = transaction.account?.id == accountID || transaction.transferTargetID == accountID
                if !touchesAccount { return false }
            }
            if !query.isEmpty {
                let haystack = [transaction.title, transaction.note, transaction.category?.name ?? "", transaction.account?.shortName ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                if !haystack.contains(query) { return false }
            }
            return true
        }
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { DaySection(day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private var totalIn: Double { filtered.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    private var totalOut: Double { filtered.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                PillSegments(options: Filter.allCases, selection: $filter) { $0.rawValue }

                HStack(spacing: 8) {
                    totalTile("Received", totalIn, color: Theme.accentText)
                    totalTile("Spent", totalOut, color: Theme.textPrimary)
                }

                if sections.isEmpty {
                    Text(transactions.isEmpty ? "No transactions yet." : "Nothing matches these filters.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .card()
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(dayTitle(section.day))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(dayNet(section.items))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(section.items) { transaction in
                                Button {
                                    editing = transaction
                                } label: {
                                    TransactionRow(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                                if transaction.id != section.items.last?.id {
                                    Divider().overlay(Theme.separator)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search merchant, note or category")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Account", selection: $accountID) {
                        Text("All accounts").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                } label: {
                    Image(systemName: accountID == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter by account")
            }
        }
        .sheet(item: $editing) { transaction in
            AddTransactionView(editing: transaction)
        }
    }

    private func totalTile(_ label: String, _ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(Money.format(value))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .card(radius: 16, padding: 14)
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if calendar.isDate(day, equalTo: Date(), toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return day.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Money in minus money out for the day, e.g. "- Rs. 7,040".
    private func dayNet(_ items: [MoneyTransaction]) -> String {
        let net = items.reduce(0.0) { total, transaction in
            switch transaction.kind {
            case .income: return total + transaction.amount
            case .expense: return total - transaction.amount
            case .transfer: return total
            }
        }
        if net == 0 { return "" }
        return (net > 0 ? "+ " : "") + Money.format(net)
    }
}
