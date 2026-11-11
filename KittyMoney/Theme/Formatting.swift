import Foundation

/// Rupee formatting used across the app.
enum Money {
    private static func formatter(decimals: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter
    }

    private static let whole = formatter(decimals: 0)
    private static let cents = formatter(decimals: 2)

    /// "Rs. 12,400" or, with `decimals: true`, "Rs. 12,400.00".
    static func format(_ value: Double, decimals: Bool = false) -> String {
        let number = NSNumber(value: abs(value))
        let text = (decimals ? cents : whole).string(from: number) ?? "0"
        return (value < 0 ? "- " : "") + "Rs. " + text
    }

    /// Amount in its own currency: "Rs. 1,690" or "USD 20.00".
    static func format(_ value: Double, currency: Currency) -> String {
        guard currency != .lkr else { return format(value) }
        let text = cents.string(from: NSNumber(value: abs(value))) ?? "0"
        return (value < 0 ? "- " : "") + currency.rawValue + " " + text
    }

    /// Plain number for editing in a text field: "1250" or "1250.50".
    static func plain(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    /// Parses what the user typed, ignoring commas. Returns nil for empty or invalid input.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    /// Short form for tight spaces: "Rs. 120.4k".
    static func compact(_ value: Double) -> String {
        guard abs(value) >= 1_000 else { return format(value) }
        let thousands = value / 1_000
        let text = String(format: "%.1f", thousands)
        return "Rs. " + text + "k"
    }
}

extension Date {
    var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.start ?? self
    }

    var endOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.end ?? self
    }

    var shortDayMonth: String {
        formatted(.dateTime.day().month(.abbreviated))
    }

    /// "Today", "Yesterday" or "8 Nov".
    var relativeDayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return shortDayMonth
    }
}
