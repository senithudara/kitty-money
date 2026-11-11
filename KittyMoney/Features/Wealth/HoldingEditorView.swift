import SwiftUI
import SwiftData

/// Add or edit a CSE holding, and record buys or sells.
struct HoldingEditorView: View {
    var holding: Holding? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var symbol = ""
    @State private var companyName = ""
    @State private var quantityText = ""
    @State private var averageCostText = ""
    @State private var priceText = ""
    @State private var note = ""
    @State private var isFetching = false
    @State private var fetchFailed = false
    @State private var didLoad = false
    @State private var confirmDelete = false

    // Trade recording (existing holdings only)
    @State private var isSell = false
    @State private var tradeQuantityText = ""
    @State private var tradePriceText = ""

    private var canSave: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty && (Money.parse(quantityText) ?? 0) >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Symbol, e.g. JKH or JKH.N0000", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Company name (optional)", text: $companyName)
                    numberRow("Shares", text: $quantityText, placeholder: "0")
                    numberRow("Average cost", text: $averageCostText, placeholder: "Rs. per share")
                }
                .listRowBackground(Theme.card)

                Section {
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("Rs. per share", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                        Button {
                            Task { await fetchPrice() }
                        } label: {
                            if isFetching { ProgressView() } else { Text("Fetch") }
                        }
                        .buttonStyle(.borderless)
                        .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
                    }
                } header: {
                    Text("Market price")
                } footer: {
                    Text(fetchFailed
                         ? "Couldn't get a price from cse.lk. Check the symbol, or type the price in."
                         : "Fetch gets the last traded price from cse.lk, or type it in.")
                }
                .listRowBackground(Theme.card)

                if holding != nil {
                    Section {
                        Picker("Trade", selection: $isSell) {
                            Text("Bought").tag(false)
                            Text("Sold").tag(true)
                        }
                        .pickerStyle(.segmented)
                        numberRow("Shares", text: $tradeQuantityText, placeholder: "0")
                        if !isSell {
                            numberRow("Price", text: $tradePriceText, placeholder: "Rs. per share")
                        }
                        Button(isSell ? "Record sale" : "Record purchase") { recordTrade() }
                            .disabled(!canRecordTrade)
                    } header: {
                        Text("Record a trade")
                    } footer: {
                        Text("Buying updates your share count and average cost. Selling reduces your share count.")
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
                .listRowBackground(Theme.card)

                if holding != nil {
                    Section {
                        Button("Delete holding", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(holding == nil ? "Add holding" : "Edit holding")
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
            .confirmationDialog("Delete this holding?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteHolding() }
            }
        }
    }

    private func numberRow(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
        }
    }

    private var canRecordTrade: Bool {
        guard let quantity = Money.parse(tradeQuantityText), quantity > 0 else { return false }
        if isSell { return true }
        return (Money.parse(tradePriceText) ?? 0) > 0
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let holding else { return }
        symbol = holding.symbol
        companyName = holding.companyName
        quantityText = Money.plain(holding.quantity)
        averageCostText = Money.plain(holding.averageCost)
        priceText = holding.lastPrice > 0 ? Money.plain(holding.lastPrice) : ""
        note = holding.note
    }

    private func fetchPrice() async {
        isFetching = true
        fetchFailed = false
        let quote = await CSEPrices.quote(for: symbol)
        isFetching = false
        if let quote {
            symbol = quote.symbol
            priceText = Money.plain(quote.price)
            if companyName.trimmingCharacters(in: .whitespaces).isEmpty, let name = quote.name {
                companyName = name
            }
        } else {
            fetchFailed = true
        }
    }

    /// Applies a buy or sell to the numbers in the form (saved with Save).
    private func recordTrade() {
        guard let tradeQuantity = Money.parse(tradeQuantityText), tradeQuantity > 0 else { return }
        let quantity = Money.parse(quantityText) ?? 0
        let averageCost = Money.parse(averageCostText) ?? 0
        if isSell {
            quantityText = Money.plain(max(0, quantity - tradeQuantity))
        } else {
            let price = Money.parse(tradePriceText) ?? 0
            let newQuantity = quantity + tradeQuantity
            let newAverage = newQuantity > 0 ? (quantity * averageCost + tradeQuantity * price) / newQuantity : 0
            quantityText = Money.plain(newQuantity)
            averageCostText = Money.plain((newAverage * 100).rounded() / 100)
        }
        tradeQuantityText = ""
        tradePriceText = ""
    }

    private func save() {
        let code = CSEPrices.normalize(symbol)
        let quantity = Money.parse(quantityText) ?? 0
        let averageCost = Money.parse(averageCostText) ?? 0
        let price = Money.parse(priceText) ?? 0

        let target: Holding
        if let holding {
            target = holding
        } else {
            target = Holding(symbol: code, quantity: quantity, averageCost: averageCost)
            context.insert(target)
        }
        target.symbol = code
        target.companyName = companyName.trimmingCharacters(in: .whitespaces)
        target.quantity = quantity
        target.averageCost = averageCost
        if price != target.lastPrice {
            target.lastPrice = price
            target.priceUpdatedAt = price > 0 ? Date() : nil
        }
        target.note = note
        try? context.save()
        dismiss()
    }

    private func deleteHolding() {
        guard let holding else { return }
        context.delete(holding)
        try? context.save()
        dismiss()
    }
}

#Preview {
    HoldingEditorView()
        .modelContainer(PreviewData.container)
}
