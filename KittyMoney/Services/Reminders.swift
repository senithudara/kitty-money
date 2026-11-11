import Foundation
import SwiftData
import UserNotifications

/// Keys and defaults for reminder settings (shared with SettingsView's @AppStorage).
enum ReminderSettings {
    static let leadDaysKey = "reminderLeadDays"
    static let hourKey = "reminderHour"
    static let minuteKey = "reminderMinute"
    static let lowBalanceKey = "lowBalanceWarnings"

    static let defaultLeadDays = 3
    static let defaultHour = 9
    static let defaultMinute = 0

    static var leadDays: Int { UserDefaults.standard.object(forKey: leadDaysKey) as? Int ?? defaultLeadDays }
    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? defaultHour }
    static var minute: Int { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? defaultMinute }
    static var lowBalance: Bool { UserDefaults.standard.object(forKey: lowBalanceKey) as? Bool ?? true }
}

/// Schedules local notifications for subscription renewals and installments.
/// iOS allows 64 pending notifications, so only the next 30 days are scheduled,
/// and the schedule is rebuilt whenever the app opens or payment data changes.
enum Reminders {
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus == .authorized
        }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @MainActor
    static func refresh(in context: ModelContext) async {
        // Every data change ends up here, so it's also where the widget is kept current.
        WidgetSync.update(from: context)

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        let now = Date()
        let horizon = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        var events: [Event] = []

        let subscriptions = (try? context.fetch(FetchDescriptor<SubscriptionPlan>(predicate: #Predicate { $0.isActive }))) ?? []
        for subscription in subscriptions {
            let due = subscription.upcomingRenewal(onOrAfter: now)
            guard due <= horizon else { continue }
            events.append(Event(
                id: "sub-\(subscription.id.uuidString)",
                title: "\(subscription.name) renewal",
                amountText: subscription.currency == .lkr
                    ? Money.format(subscription.amount)
                    : subscription.displayAmount + (subscription.lkrEstimateText.map { " (\($0))" } ?? ""),
                amount: subscription.estimatedLKR,
                dueDate: due,
                accountName: subscription.account?.shortName,
                balance: subscription.account?.balance
            ))
        }

        let plans = (try? context.fetch(FetchDescriptor<InstallmentPlan>())) ?? []
        for plan in plans {
            for installment in plan.installments where !installment.isPaid && installment.dueDate <= horizon {
                events.append(Event(
                    id: "inst-\(installment.id.uuidString)",
                    title: "\(plan.provider.rawValue) installment",
                    amountText: Money.format(installment.amount),
                    amount: installment.amount,
                    dueDate: installment.dueDate,
                    accountName: plan.account?.shortName,
                    balance: plan.account?.balance
                ))
            }
        }

        let leadDays = ReminderSettings.leadDays
        var requests: [(Date, UNNotificationRequest)] = []
        for event in events {
            for daysBefore in Set([leadDays, 0]).sorted(by: >) {
                guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: event.dueDate)),
                      let fireDate = calendar.date(bySettingHour: ReminderSettings.hour, minute: ReminderSettings.minute, second: 0, of: day),
                      fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                switch daysBefore {
                case 0: content.title = "\(event.title) due today"
                case 1: content.title = "\(event.title) due tomorrow"
                default: content.title = "\(event.title) due in \(daysBefore) days"
                }
                var body = event.amountText
                if let name = event.accountName { body += " from \(name)" }
                if ReminderSettings.lowBalance, event.amount > 0, let balance = event.balance, balance < event.amount {
                    body += ". Heads up: \(event.accountName ?? "the account") only has \(Money.format(balance))."
                }
                content.body = body
                content.sound = .default

                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: "\(event.id)-\(daysBefore)d", content: content, trigger: trigger)
                requests.append((fireDate, request))
            }
        }

        center.removeAllPendingNotificationRequests()
        for (_, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(60) {
            try? await center.add(request)
        }
    }

    private struct Event {
        let id: String
        let title: String
        let amountText: String
        /// Rupee amount, used for the low balance check.
        let amount: Double
        let dueDate: Date
        let accountName: String?
        let balance: Double?
    }
}
