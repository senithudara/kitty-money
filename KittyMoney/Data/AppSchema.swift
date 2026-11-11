import SwiftData

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Account.self,
        MoneyTransaction.self,
        BudgetCategory.self,
        SubscriptionPlan.self,
        InstallmentPlan.self,
        Installment.self,
        SavingsGoal.self,
        SavingsDeposit.self,
        Holding.self
    ]

    /// The one store the app and its Shortcuts action share.
    static let shared: ModelContainer = makeContainer()

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the Kitty Money data store: \(error)")
        }
    }
}
