import SwiftUI
import SwiftData

/// Shows a plan's schedule. Tap an installment to mark it paid or unpaid.
struct InstallmentPlanDetailView: View {
    @Bindable var plan: InstallmentPlan

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        LogoTile(name: plan.provider.rawValue, colorHex: plan.colorHex, logoData: plan.logoData, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.provider.rawValue)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                            Text(plan.isComplete ? "All paid" : "\(Money.format(plan.remainingAmount)) left of \(Money.format(plan.totalAmount))")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("Title", text: $plan.title)
                    Picker("Charged to", selection: accountBinding) {
                        Text("Not set").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    ForEach(plan.sortedInstallments) { installment in
                        Button {
                            installment.paidAt = installment.isPaid ? nil : Date()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: installment.isPaid ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(installment.isPaid ? Theme.accentText : Theme.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Installment \(installment.number)")
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(subtitle(for: installment))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Text(Money.format(installment.amount))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        .accessibilityValue(installment.isPaid ? "Paid" : "Not paid")
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Tap an installment to mark it paid. Once SMS tracking is on, matching card charges will mark them automatically.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Delete plan", role: .destructive) {
                        confirmDelete = true
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(plan.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Delete this plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deletePlan() }
            } message: {
                Text("Its schedule and reminders will be removed.")
            }
        }
    }

    private var accountBinding: Binding<UUID?> {
        Binding(
            get: { plan.account?.id },
            set: { newID in plan.account = accounts.first { $0.id == newID } }
        )
    }

    private func subtitle(for installment: Installment) -> String {
        if let paidAt = installment.paidAt {
            return "Paid \(paidAt.shortDayMonth)"
        }
        return "Due \(installment.dueDate.shortDayMonth)"
    }

    private func finish() {
        try? context.save()
        let container = context.container
        Task { @MainActor in
            await Reminders.refresh(in: container.mainContext)
        }
        dismiss()
    }

    private func deletePlan() {
        // Close the sheet first so nothing on screen reads the plan after it's deleted.
        let target = plan
        let container = context.container
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            let mainContext = container.mainContext
            mainContext.delete(target)
            try? mainContext.save()
            await Reminders.refresh(in: mainContext)
        }
    }
}
