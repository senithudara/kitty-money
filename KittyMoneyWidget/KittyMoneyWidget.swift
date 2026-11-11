import WidgetKit
import SwiftUI
import UIKit

// MARK: - Data (written by the app)

/// Same shape as WidgetSnapshot in the app's WidgetSync.swift. Keep the two in sync.
struct WidgetSnapshot: Codable {
    struct Payment: Codable {
        var id: String
        var title: String
        var amountText: String
        var dueDate: Date
        var colorHex: String
        var initial: String
        var logoFile: String?
    }

    var updatedAt: Date
    var hideAmounts: Bool
    var balance: Double
    var balanceLabel: String
    var budgetTotal: Double
    var spent: Double
    var payments: [Payment]

    static let sample = WidgetSnapshot(
        updatedAt: Date(),
        hideAmounts: false,
        balance: 248_500,
        balanceLabel: "3 accounts",
        budgetTotal: 90_000,
        spent: 64_200,
        payments: [
            Payment(id: "1", title: "Mintpay · Daraz", amountText: "Rs. 4,500", dueDate: Date().addingTimeInterval(2 * 86_400), colorHex: "#3A3A42", initial: "M"),
            Payment(id: "2", title: "Netflix", amountText: "Rs. 1,690", dueDate: Date().addingTimeInterval(4 * 86_400), colorHex: "#5A1A1E", initial: "N"),
            Payment(id: "3", title: "iCloud+", amountText: "$2.99", dueDate: Date().addingTimeInterval(12 * 86_400), colorHex: "#2D3A55", initial: "I")
        ]
    )
}

enum SnapshotStore {
    static let appGroupID = "group.com.senithudara.kittymoney.shared"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = folder?.appendingPathComponent("widget.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func logo(_ file: String?) -> UIImage? {
        guard let file, let url = folder?.appendingPathComponent("logos").appendingPathComponent(file) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

// MARK: - Timeline

struct KittyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct KittyProvider: TimelineProvider {
    func placeholder(in context: Context) -> KittyEntry {
        KittyEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (KittyEntry) -> Void) {
        completion(KittyEntry(date: Date(), snapshot: SnapshotStore.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KittyEntry>) -> Void) {
        let snapshot = SnapshotStore.load()
        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        // A second entry just after midnight so "Tomorrow" becomes "Today" on time.
        let entries = [
            KittyEntry(date: now, snapshot: snapshot),
            KittyEntry(date: midnight.addingTimeInterval(60), snapshot: snapshot)
        ]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(3_600))))
    }
}

// MARK: - Widget

struct KittyMoneyWidget: Widget {
    let kind = "KittyMoneyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KittyProvider()) { entry in
            KittyWidgetView(entry: entry)
                .containerBackground(for: .widget) { WTheme.card }
        }
        .configurationDisplayName("Kitty Money")
        .description("Budget left this month, your balance and upcoming payments.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Views

struct KittyWidgetView: View {
    let entry: KittyEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot ?? .sample }
    private var hasData: Bool { entry.snapshot != nil }

    var body: some View {
        if !hasData && family != .accessoryInline && family != .accessoryRectangular {
            Text("Open Kitty Money once to set up this widget.")
                .font(.system(size: 13))
                .foregroundStyle(WTheme.textSecondary)
        } else {
            switch family {
            case .systemSmall:
                SummaryPanel(snapshot: snapshot, date: entry.date, compact: true)
            case .systemMedium:
                HStack(spacing: 14) {
                    SummaryPanel(snapshot: snapshot, date: entry.date, compact: true)
                        .frame(width: 138)
                    Rectangle()
                        .fill(WTheme.separator)
                        .frame(width: 1)
                    PaymentList(snapshot: snapshot, date: entry.date, limit: 3)
                }
            case .systemLarge:
                VStack(alignment: .leading, spacing: 14) {
                    SummaryPanel(snapshot: snapshot, date: entry.date, compact: false)
                    Rectangle()
                        .fill(WTheme.separator)
                        .frame(height: 1)
                    PaymentList(snapshot: snapshot, date: entry.date, limit: 6)
                }
            case .accessoryRectangular:
                LockScreenView(snapshot: snapshot, date: entry.date)
            case .accessoryInline:
                Text(Format.leftLine(snapshot))
            default:
                SummaryPanel(snapshot: snapshot, date: entry.date, compact: true)
            }
        }
    }
}

