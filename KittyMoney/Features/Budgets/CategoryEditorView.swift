import SwiftUI
import SwiftData

/// Create or edit a budget category: name, label, monthly limit and auto-categorize keywords.
struct CategoryEditorView: View {
    var category: BudgetCategory? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var mono = ""
    @State private var limitText = ""
    @State private var keywordsText = ""
    @State private var isIncome = false
    @State private var didLoad = false
    @State private var confirmDelete = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CategoryTile(mono: displayMono)
                        TextField("Category name", text: $name)
                    }
                    TextField("Two-letter label (optional)", text: $mono)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: mono) { _, newValue in
                            if newValue.count > 2 { mono = String(newValue.prefix(2)) }
                        }
                    if category == nil {
                        Toggle("Income category", isOn: $isIncome)
                    }
                }
                .listRowBackground(Theme.card)

                if !isIncome {
                    Section {
                        HStack {
                            Text("Rs.")
                                .foregroundStyle(Theme.textSecondary)
                            TextField("0", text: $limitText)
                                .keyboardType(.decimalPad)
                        }
                    } header: {
                        Text("Monthly limit")
                    } footer: {
                        Text("Leave at 0 for no limit.")
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    TextField("e.g. KEELLS, CARGILLS", text: $keywordsText, axis: .vertical)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                } header: {
                    Text("Auto-categorize")
                } footer: {
                    Text("Merchant words separated by commas. Transactions whose title or SMS contains one of them land in this category.")
                }
                .listRowBackground(Theme.card)

                if category != nil {
                    Section {
                        Button("Delete category", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(category == nil ? "New category" : "Edit category")
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
            .confirmationDialog("Delete this category?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteCategory() }
            } message: {
                Text("Its transactions are kept and become uncategorized.")
            }
        }
    }

    private var displayMono: String {
        let label = mono.trimmingCharacters(in: .whitespaces)
        if !label.isEmpty { return label.uppercased() }
        let fallback = String(name.trimmingCharacters(in: .whitespaces).prefix(2)).uppercased()
        return fallback.isEmpty ? "··" : fallback
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let category else { return }
        name = category.name
        mono = category.mono
        limitText = category.monthlyLimit > 0 ? Money.plain(category.monthlyLimit) : ""
        keywordsText = category.keywords.joined(separator: ", ")
        isIncome = category.isIncome
    }

    private func save() {
        let target: BudgetCategory
        if let category {
            target = category
        } else {
            let count = (try? context.fetchCount(FetchDescriptor<BudgetCategory>())) ?? 0
            target = BudgetCategory(name: name, mono: displayMono, sortOrder: count, isIncome: isIncome)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.mono = displayMono
        target.monthlyLimit = isIncome ? 0 : (Money.parse(limitText) ?? 0)
        target.keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        try? context.save()
        dismiss()
    }

    private func deleteCategory() {
        guard let category else { return }
        context.delete(category)
        try? context.save()
        dismiss()
    }
}

#Preview {
    CategoryEditorView()
        .modelContainer(PreviewData.container)
}
