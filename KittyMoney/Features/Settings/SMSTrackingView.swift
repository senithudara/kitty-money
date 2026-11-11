import SwiftUI
import SwiftData

/// Setup steps for the Shortcuts automations, a box to test any SMS, and recent imports.
struct SMSTrackingView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<MoneyTransaction> { $0.sourceRaw == "sms" }, sort: \MoneyTransaction.date, order: .reverse)
    private var smsTransactions: [MoneyTransaction]

    @State private var testText = ""
    @State private var preview: String?
    @State private var importResult: String?
    @State private var editingTransaction: MoneyTransaction?
    @FocusState private var editorFocused: Bool

    private struct Automation: Identifiable {
        let phrase: String
        let covers: String
        var id: String { phrase }
    }

    private let automations: [Automation] = [
        Automation(phrase: "A/C", covers: "BOC and People's Bank debits, credits and balances"),
        Automation(phrase: "card ending", covers: "ComBank card purchases and cancellations"),
        Automation(phrase: "instalment", covers: "Koko and Mintpay reminders and failed payments"),
        Automation(phrase: "Fund transfer", covers: "Optional: names People's Bank transfers, e.g. \"Transfer to Hatton National Bank\"")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("iPhone apps can't read your SMS directly, so a Shortcuts automation hands each bank message to Kitty Money. It runs in the background and everything stays on your phone.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                stepsCard
                automationsCard
                testCard
                recentSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("SMS tracking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editorFocused = false }
            }
        }
        .sheet(item: $editingTransaction) { transaction in
            AddTransactionView(editing: transaction)
        }
    }

    // MARK: Setup

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Set up one automation for each phrase below")
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Open Shortcuts, go to Automation and tap +.")
                step(2, "Choose Message. Set Message Contains to the phrase, e.g. A/C.")
                step(3, "Select Run Immediately, then tap Next.")
                step(4, "Add the Log Bank SMS action from Kitty Money.")
                step(5, "Tap Message in the action and choose Shortcut Input. Done.")
            }
            .card()
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.onLime)
                .frame(width: 24, height: 24)
                .background(Theme.lime, in: Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var automationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Phrases")
            VStack(spacing: 0) {
                ForEach(automations) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text(item.phrase)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accentText)
                            .frame(width: 112, alignment: .leading)
                        Text(item.covers)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    if item.phrase != automations.last?.phrase {
                        Divider().overlay(Theme.separator)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            Text("Other messages that happen to contain these phrases are safely ignored. OTPs and login alerts are never recorded.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Test

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Test a message")
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if testText.isEmpty {
                        Text("Paste an SMS here to see how it's read")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $testText)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 96)
                        .focused($editorFocused)
                }
                .padding(8)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 8) {
                    Button {
                        editorFocused = false
                        importResult = nil
                        preview = SMSParser.parse(testText).summary
                    } label: {
                        Text("Preview")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        editorFocused = false
                        Task {
                            let result = await SMSImporter.importMessage(testText, in: context)
                            preview = nil
                            importResult = result.message
                            if result.saved { testText = "" }
                        }
                    } label: {
                        Text("Import")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.onLime)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.lime, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let text = importResult ?? preview {
                    Text(text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(importResult != nil ? Theme.accentText : Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            Text("Use Import for older messages too, e.g. to bring in this month's SMS before the automations were set up.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldLabel("Recently imported")
            if smsTransactions.isEmpty {
                Text("Nothing imported yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .card()
            } else {
                let items = Array(smsTransactions.prefix(15))
                VStack(spacing: 0) {
                    ForEach(items) { transaction in
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
        SMSTrackingView()
    }
    .modelContainer(PreviewData.container)
}