/// How much is left to spend, made hard to ignore. Balance is kept small at the bottom.
struct SummaryPanel: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let compact: Bool

    var body: some View {
        let budget = BudgetStatus(snapshot: snapshot, date: date)

        VStack(alignment: .leading, spacing: 5) {
            if let budget {
                Text(budget.left >= 0 ? "Left to spend" : "Over budget")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WTheme.textSecondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.amount(abs(budget.left), hidden: snapshot.hideAmounts))
                        .font(.system(size: compact ? 22 : 30, weight: .bold))
                        .foregroundStyle(budget.textColor)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                    if !compact {
                        Text(budget.percentText)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(budget.textColor)
                    }
                }

                // The bar shows what's left, so it shrinks as you spend.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WTheme.track)
                        Capsule()
                            .fill(budget.barColor)
                            .frame(width: max(budget.leftRatio > 0 ? 6 : 0, geometry.size.width * budget.leftRatio))
                    }
                }
                .frame(height: 7)

                if compact {
                    Text(budget.percentText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(budget.textColor)
                }

                Text(budget.dailyText(hidden: snapshot.hideAmounts))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Set a monthly limit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WTheme.textPrimary)
                Text("Open Budgets in Kitty Money to see what's left to spend here.")
                    .font(.system(size: 11))
                    .foregroundStyle(WTheme.textSecondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            Text("Balance \(Format.amount(snapshot.balance, hidden: snapshot.hideAmounts)) · \(snapshot.balanceLabel)")
                .font(.system(size: 10))
                .foregroundStyle(WTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Budget figures for the panel: what's left, how much of it, and a daily allowance.
struct BudgetStatus {
    let left: Double
    let leftRatio: Double
    let daysLeft: Int

    init?(snapshot: WidgetSnapshot, date: Date) {
        guard snapshot.budgetTotal > 0 else { return nil }
        left = snapshot.budgetTotal - snapshot.spent
        leftRatio = min(1, max(0, left / snapshot.budgetTotal))
        let calendar = Calendar.current
        let monthEnd = calendar.dateInterval(of: .month, for: date)?.end ?? date
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: monthEnd).day ?? 1
        daysLeft = max(1, days)
    }

    var percentText: String {
        left < 0 ? "0% left" : "\(Int((leftRatio * 100).rounded()))% left"
    }

    /// Lime while there's plenty, amber under half, red under a fifth or over budget.
    var barColor: Color {
        if left < 0 || leftRatio < 0.2 { return WTheme.danger }
        if leftRatio < 0.5 { return WTheme.warning }
        return WTheme.lime
    }

    var textColor: Color {
        if left < 0 || leftRatio < 0.2 { return WTheme.danger }
        if leftRatio < 0.5 { return WTheme.warning }
        return WTheme.accentText
    }

    func dailyText(hidden: Bool) -> String {
        guard left > 0 else { return "No room left this month" }
        let perDay = Format.amount(left / Double(daysLeft), hidden: hidden)
        return daysLeft == 1 ? "\(perDay) for today" : "\(perDay) a day · \(daysLeft) days"
    }
}

/// Upcoming payments with logos.
struct PaymentList: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let limit: Int

    var body: some View {
        let items = Array(snapshot.payments.prefix(limit))
        VStack(alignment: .leading, spacing: 0) {
            Text("Upcoming")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WTheme.textSecondary)
                .padding(.bottom, 6)
            if items.isEmpty {
                Text("Nothing due in the next 30 days")
                    .font(.system(size: 12))
                    .foregroundStyle(WTheme.textSecondary)
                Spacer(minLength: 0)
            } else {
                ForEach(items, id: \.id) { payment in
                    PaymentRow(payment: payment, date: date, hidden: snapshot.hideAmounts)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PaymentRow: View {
    let payment: WidgetSnapshot.Payment
    let date: Date
    let hidden: Bool

    var body: some View {
        let due = Format.due(payment.dueDate, from: date)
        HStack(spacing: 8) {
            LogoView(payment: payment, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(payment.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WTheme.textPrimary)
                    .lineLimit(1)
                Text(due.text)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(due.soon ? WTheme.warning : WTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(hidden ? "••••" : payment.amountText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct LogoView: View {
    let payment: WidgetSnapshot.Payment
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        if let image = SnapshotStore.logo(payment.logoFile) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(size * 0.12)
                .frame(width: size, height: size)
                .background(Color.white, in: shape)
        } else {
            Text(payment.initial)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color(hex: payment.colorHex), in: shape)
        }
    }
}

struct LockScreenView: View {
    let snapshot: WidgetSnapshot
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.leftLine(snapshot))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let next = snapshot.payments.first {
                let due = Format.due(next.dueDate, from: date)
                Text("\(next.title) · \(snapshot.hideAmounts ? "••••" : next.amountText) · \(due.text)")
                    .font(.system(size: 12))
                    .lineLimit(2)
            } else {
                Text("No payments due soon")
                    .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Formatting and colors

enum Format {
    static func amount(_ value: Double, hidden: Bool) -> String {
        if hidden { return "Rs. ••••" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return "Rs. " + (formatter.string(from: NSNumber(value: value)) ?? "0")
    }

    static func leftLine(_ snapshot: WidgetSnapshot) -> String {
        guard snapshot.budgetTotal > 0 else {
            return "Balance \(amount(snapshot.balance, hidden: snapshot.hideAmounts))"
        }
        let left = snapshot.budgetTotal - snapshot.spent
        guard left >= 0 else { return "\(amount(-left, hidden: snapshot.hideAmounts)) over budget" }
        let percent = Int((left / snapshot.budgetTotal * 100).rounded())
        return "\(amount(left, hidden: snapshot.hideAmounts)) left · \(percent)%"
    }

    static func due(_ dueDate: Date, from date: Date) -> (text: String, soon: Bool) {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: dueDate)).day ?? 0
        switch days {
        case ..<0: return ("Overdue", true)
        case 0: return ("Today", true)
        case 1: return ("Tomorrow", true)
        case 2...3: return ("In \(days) days", true)
        case 4...7: return ("In \(days) days", false)
        default: return (dueDate.formatted(.dateTime.day().month(.abbreviated)), false)
        }
    }
}

enum WTheme {
    static let card = Color(light: "#FFFFFF", dark: "#19191D")
    static let track = Color(light: "#E4E4DF", dark: "#2A2A30")
    static let separator = Color(light: "#E2E2DD", dark: "#2A2A30")
    static let textPrimary = Color(light: "#18181B", dark: "#F2F2F0")
    static let textSecondary = Color(light: "#6B6B70", dark: "#9A9AA0")
    static let lime = Color(hex: "#C6F432")
    static let accentText = Color(light: "#4F6B00", dark: "#C6F432")
    static let warning = Color(light: "#A35F00", dark: "#F0B44C")
    static let danger = Color(light: "#C8372D", dark: "#FF7A6B")
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: String, dark: String) {
        let lightColor = UIColor(hex: light)
        let darkColor = UIColor(hex: dark)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor })
    }
}

extension UIColor {
    convenience init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

#Preview(as: .systemMedium) {
    KittyMoneyWidget()
} timeline: {
    KittyEntry(date: Date(), snapshot: .sample)
}
