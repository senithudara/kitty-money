import SwiftUI
import SwiftData

/// Create or edit a savings goal.
struct GoalEditorView: View {
    var goal: SavingsGoal? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var name = ""
    @State private var targetText = ""
    @State private var monthlyText = ""
    @State private var accountID: UUID?
    @State private var colorHex = ColorSwatchPicker.palette[3]
    @State private var didLoad = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal name, e.g. Emergency fund", text: $name)
                    Picker("Saved in", selection: $accountID) {
                        Text("Not set").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    HStack {
                        Text("Monthly")
                        Spacer()
                        Text("Rs.").foregroundStyle(Theme.textSecondary)
                        TextField("10,000", text: $monthlyText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                    HStack {
                        Text("Target")
                        Spacer()
                        Text("Rs.").foregroundStyle(Theme.textSecondary)
                        TextField("Optional", text: $targetText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                } header: {
                    Text("Amounts")
                } footer: {
                    Text("Monthly is what you plan to put aside each month. Leave the target empty if you're just saving steadily.")
                }
                .listRowBackground(Theme.card)

                Section("Color") {
                    ColorSwatchPicker(selection: $colorHex)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(goal == nil ? "New savings goal" : "Edit goal")
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
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let goal else { return }
        name = goal.name
        targetText = goal.targetAmount > 0 ? Money.plain(goal.targetAmount) : ""
        monthlyText = goal.monthlyAmount > 0 ? Money.plain(goal.monthlyAmount) : ""
        accountID = goal.account?.id
        colorHex = goal.colorHex
    }

    private func save() {
        let target: SavingsGoal
        if let goal {
            target = goal
        } else {
            target = SavingsGoal(name: name)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.targetAmount = Money.parse(targetText) ?? 0
        target.monthlyAmount = Money.parse(monthlyText) ?? 0
        target.account = accounts.first { $0.id == accountID }
        target.colorHex = colorHex
        try? context.save()
        dismiss()
    }
}

/// A goal's progress and deposit history.
struct GoalDetailView: View {
    let goal: SavingsGoal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var showingDeposit = false
    @State private var showingEdit = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            LogoTile(name: goal.name, colorHex: goal.colorHex, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Money.format(goal.totalSaved))
                                    .font(.system(size: 22, weight: .bold))
                                Text(goal.targetAmount > 0 ? "of \(Money.format(goal.targetAmount)) target" : "saved so far")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if goal.targetAmount > 0 {
                            ProgressBar(value: goal.progress, height: 8)
                        }
                        if goal.monthlyAmount > 0 {
                            Text("\(Money.format(goal.savedThisMonth)) of \(Money.format(goal.monthlyAmount)) this month")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(goal.savedThisMonth >= goal.monthlyAmount ? Theme.accentText : Theme.warning)
                        }
                    }
                    .padding(.vertical, 6)

                    Button {
                        showingDeposit = true
                    } label: {
                        Label("Log a deposit", systemImage: "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    if goal.deposits.isEmpty {
                        Text("No deposits yet.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(goal.sortedDeposits) { deposit in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deposit.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                if !deposit.note.isEmpty {
                                    Text(deposit.note)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer()
                            Text((deposit.amount >= 0 ? "+ " : "") + Money.format(deposit.amount))
                                .fontWeight(.semibold)
                                .foregroundStyle(deposit.amount >= 0 ? Theme.accentText : Theme.danger)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                deleteDeposit(deposit)
                            }
                        }
                    }
                } header: {
                    Text("History")
                } footer: {
                    if !goal.deposits.isEmpty {
                        Text("Swipe left on a deposit to delete it.")
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Delete goal", role: .destructive) {
                        confirmDelete = true
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(goal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { showingEdit = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingDeposit) {
                DepositEditorView(goal: goal)
            }
            .sheet(isPresented: $showingEdit) {
                GoalEditorView(goal: goal)
            }
            .confirmationDialog("Delete this goal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteGoal() }
            } message: {
                Text("Its deposit history is removed. Any transfers already recorded between your accounts are kept.")
            }
        }
    }

    private func deleteDeposit(_ deposit: SavingsDeposit) {
        if let id = deposit.transactionID {
            let descriptor = FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.id == id })
            if let transaction = try? context.fetch(descriptor).first {
                Ledger.delete(transaction, in: context)
            }
        }
        context.delete(deposit)
        try? context.save()
    }

    private func deleteGoal() {
        let target = goal
        let container = context.container
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            let mainContext = container.mainContext
            mainContext.delete(target)
            try? mainContext.save()
        }
    }
}

/// Log money put into (or taken out of) a savings goal.
struct DepositEditorView: View {
    let goal: SavingsGoal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var isWithdrawal = false
    @State private var amountText = ""
    @State private var date = Date()
    @State private var fromAccountID: UUID?
    @State private var note = ""
    @State private var didLoad = false

    private var amount: Double { Money.parse(amountText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $isWithdrawal) {
                        Text("Deposit").tag(false)
                        Text("Withdrawal").tag(true)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Rs.").foregroundStyle(Theme.textSecondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }
                .listRowBackground(Theme.card)

                Section {
                    Picker(isWithdrawal ? "Moved to" : "Moved from", selection: $fromAccountID) {
                        Text("Don't move money").tag(UUID?.none)
                        ForEach(accounts.filter { $0.id != goal.account?.id }) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                } header: {
                    Text("Account balances")
                } footer: {
                    Text(transferExplanation)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isWithdrawal ? "Withdrawal" : "Deposit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(amount <= 0)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if goal.monthlyAmount > 0 { amountText = Money.plain(goal.monthlyAmount) }
            }
        }
    }

    private var transferExplanation: String {
        let savingsName = goal.account?.shortName ?? "savings"
        if fromAccountID == nil {
            return "Only the goal is updated. Pick an account to also record a transfer \(isWithdrawal ? "from \(savingsName)" : "into \(savingsName)") and update both balances."
        }
        return isWithdrawal
            ? "Records a transfer from \(savingsName) to the selected account."
            : "Records a transfer from the selected account into \(savingsName)."
    }

    private func save() {
        guard amount > 0 else { return }
        let deposit = SavingsDeposit(amount: isWithdrawal ? -amount : amount, date: date, note: note)
        context.insert(deposit)
        deposit.goal = goal

        if let otherID = fromAccountID, let other = accounts.first(where: { $0.id == otherID }) {
            let transaction = MoneyTransaction(
                amount: amount,
                kind: .transfer,
                title: isWithdrawal ? "From savings: \(goal.name)" : "Savings: \(goal.name)",
                date: date,
                note: note
            )
            context.insert(transaction)
            if isWithdrawal {
                transaction.account = goal.account
                transaction.transferTargetID = other.id
            } else {
                transaction.account = other
                transaction.transferTargetID = goal.account?.id
            }
            Ledger.apply(transaction, in: context)
            deposit.transactionID = transaction.id
        }

        try? context.save()
        dismiss()
    }
}
