import SwiftUI
import SwiftData

struct AccountsView: View {
    var initialSelection: UUID? = nil

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var selectedID: UUID?
    @State private var showingNewAccount = false
    @State private var editingAccount: Account?
    @State private var editingTransaction: MoneyTransaction?

    private var currentID: UUID? { selectedID ?? initialSelection ?? accounts.first?.id }
    private var selectedAccount: Account? { accounts.first { $0.id == currentID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 10) {
                    ForEach(accounts) { account in
                        accountCard(account, isSelected: account.id == currentID)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedID = account.id }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { selectedID = account.id }
                    }
                }

                if let account = selectedAccount {
                    transactionsSection(for: account)
                }

                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(Theme.lime).frame(width: 8, height: 8).padding(.top, 6)
                    Text("Tap the pencil to set a balance, logo or SMS sender. Balances will update from bank SMS once tracking is set up.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card(radius: 16, padding: 14)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewAccount = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add account")
            }
        }
        .sheet(isPresented: $showingNewAccount) {
            AccountEditorView()
        }
        .sheet(item: $editingAccount) { account in
            AccountEditorView(account: account)
        }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(editing: transaction)
        }
    }

    private func accountCard(_ account: Account, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LogoTile(name: account.shortName, colorHex: account.colorHex, logoData: account.logoData, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(account.last4.isEmpty ? account.kind.rawValue : "\(account.kind.rawValue) · •••• \(account.last4)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    editingAccount = account
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(account.name)")
            }
            HStack(alignment: .lastTextBaseline) {
                Text(Money.format(account.balance, decimals: true))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Spacer()
                Text(updatedLabel(account))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .strokeBorder(isSelected ? Theme.accentText : Color.clear, lineWidth: 1.5)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func updatedLabel(_ account: Account) -> String {
        guard let date = account.balanceUpdatedAt else { return "Not updated yet" }
        return "Updated \(date.relativeDayLabel.lowercased())"
    }

    private func transactionsSection(for account: Account) -> some View {
        let items = account.transactions.sorted { $0.date > $1.date }.prefix(30)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "\(account.shortName) transactions")
            if items.isEmpty {
                Text("No transactions for this account yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items)) { transaction in
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
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            }
        }
    }
}

#Preview {
    NavigationStack {
        AccountsView()
    }
    .modelContainer(PreviewData.container)
}
