import SwiftUI
import SwiftData

/// Create a new Koko / Mintpay installment plan and its payment schedule.
struct InstallmentPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var title = ""
    @State private var provider: InstallmentProvider = .mintpay
    @State private var totalText = ""
    @State private var count = 3
    @State private var alreadyPaid = 0
    @State private var firstDue = Date()
    @State private var monthsBetween = 1
    @State private var accountID: UUID?
    @State private var didLoad = false

    private var total: Double { Money.parse(totalText) ?? 0 }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && total > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $provider) {
                        ForEach(InstallmentProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("What did you buy? e.g. Daraz order", text: $title)
                    HStack {
                        Text("Rs.")
                            .foregroundStyle(Theme.textSecondary)
                        TextField("Total amount", text: $totalText)
                            .keyboardType(.decimalPad)
                    }
                    Picker("Charged to", selection: $accountID) {
                        Text("Not set").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Stepper("\(count) installments", value: $count, in: 2...12)
                    Stepper(monthsBetween == 1 ? "Every month" : "Every \(monthsBetween) months", value: $monthsBetween, in: 1...3)
                    DatePicker("First payment", selection: $firstDue, displayedComponents: .date)
                    Stepper("\(alreadyPaid) already paid", value: $alreadyPaid, in: 0...(count - 1))
                } header: {
                    Text("Schedule")
                } footer: {
                    if total > 0 {
                        Text("\(count) payments of about \(Money.format(total / Double(count))). If the first one was charged at checkout, set its date to the purchase day and mark 1 as already paid.")
                    } else {
                        Text("If the first payment was charged at checkout, set its date to the purchase day and mark 1 as already paid.")
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New installment plan")
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
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                accountID = accounts.first?.id
            }
            .onChange(of: count) { _, newCount in
                if alreadyPaid > newCount - 1 { alreadyPaid = newCount - 1 }
            }
        }
    }

    private func save() {
        let plan = InstallmentPlan(title: title.trimmingCharacters(in: .whitespaces), provider: provider, totalAmount: total)
        context.insert(plan)
        plan.account = accounts.first { $0.id == accountID }
        plan.buildSchedule(count: count, firstDue: firstDue, monthsBetween: monthsBetween, in: context)
        for installment in plan.sortedInstallments.prefix(alreadyPaid) {
            installment.paidAt = installment.dueDate
        }
        try? context.save()

        let container = context.container
        Task { @MainActor in
            await LogoSync.fillMissing(in: container.mainContext)
            await Reminders.refresh(in: container.mainContext)
        }
        dismiss()
    }
}

#Preview {
    InstallmentPlanEditorView()
        .modelContainer(PreviewData.container)
}
