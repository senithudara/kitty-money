import Foundation
import SwiftData

struct SMSImportResult {
    let message: String
    let saved: Bool
}

/// Applies a parsed SMS to your data: records transactions, syncs balances,
/// matches subscriptions and installments, and handles cancellations.
enum SMSImporter {
    @MainActor
    static func importMessage(_ text: String, in context: ModelContext) async -> SMSImportResult {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = SMSParser.parse(raw)

        let result: SMSImportResult
        switch parsed.kind {
        case .ignored:
            result = SMSImportResult(message: parsed.summary, saved: false)
        case .transferNote:
            PendingTransferNote.save(parsed.title, source: parsed.source)
            result = SMSImportResult(message: "Noted: \(parsed.title)", saved: false)
        case .debit, .credit:
            result = await record(parsed, raw: raw, in: context)
        case .reversal:
            result = reverse(parsed, in: context)
        case .installmentDue, .installmentFailed:
            result = updateInstallment(parsed, in: context)
        }

        if result.saved {
            try? context.save()
            await Reminders.refresh(in: context)
        }
        return result
    }

    // MARK: Debits and credits

    @MainActor
    private static func record(_ parsed: ParsedSMS, raw: String, in context: ModelContext) async -> SMSImportResult {
        let smsSource = TransactionSource.sms.rawValue
        let smsTransactions = (try? context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.sourceRaw == smsSource }))) ?? []

        // Banks sometimes send the same SMS twice.
        let duplicateWindow: TimeInterval = 7 * 86_400
        if smsTransactions.contains(where: { $0.rawMessage == raw && abs($0.date.timeIntervalSinceNow) < duplicateWindow }) {
            return SMSImportResult(message: "Already recorded this SMS", saved: false)
        }

        let accounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let account = matchAccount(parsed, in: accounts)
        let date = parsed.date ?? Date()

        // Convert foreign currency charges.
        var amount = parsed.amount
        var note = ""
        var foreign = false
        if parsed.currencyCode != Currency.lkr.rawValue {
            foreign = true
            await ExchangeRates.refreshIfNeeded(maxAge: 3 * 3600)
            let original = ParsedSMS.formatAmount(parsed.amount, code: parsed.currencyCode)
            if let rate = ExchangeRates.cachedRate(for: parsed.currencyCode) {
                amount = (parsed.amount * rate * 100).rounded() / 100
                note = "\(original) at Rs. \(String(format: "%.2f", rate)). Edit to match your statement."
            } else {
                note = "Charged \(original). Enter the rupee amount from your statement."
            }
        }

        if parsed.kind == .debit {
            if let matched = matchInstallment(parsed, amount: amount, date: date, account: account, raw: raw, note: note, in: context) {
                applyBalance(parsed, to: account)
                return matched
            }
            if let matched = matchSubscription(parsed, amount: amount, date: date, account: account, raw: raw, note: note, foreign: foreign, in: context) {
                applyBalance(parsed, to: account)
                return matched
            }
        }

        var title = parsed.title
        if parsed.kind == .debit, parsed.merchantRaw.uppercased().contains("TFR"), let pending = PendingTransferNote.take(source: parsed.source) {
            title = pending
        }

        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        let pool = categories.filter { $0.isIncome == (parsed.kind == .credit) }
        var category = Ledger.suggestedCategory(for: parsed.merchantRaw + " " + parsed.title, in: pool)

        // Unknown merchant: look it up (Apple Maps, then on-device AI) and remember the answer.
        var guessed = false
        if category == nil, parsed.kind == .debit, !Ledger.isGenericTitle(parsed.title),
           let found = await MerchantClassifier.classify(parsed.title, among: categories) {
            category = found
            guessed = true
            Ledger.learn(merchant: parsed.title, rawMessage: raw, category: found, allCategories: categories)
        }

        let transaction = MoneyTransaction(
            amount: amount,
            kind: parsed.kind == .credit ? .income : .expense,
            title: title,
            date: date,
            note: note,
            source: .sms
        )
        context.insert(transaction)
        transaction.account = account
        transaction.category = category
        transaction.rawMessage = raw
        transaction.isSeen = false
        transaction.needsReview = foreign || category == nil
        transaction.categoryGuessed = guessed
        Ledger.apply(transaction, in: context)
        applyBalance(parsed, to: account)

        let verb = parsed.kind == .credit ? "Received" : "Spent"
        let where_ = category.map { " · \($0.name)\(guessed ? " (looked up)" : "")" } ?? " · needs a category"
        return SMSImportResult(message: "\(verb) \(Money.format(amount)) · \(title)\(where_)", saved: true)
    }

    /// The SMS balance is the bank's own figure, so it overrides the calculated one.
    private static func applyBalance(_ parsed: ParsedSMS, to account: Account?) {
        guard let account, let balance = parsed.balance else { return }
        account.balance = balance
        account.balanceUpdatedAt = Date()
    }

    static func matchAccount(_ parsed: ParsedSMS, in accounts: [Account]) -> Account? {
        guard let source = parsed.source, !source.accountKeywords.isEmpty else { return nil }
        let candidates = accounts.filter { account in
            let haystack = [account.smsSender ?? "", account.name, account.shortName]
                .joined(separator: " ")
                .uppercased()
                .filter { $0.isLetter || $0 == " " }
            return source.accountKeywords.contains { haystack.contains($0) }
        }
        if candidates.count > 1, let digits = parsed.accountDigits {
            if let exact = candidates.first(where: { !$0.last4.isEmpty && (digits.hasSuffix($0.last4) || $0.last4.hasSuffix(digits)) }) {
                return exact
            }
        }
        return candidates.first
    }

    // MARK: Installments paid by card

    @MainActor
    private static func matchInstallment(_ parsed: ParsedSMS, amount: Double, date: Date, account: Account?, raw: String, note: String, in context: ModelContext) -> SMSImportResult? {
        let merchant = parsed.merchantRaw.uppercased()
        let provider: InstallmentProvider
        if merchant.contains("MINTPAY") {
            provider = .mintpay
        } else if merchant.contains("KOKO") {
            provider = .koko
        } else {
            return nil
        }

        let plans = (try? context.fetch(FetchDescriptor<InstallmentPlan>())) ?? []
        let unpaid = plans
            .filter { $0.provider == provider }
            .flatMap { $0.installments }
            .filter { !$0.isPaid }
        let best = unpaid
            .filter { abs($0.amount - amount) <= max(50, $0.amount * 0.03) }
            .min { abs($0.dueDate.timeIntervalSince(date)) < abs($1.dueDate.timeIntervalSince(date)) }

        let transaction = MoneyTransaction(
            amount: amount,
            kind: .expense,
            title: "\(provider.rawValue) · \(best?.plan?.title ?? "installment")",
            date: date,
            note: note,
            source: .sms
        )
        context.insert(transaction)
        transaction.account = account
        transaction.rawMessage = raw
        transaction.isSeen = false
        transaction.installmentID = best?.id
        transaction.needsReview = best == nil
        Ledger.apply(transaction, in: context)

        if let best {
            best.paidAt = date
            return SMSImportResult(message: "Marked \(provider.rawValue) installment \(best.number) as paid · \(Money.format(amount))", saved: true)
        }
        return SMSImportResult(message: "Recorded \(provider.rawValue) payment of \(Money.format(amount)), but no matching plan was found", saved: true)
    }

    // MARK: Subscriptions paid by card

    @MainActor
    private static func matchSubscription(_ parsed: ParsedSMS, amount: Double, date: Date, account: Account?, raw: String, note: String, foreign: Bool, in context: ModelContext) -> SMSImportResult? {
        let merchant = (parsed.merchantRaw + " " + parsed.title).uppercased()
        let subscriptions = (try? context.fetch(FetchDescriptor<SubscriptionPlan>(predicate: #Predicate { $0.isActive }))) ?? []
        guard let subscription = subscriptions.first(where: { matchKeys(for: $0).contains { merchant.contains($0) } }) else { return nil }

        let window: TimeInterval = 4 * 86_400
        let autoSource = TransactionSource.subscription.rawValue
        let autoRecorded = (try? context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.sourceRaw == autoSource }))) ?? []

        // Replace the estimate the app recorded on renewal day with the bank's figure.
        if let existing = autoRecorded.first(where: { $0.title == subscription.name && abs($0.date.timeIntervalSince(date)) <= window }) {
            Ledger.reverse(existing, in: context)
            existing.amount = amount
            existing.date = date
            existing.source = .sms
            existing.rawMessage = raw
            existing.isSeen = false
            existing.note = note
            existing.needsReview = foreign
            existing.subscriptionID = subscription.id
            if let account { existing.account = account }
            Ledger.apply(existing, in: context)
            return SMSImportResult(message: "Updated \(subscription.name) renewal to \(Money.format(amount))", saved: true)
        }

        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        let transaction = MoneyTransaction(amount: amount, kind: .expense, title: subscription.name, date: date, note: note, source: .sms)
        context.insert(transaction)
        transaction.account = account
        transaction.category = categories.first { $0.name == "Subscriptions" && !$0.isIncome }
        transaction.rawMessage = raw
        transaction.isSeen = false
        transaction.subscriptionID = subscription.id
        transaction.needsReview = foreign
        Ledger.apply(transaction, in: context)

        // The bank charged it, so the app shouldn't record this renewal again.
        if abs(subscription.nextRenewal.timeIntervalSince(date)) <= window {
            subscription.nextRenewal = subscription.cycle.advance(subscription.nextRenewal)
        }
        return SMSImportResult(message: "Recorded \(subscription.name) · \(Money.format(amount))", saved: true)
    }

    /// Text in a card SMS that identifies a subscription, e.g. "NETFLIX", or "APPLE.COM" for iCloud.
    static func matchKeys(for subscription: SubscriptionPlan) -> [String] {
        var keys = [subscription.name.uppercased()]
        if let domain = subscription.logoDomain?.uppercased(), let root = domain.split(separator: ".").first, root.count >= 4 {
            keys.append(String(root))
            if domain.contains("ICLOUD") || domain.contains("APPLE") { keys.append("APPLE.COM") }
            if domain.contains("CLAUDE") { keys.append("ANTHROPIC") }
            if domain.contains("OPENAI") { keys.append("OPENAI") }
        }
        let name = subscription.name.uppercased()
        if name.contains("ICLOUD") || name.contains("APPLE") { keys.append("APPLE.COM") }
        return keys.filter { $0.count >= 3 }
    }

    // MARK: Cancellations

    @MainActor
    private static func reverse(_ parsed: ParsedSMS, in context: ModelContext) -> SMSImportResult {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let account = matchAccount(parsed, in: accounts)
        let smsSource = TransactionSource.sms.rawValue
        let since = Date().addingTimeInterval(-10 * 86_400)
        let candidates = ((try? context.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.sourceRaw == smsSource && $0.date >= since }))) ?? [])
            .filter { account == nil || $0.account?.id == account?.id }
            .filter { transaction in
                let key = parsed.merchantRaw.uppercased()
                return (transaction.rawMessage ?? "").uppercased().contains(key) || transaction.title.uppercased() == parsed.title.uppercased()
            }
            .sorted { $0.date > $1.date }

        guard let match = candidates.first else {
            return SMSImportResult(message: "Cancellation for \(parsed.title), but no matching payment was found", saved: false)
        }
        let title = match.title
        let amount = match.amount
        Ledger.delete(match, in: context)
        return SMSImportResult(message: "Removed cancelled payment · \(title) \(Money.format(amount))", saved: true)
    }

    // MARK: Koko / Mintpay reminders and failures

    @MainActor
    private static func updateInstallment(_ parsed: ParsedSMS, in context: ModelContext) -> SMSImportResult {
        guard let provider = parsed.installmentProvider else {
            return SMSImportResult(message: parsed.summary, saved: false)
        }
        let plans = ((try? context.fetch(FetchDescriptor<InstallmentPlan>())) ?? []).filter { $0.provider == provider }
        let merchantWords = parsed.title.uppercased().split(separator: " ").map(String.init).filter { $0.count >= 3 }

        let plan = plans.first { plan in
            let title = plan.title.uppercased()
            return title.contains(parsed.title.uppercased()) || parsed.title.uppercased().contains(title) || merchantWords.contains { title.contains($0) }
        } ?? plans.first { plan in
            parsed.amount > 0 && plan.installments.contains { !$0.isPaid && abs($0.amount - parsed.amount) <= 1 }
        }

        let dueDate = parsed.dueDate ?? Date()
        let failed = parsed.kind == .installmentFailed

        if let plan {
            let unpaid = plan.sortedInstallments.filter { !$0.isPaid }
            let installment = unpaid.first { parsed.amount > 0 && abs($0.amount - parsed.amount) <= 1 } ?? unpaid.first
            guard let installment else {
                return SMSImportResult(message: "\(plan.title) is already fully paid in the app", saved: false)
            }
            installment.dueDate = dueDate
            if parsed.amount > 0 { installment.amount = parsed.amount }
            let message = failed
                ? "\(provider.rawValue) payment failed for \(plan.title). Installment \(installment.number) is still unpaid"
                : "\(provider.rawValue) installment for \(plan.title) is due \(dueDate.relativeDayLabel.lowercased())"
            return SMSImportResult(message: message, saved: true)
        }

        // No plan yet: create one so the payment shows up and gets reminders.
        let newPlan = InstallmentPlan(title: parsed.title, provider: provider, totalAmount: parsed.amount)
        context.insert(newPlan)
        let installment = Installment(number: 1, amount: parsed.amount, dueDate: dueDate)
        context.insert(installment)
        installment.plan = newPlan
        return SMSImportResult(message: "Added \(provider.rawValue) plan for \(parsed.title). Open it in Payments to fill in the rest of the schedule", saved: true)
    }
}

/// People's Bank sends "Fund transfer Successful ... to Hatton National Bank" just before the debit SMS.
/// This remembers it for a few minutes so the debit gets a useful title.
enum PendingTransferNote {
    private static let titleKey = "pendingTransferTitle"
    private static let sourceKey = "pendingTransferSource"
    private static let dateKey = "pendingTransferDate"

    static func save(_ title: String, source: SMSSource?) {
        let defaults = UserDefaults.standard
        defaults.set(title, forKey: titleKey)
        defaults.set(source?.rawValue, forKey: sourceKey)
        defaults.set(Date(), forKey: dateKey)
    }

    static func take(source: SMSSource?) -> String? {
        let defaults = UserDefaults.standard
        guard let title = defaults.string(forKey: titleKey),
              let date = defaults.object(forKey: dateKey) as? Date,
              Date().timeIntervalSince(date) < 15 * 60,
              defaults.string(forKey: sourceKey) == source?.rawValue else { return nil }
        defaults.removeObject(forKey: titleKey)
        return title
    }
}
