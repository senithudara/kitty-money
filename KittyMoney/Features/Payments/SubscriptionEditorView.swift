import SwiftUI
import SwiftData

/// Create or edit a subscription.
struct SubscriptionEditorView: View {
    var subscription: SubscriptionPlan? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var name = ""
    @State private var amountText = ""
    @State private var cycle: BillingCycle = .monthly
    @State private var nextRenewal = Date()
    @State private var accountID: UUID?
    @State private var isActive = true
    @State private var colorHex = ColorSwatchPicker.palette[4]
    @State private var logoDomain = ""
    @State private var logoData: Data?
    @State private var currency: Currency = .lkr
    @State private var autoRecord = true
    /// True until the user picks or removes a logo themselves; while true, the logo follows the name.
    @State private var autoLogo = true
    /// Rupees per unit of the selected currency, shown as a live conversion.
    @State private var rate: Double?
    @State private var didLoad = false
    @State private var confirmDelete = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Money.parse(amountText) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Netflix", text: $name)
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text(currency.symbol)
                            .foregroundStyle(Theme.textSecondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                    Picker("Billed", selection: $cycle) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.rawValue).tag(cycle)
                        }
                    }
                    DatePicker("Next renewal", selection: $nextRenewal, displayedComponents: .date)
                    Picker("Charged to", selection: $accountID) {
                        Text("Not set").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                    if subscription != nil {
                        Toggle("Active", isOn: $isActive)
                            .tint(Theme.lime)
                    }
                } footer: {
                    if let conversionText {
                        Text(conversionText)
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Toggle("Add a transaction on renewal day", isOn: $autoRecord)
                        .tint(Theme.lime)
                } footer: {
                    Text(currency == .lkr
                         ? "Records the payment as an expense from the selected account each time it renews."
                         : "On renewal day the \(currency.rawValue) amount is converted at that day's rate and recorded as an expense. It's marked \"Check amount\" so you can match it to what your bank actually charged.")
                }
                .listRowBackground(Theme.card)

                LogoEditor(name: name, colorHex: colorHex, logoData: $logoData, domain: $logoDomain) {
                    autoLogo = false
                }

                Section("Tile color") {
                    ColorSwatchPicker(selection: $colorHex)
                }
                .listRowBackground(Theme.card)

                if subscription != nil {
                    Section {
                        Button("Delete subscription", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(subscription == nil ? "New subscription" : "Edit subscription")
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
            .task(id: currency) {
                await loadRate()
            }
            .task(id: name) {
                await autoFetchLogo()
            }
            .confirmationDialog("Delete this subscription?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteSubscription() }
            } message: {
                Text("Its reminders will stop. Past transactions are kept.")
            }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let subscription {
            name = subscription.name
            amountText = Money.plain(subscription.amount)
            cycle = subscription.cycle
            nextRenewal = subscription.upcomingRenewal()
            accountID = subscription.account?.id
            isActive = subscription.isActive
            colorHex = subscription.colorHex
            logoDomain = subscription.logoDomain ?? ""
            logoData = subscription.logoData
            currency = subscription.currency
            autoRecord = subscription.autoRecord
            autoLogo = subscription.logoData == nil
        } else {
            accountID = accounts.first?.id
        }
    }

    private func save() {
        guard let amount = Money.parse(amountText) else { return }
        let target: SubscriptionPlan
        if let subscription {
            target = subscription
        } else {
            target = SubscriptionPlan(name: name, amount: amount, nextRenewal: nextRenewal)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.amount = amount
        target.cycle = cycle
        target.currency = currency
        target.autoRecord = autoRecord
        target.nextRenewal = nextRenewal
        target.account = accounts.first { $0.id == accountID }
        target.isActive = isActive
        target.colorHex = colorHex
        target.logoData = logoData
        let domain = LogoFetcher.normalize(logoDomain)
        target.logoDomain = domain.isEmpty ? nil : domain
        try? context.save()

        let needsLogo = target.logoData == nil && target.logoDomain != nil
        let container = context.container
        Task { @MainActor in
            if needsLogo { await LogoSync.fillMissing(in: container.mainContext) }
            await RenewalProcessor.run(in: container.mainContext)
            await Reminders.refresh(in: container.mainContext)
        }
        dismiss()
    }

    /// "≈ Rs. 6,020 at today's rate" for foreign amounts.
    private var conversionText: String? {
        guard currency != .lkr else { return nil }
        guard let rate else {
            return "Fetching today's \(currency.rawValue) rate…"
        }
        let base = "1 \(currency.rawValue) = Rs. \(String(format: "%.2f", rate))"
        guard let amount = Money.parse(amountText), amount > 0 else { return base }
        return "≈ \(Money.format(amount * rate)) today (\(base))"
    }

    private func loadRate() async {
        rate = ExchangeRates.cachedRate(for: currency.rawValue)
        guard currency != .lkr else { return }
        await ExchangeRates.refreshIfNeeded()
        rate = ExchangeRates.cachedRate(for: currency.rawValue)
    }

    /// While the user hasn't chosen a logo, fetch one that matches the name (after a short pause in typing).
    private func autoFetchLogo() async {
        guard autoLogo else { return }
        let typed = name.trimmingCharacters(in: .whitespaces)
        guard typed.count >= 3 else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled, autoLogo else { return }
        if let found = await LogoFetcher.fetch(forName: typed), !Task.isCancelled, autoLogo {
            logoData = found.data
            logoDomain = found.domain
        }
    }

    private func deleteSubscription() {
        guard let subscription else { return }
        context.delete(subscription)
        try? context.save()
        let container = context.container
        Task { @MainActor in
            await Reminders.refresh(in: container.mainContext)
        }
        dismiss()
    }
}

#Preview {
    SubscriptionEditorView()
        .modelContainer(PreviewData.container)
}
