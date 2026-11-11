import AppIntents
import SwiftData

/// Shortcuts action "Log Bank SMS". A Message automation passes each bank SMS here,
/// and it's processed without opening the app.
struct LogSMSIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Bank SMS"
    static var description = IntentDescription("Reads a bank, Koko or Mintpay SMS and updates Kitty Money: transactions, balances and installments.")
    static var openAppWhenRun: Bool = false

    /// Optional on purpose: if the automation isn't connected to the SMS, Shortcuts won't pop up a box asking for text.
    @Parameter(
        title: "Message",
        description: "The SMS text. In a Message automation, choose Shortcut Input.",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var message: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(value: "No message received. In the automation, set Message to Shortcut Input.")
        }
        let result = await SMSImporter.importMessage(message, in: AppSchema.shared.mainContext)
        return .result(value: result.message)
    }
}

struct KittyMoneyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSMSIntent(),
            phrases: ["Log a bank SMS in \(.applicationName)"],
            shortTitle: "Log Bank SMS",
            systemImageName: "message"
        )
    }
}
