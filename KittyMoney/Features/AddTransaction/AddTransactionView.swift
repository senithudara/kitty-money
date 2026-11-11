import SwiftUI
import SwiftData

/// Add a new transaction, or edit one when `editing` is set.
struct AddTransactionView: View {
    var editing: MoneyTransaction? = nil
    /// Starting type for a new transaction, e.g. `.income` from "Log income".
    var initialKind: TransactionKind = .expense

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]

    private enum Field { case amount, title, note }

    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var targetID: UUID?
    @State private var categoryID: UUID?
    @State private var title = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var didLoad = false
    @State private var userPickedCategory = false
    @State private var originalCategoryID: UUID?
    @State private var confirmDelete = false
    @FocusState private var focused: Field?

    private var amount: Double? { Money.parse(amountText) }

    private var visibleCategories: [BudgetCategory] {
        categories.filter { $0.isIncome == (kind == .income) }
    }

    private var canSave: Bool {
        guard let amount, amount > 0, accountID != nil else { return false }
        if kind == .transfer {
            return targetID != nil && targetID != accountID
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PillSegments(options: TransactionKind.allCases, selection: $kind) { $0.rawValue }
                    amountField
                    titleField

                    VStack(alignment: .leading, spacing: 10) {
                        FieldLabel(kind == .transfer ? "From account" : "Account")
                        AccountChips(accounts: accounts, selection: $accountID)
                    }

                    if kind == .transfer {
                        VStack(alignment: .leading, spacing: 10) {
                            FieldLabel("To account")
                            AccountChips(accounts: accounts, selection: $targetID, excluded: accountID)
                        }
                    } else {
                        categoryGrid
                    }

                    detailsCard

                    if editing != nil {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text("Delete transaction")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(editing == nil ? "New transaction" : "Edit transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            .onAppear(perform: load)
            .onChange(of: title) { _, newValue in
                autoCategorize(newValue)
            }
            .onChange(of: kind) { _, _ in
                if !visibleCategories.contains(where: { $0.id == categoryID }) {
                    categoryID = nil
                    userPickedCategory = false
                }
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteTransaction() }
            } message: {
                Text("The account balance will be adjusted back.")
            }
        }
    }

    // MARK: Sections

    private var amountField: some View {
        VStack(spacing: 6) {
            FieldLabel("Amount")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Rs.")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 80, maxWidth: 230)
                    .focused($focused, equals: .amount)
                    .accessibilityLabel("Amount in rupees")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Title")
            TextField(kind == .transfer ? "e.g. Savings top-up" : "e.g. Keells Super", text: $title)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused, equals: .title)
                .submitLabel(.done)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Category")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(visibleCategories) { category in
                    let isSelected = category.id == categoryID
                    Button {
                        categoryID = category.id
                        userPickedCategory = true
                    } label: {
                        Text(category.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(isSelected ? Theme.onLime : Theme.textPrimary)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isSelected ? Theme.lime : Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            DatePicker("Date", selection: $date)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            Divider().overlay(Theme.separator).padding(.leading, 16)
            HStack {
                Text("Note")
                TextField("Optional", text: $note)
                    .multilineTextAlignment(.trailing)
                    .focused($focused, equals: .note)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
        .font(.system(size: 15))
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let transaction = editing {
            kind = transaction.kind
            amountText = Money.plain(transaction.amount)
            accountID = transaction.account?.id
            targetID = transaction.transferTargetID
            categoryID = transaction.category?.id
            originalCategoryID = transaction.category?.id
            title = transaction.title
            date = transaction.date
            note = transaction.note
            userPickedCategory = true
        } else {
            kind = initialKind
            accountID = accounts.first?.id
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                focused = .amount
            }
        }
    }

    private func autoCategorize(_ text: String) {
        guard !userPickedCategory, kind != .transfer else { return }
        if let match = Ledger.suggestedCategory(for: text, in: visibleCategories) {
            categoryID = match.id
        }
    }

    private func save() {
        guard canSave, let amount else { return }
        let account = accounts.first { $0.id == accountID }
        let category = kind == .transfer ? nil : categories.first { $0.id == categoryID }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let finalTitle: String
        if !trimmed.isEmpty {
            finalTitle = trimmed
        } else if kind == .transfer {
            let targetName = accounts.first { $0.id == targetID }?.shortName ?? "account"
            finalTitle = "Transfer to \(targetName)"
        } else {
            finalTitle = category?.name ?? kind.rawValue
        }

        let transaction: MoneyTransaction
        if let existing = editing {
            Ledger.reverse(existing, in: context)
            transaction = existing
            transaction.amount = amount
            transaction.kind = kind
            transaction.title = finalTitle
            transaction.date = date
            transaction.note = note
            transaction.needsReview = false
            transaction.categoryGuessed = false
        } else {
            transaction = MoneyTransaction(amount: amount, kind: kind, title: finalTitle, date: date, note: note, source: .manual)
            context.insert(transaction)
        }
        transaction.account = account
        transaction.category = category
        transaction.isSeen = true
        transaction.transferTargetID = kind == .transfer ? targetID : nil
        Ledger.apply(transaction, in: context)

        // Teach auto-categorize when an SMS transaction's category is set or changed.
        if editing != nil, transaction.source == .sms || transaction.source == .email,
           let category, category.id != originalCategoryID {
            Ledger.learn(merchant: finalTitle, rawMessage: transaction.rawMessage, category: category, allCategories: categories)
        }

        try? context.save()
        dismiss()
    }

    private func deleteTransaction() {
        guard let editing else { return }
        Ledger.delete(editing, in: context)
        dismiss()
    }
}

#Preview {
    AddTransactionView()
        .modelContainer(PreviewData.container)
}
