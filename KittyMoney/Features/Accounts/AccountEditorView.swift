import SwiftUI
import SwiftData

/// Create a new account, or edit one when `account` is set.
struct AccountEditorView: View {
    var account: Account? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var shortName = ""
    @State private var last4 = ""
    @State private var kind: AccountKind = .savings
    @State private var balanceText = ""
    @State private var colorHex = ColorSwatchPicker.palette[1]
    @State private var logoDomain = ""
    @State private var logoData: Data?
    @State private var smsSender = ""
    @State private var includeInTotal = true
    @State private var didLoad = false
    @State private var confirmDelete = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Account name, e.g. Commercial Bank", text: $name)
                    TextField("Short name for cards, e.g. ComBank", text: $shortName)
                    Picker("Type", selection: $kind) {
                        ForEach(AccountKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    TextField("Last 4 digits (optional)", text: $last4)
                        .keyboardType(.numberPad)
                    Toggle("Include in total balance", isOn: $includeInTotal)
                        .tint(Theme.lime)
                }
                .listRowBackground(Theme.card)

                Section {
                    HStack {
                        Text("Rs.")
                            .foregroundStyle(Theme.textSecondary)
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Current balance")
                } footer: {
                    Text("Sets the balance directly. Transactions you add adjust it from here, and bank SMS will keep it accurate once SMS tracking is on.")
                }
                .listRowBackground(Theme.card)

                LogoEditor(name: shortName.isEmpty ? name : shortName, colorHex: colorHex, logoData: $logoData, domain: $logoDomain)

                Section("Tile color") {
                    ColorSwatchPicker(selection: $colorHex)
                }
                .listRowBackground(Theme.card)

                Section {
                    TextField("e.g. COMBANK", text: $smsSender)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("SMS sender name")
                } footer: {
                    Text("The name your bank's SMS alerts come from. Used for automatic tracking.")
                }
                .listRowBackground(Theme.card)

                if account != nil {
                    Section {
                        Button("Delete account", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(account == nil ? "New account" : "Edit account")
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
            .confirmationDialog("Delete this account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteAccount() }
            } message: {
                Text("Its transactions are kept, but won't be linked to an account anymore.")
            }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let account else { return }
        name = account.name
        shortName = account.shortName
        last4 = account.last4
        kind = account.kind
        balanceText = Money.plain(account.balance)
        colorHex = account.colorHex
        logoDomain = account.logoDomain ?? ""
        logoData = account.logoData
        smsSender = account.smsSender ?? ""
        includeInTotal = account.includeInTotal
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedShort = shortName.trimmingCharacters(in: .whitespaces)
        let balance = Money.parse(balanceText) ?? 0

        let target: Account
        if let account {
            target = account
        } else {
            let count = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
            target = Account(name: trimmedName, shortName: trimmedShort, sortOrder: count)
            context.insert(target)
            target.balanceUpdatedAt = Date()
        }

        if target.balance != balance {
            target.balance = balance
            target.balanceUpdatedAt = Date()
        }
        target.name = trimmedName
        target.shortName = trimmedShort.isEmpty ? trimmedName : trimmedShort
        target.last4 = String(last4.filter(\.isNumber).suffix(4))
        target.kind = kind
        target.includeInTotal = includeInTotal
        target.colorHex = colorHex
        target.logoData = logoData
        let domain = LogoFetcher.normalize(logoDomain)
        target.logoDomain = domain.isEmpty ? nil : domain
        let sender = smsSender.trimmingCharacters(in: .whitespaces).uppercased()
        target.smsSender = sender.isEmpty ? nil : sender

        try? context.save()
        dismiss()
    }

    private func deleteAccount() {
        guard let account else { return }
        context.delete(account)
        try? context.save()
        dismiss()
    }
}

#Preview {
    AccountEditorView()
        .modelContainer(PreviewData.container)
}
