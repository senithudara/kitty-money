import Foundation

/// Where an SMS came from, worked out from its wording.
enum SMSSource: String {
    case boc = "BOC"
    case combank = "ComBank"
    case peoples = "People's Bank"
    case koko = "Koko"
    case mintpay = "Mintpay"

    /// Words that identify the matching account by its name, short name or SMS sender.
    var accountKeywords: [String] {
        switch self {
        case .boc: return ["BOC", "BANK OF CEYLON"]
        case .combank: return ["COMBANK", "COMMERCIAL"]
        case .peoples: return ["PEOPLE"]
        case .koko, .mintpay: return []
        }
    }
}

/// What a single SMS means for the app.
struct ParsedSMS {
    enum Kind: Equatable {
        case debit
        case credit
        /// A card payment was cancelled or reversed.
        case reversal
        case installmentDue
        case installmentFailed
        /// Extra detail about a transfer whose debit SMS comes separately (People's Bank).
        case transferNote
        case ignored
    }

    var kind: Kind
    var source: SMSSource?
    var amount: Double = 0
    var currencyCode: String = "LKR"
    /// Clean name to show, e.g. "Caravan Fresh".
    var title: String = ""
    /// Merchant or description as written in the SMS, used for matching.
    var merchantRaw: String = ""
    /// Available balance after the transaction, when the bank includes it.
    var balance: Double?
    var date: Date?
    /// Trailing digits of the account or card number.
    var accountDigits: String?
    var dueDate: Date?
    var installmentProvider: InstallmentProvider?
    var note: String = ""

    /// One line describing the result, for the test box in Settings.
    var summary: String {
        let money = Self.formatAmount(amount, code: currencyCode)
        let from = source.map { " · \($0.rawValue)" } ?? ""
        let balanceText = balance.map { " · balance \(Money.format($0, decimals: true))" } ?? ""
        switch kind {
        case .debit: return "Spent \(money) at \(title)\(from)\(balanceText)"
        case .credit: return "Received \(money) · \(title)\(from)\(balanceText)"
        case .reversal: return "Cancelled payment at \(title)\(from)"
        case .installmentDue: return "\(installmentProvider?.rawValue ?? "Installment") of \(money) for \(title) due \(dueDate?.relativeDayLabel.lowercased() ?? "soon")"
        case .installmentFailed: return "\(installmentProvider?.rawValue ?? "Installment") payment failed for \(title)"
        case .transferNote: return title
        case .ignored: return note.isEmpty ? "Not a transaction" : note
        }
    }

    static func formatAmount(_ amount: Double, code: String) -> String {
        if let currency = Currency(rawValue: code) { return Money.format(amount, currency: currency) }
        return "\(code) \(String(format: "%.2f", amount))"
    }
}

/// Reads bank, Koko and Mintpay SMS. Based on real message formats; banks may change them,
/// which is why Settings has a box to test any message.
enum SMSParser {
    static func parse(_ text: String) -> ParsedSMS {
        let message = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = message.lowercased()

        if lower.contains("verification code") || lower.contains("as otp") || lower.contains(" otp ") || lower.contains("logged in to") {
            return ignored("One-time code or login alert, nothing to record")
        }

        if let result = parseBOC(message) { return result }
        if let result = parseComBank(message) { return result }
        if let result = parsePeoples(message) { return result }
        if let result = parseKoko(message) { return result }
        if let result = parseMintpay(message) { return result }
        return ignored("Not a transaction message Kitty Money recognizes")
    }

    // MARK: Bank of Ceylon
    // "CEFT Transfer Debit Rs 1500.00 From A/C No XXXXXXXXXX123. Balance available Rs 8500.00 - Thank you for banking with BOC"
    // "No Book Deposit S/A Rs 20000.00 To A/C No XXXXXXXXXX123. Balance available Rs 28500.00 - ..."

    private static func parseBOC(_ message: String) -> ParsedSMS? {
        guard let match = groups(#"^(.*?)\s+Rs\.?\s*([\d,]+(?:\.\d{1,2})?)\s+(From|To)\s+A/C\s+No\s+[X\*]*(\d+)"#, in: message),
              let amount = number(match[2]) else { return nil }
        let lower = message.lowercased()
        guard lower.contains("boc") || lower.contains("balance available") else { return nil }

        let description = match[1].trimmingCharacters(in: .whitespaces)
        let lowerDescription = description.lowercased()
        var isCredit = match[3].lowercased() == "to"
        if lowerDescription.contains("debit") {
            isCredit = false
        } else if lowerDescription.contains("credit") || lowerDescription.contains("deposit") {
            isCredit = true
        }

        var result = ParsedSMS(kind: isCredit ? .credit : .debit, source: .boc)
        result.amount = amount
        result.accountDigits = match[4]
        result.merchantRaw = description
        result.title = bocTitle(lowerDescription, isCredit: isCredit, original: description)
        if let balance = groups(#"Balance available\s+Rs\.?\s*([\d,]+(?:\.\d{1,2})?)"#, in: message) {
            result.balance = number(balance[1])
        }
        return result
    }

    private static func bocTitle(_ lower: String, isCredit: Bool, original: String) -> String {
        if lower.contains("pos") || lower.contains("atm") { return "Card or ATM payment" }
        if lower.contains("deposit") { return "Cash deposit" }
        if lower.contains("ceft") { return isCredit ? "CEFT transfer in" : "CEFT transfer" }
        if lower.contains("online transfer") { return isCredit ? "Online transfer in" : "Online transfer" }
        if lower.contains("transfer") { return isCredit ? "Transfer in" : "Transfer" }
        let cleaned = original
            .replacingOccurrences(of: #"(?i)\b(debit|credit)\b"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? (isCredit ? "Money in" : "Payment") : cleaned
    }

    // MARK: Commercial Bank
    // "Dear Cardholder, Purchase at SAMPLE CAFE-MAIN STREETCOLOMBO 03 LK for LKR 850.00 on 05/01/26 08:05 PM has been authorised on your debit card ending #1234."
    // "YOUR TRANSACTION AT Sample Store ON YOUR CARD ENDING WITH 1234 HAS BEEN CANCELLED."

    private static func parseComBank(_ message: String) -> ParsedSMS? {
        let lower = message.lowercased()

        if lower.contains("declined") && lower.contains("card") {
            var result = ignored("Card payment was declined, nothing to record")
            result.source = .combank
            return result
        }

        if let match = groups(#"TRANSACTION AT\s+(.+?)\s+ON YOUR CARD ENDING(?: WITH)?\s+#?(\d{4})\s+HAS BEEN CANCELL?ED"#, in: message) {
            var result = ParsedSMS(kind: .reversal, source: .combank)
            result.merchantRaw = match[1]
            result.title = cleanMerchant(match[1])
            result.accountDigits = match[2]
            return result
        }

        guard let match = groups(#"Purchase at\s+(.+?)\s+for\s+([A-Z]{3})\s*([\d,]+(?:\.\d{1,2})?)\s+on\s+(\d{1,2}/\d{1,2}/\d{2,4})\s+(\d{1,2}:\d{2}\s*[AP]M)"#, in: message),
              let amount = number(match[3]) else { return nil }

        var result = ParsedSMS(kind: .debit, source: .combank)
        result.merchantRaw = match[1]
        result.title = cleanMerchant(match[1])
        result.amount = amount
        result.currencyCode = match[2].uppercased()
        result.date = date("\(match[4]) \(match[5])", formats: ["dd/MM/yy hh:mm a", "dd/MM/yyyy hh:mm a", "d/M/yy h:mm a"])
        if let card = groups(#"ending\s+(?:with\s+)?#?(\d{4})"#, in: message) {
            result.accountDigits = card[1]
        }
        return result
    }

    // MARK: People's Bank
    // "Dear Sir/Madam, Your A/C 000-0000****00 has been debited by Rs. 1200.00 (POS @18:30 05/01/2026 at SAMPLE SUPERMARKET-COLOMBO). [Av_Bal: Rs. 9800.00 as of SMS]"
    // "Fund transfer Successful. LKR 5000.00 to Sample Bank PLC - SB Account XXXXXXXX on 2026-01-05 09:00:00."

    private static func parsePeoples(_ message: String) -> ParsedSMS? {
        if let match = groups(#"Fund transfer\s+Successful\.?\s*LKR\s*([\d,]+(?:\.\d{1,2})?)\s+to\s+(.+?)\s+on\s+\d{4}-\d{2}-\d{2}"#, in: message) {
            var result = ParsedSMS(kind: .transferNote, source: .peoples)
            result.amount = number(match[1]) ?? 0
            var destination = match[2]
            for marker in [" PLC", " - ", " Account", " A/C"] {
                if let range = destination.range(of: marker, options: .caseInsensitive) {
                    destination = String(destination[..<range.lowerBound])
                }
            }
            result.title = "Transfer to \(destination.trimmingCharacters(in: .whitespaces))"
            return result
        }

        guard let match = groups(#"has been (debited|credited) by\s+Rs\.?\s*([\d,]+(?:\.\d{1,2})?)\s*\(([^)]*)\)"#, in: message),
              let amount = number(match[2]) else { return nil }

        let isCredit = match[1].lowercased() == "credited"
        var result = ParsedSMS(kind: isCredit ? .credit : .debit, source: .peoples)
        result.amount = amount
        let details = match[3]

        if let account = groups(#"A/C\s+[\d\-]*\**(\d+)"#, in: message) {
            result.accountDigits = account[1]
        }
        if let balance = groups(#"Av_Bal:\s*Rs\.?\s*([\d,]+(?:\.\d{1,2})?)"#, in: message) {
            result.balance = number(balance[1])
        }
        if let when = groups(#"@\s*(\d{1,2}:\d{2})\s+(\d{1,2}/\d{1,2}/\d{4})"#, in: details) {
            result.date = date("\(when[2]) \(when[1])", formats: ["dd/MM/yyyy HH:mm", "d/M/yyyy H:mm"])
        }
        if let merchant = groups(#"\sat\s+(.+)$"#, in: details) {
            result.merchantRaw = merchant[1]
            result.title = cleanMerchant(merchant[1])
        } else {
            let type = details.components(separatedBy: "@").first?.trimmingCharacters(in: .whitespaces) ?? ""
            result.merchantRaw = type
            if type.uppercased().contains("TFR") {
                result.title = isCredit ? "Transfer in" : "Transfer"
            } else if type.isEmpty {
                result.title = isCredit ? "Money in" : "Payment"
            } else {
                result.title = type
            }
        }
        return result
    }

    // MARK: Koko
    // "Hi Alex, Your instalment of 3500.00 for your Sample Store order is due tomorrow."
    // "Hi Alex,instalment payment for your Sample Store order failed to be processed."

    private static func parseKoko(_ message: String) -> ParsedSMS? {
        if let match = groups(#"instalment of\s+(?:Rs\.?\s*|LKR\s*)?([\d,]+(?:\.\d{1,2})?)\s+for your\s+(.+?)\s+order is due\s+(today|tomorrow)"#, in: message),
           let amount = number(match[1]) {
            var result = ParsedSMS(kind: .installmentDue, source: .koko)
            result.installmentProvider = .koko
            result.amount = amount
            result.title = match[2].trimmingCharacters(in: .whitespaces)
            result.dueDate = day(offset: match[3].lowercased() == "tomorrow" ? 1 : 0)
            return result
        }
        if let match = groups(#"instalment payment for your\s+(.+?)\s+order failed"#, in: message) {
            var result = ParsedSMS(kind: .installmentFailed, source: .koko)
            result.installmentProvider = .koko
            result.title = match[1].trimmingCharacters(in: .whitespaces)
            result.dueDate = day(offset: 0)
            return result
        }
        return nil
    }

    // MARK: Mintpay
    // "...our attempt to deduct the second instalment of Rs. 2,500.00 for your previous purchase done from Sample Store is unsuccessful..."

    private static func parseMintpay(_ message: String) -> ParsedSMS? {
        if let match = groups(#"deduct the\s+(\w+)\s+instalment of\s+Rs\.?\s*([\d,]+(?:\.\d{1,2})?)\s+for your previous purchase (?:done )?from\s+(.+?)\s+(?:is|was) unsuccessful"#, in: message) {
            var result = ParsedSMS(kind: .installmentFailed, source: .mintpay)
            result.installmentProvider = .mintpay
            result.amount = number(match[2]) ?? 0
            result.title = match[3].trimmingCharacters(in: .whitespaces)
            result.note = "\(match[1].capitalized) instalment"
            result.dueDate = day(offset: 0)
            return result
        }
        // Reminder wording isn't confirmed yet; this covers the likely form.
        if message.lowercased().contains("mintpay") || message.lowercased().contains("instalment"),
           let match = groups(#"instalment of\s+Rs\.?\s*([\d,]+(?:\.\d{1,2})?).*?(?:from|for)\s+(.+?)\s+(?:is|will be)\s+due\s+(today|tomorrow)"#, in: message),
           let amount = number(match[1]) {
            var result = ParsedSMS(kind: .installmentDue, source: .mintpay)
            result.installmentProvider = .mintpay
            result.amount = amount
            result.title = match[2].trimmingCharacters(in: .whitespaces)
            result.dueDate = day(offset: match[3].lowercased() == "tomorrow" ? 1 : 0)
            return result
        }
        return nil
    }

    // MARK: Helpers

    /// "SAMPLE CAFE-MAIN STREETCOLOMBO 03 LK" → "Sample Cafe", "UBER EATS 852 LK" → "Uber Eats".
    static func cleanMerchant(_ raw: String) -> String {
        var text = raw.uppercased()
        // Phone numbers, e.g. "650-2530000"
        text = text.replacingOccurrences(of: #"\d{3}-\d{4,}"#, with: " ", options: .regularExpression)
        // Cut at location markers
        for marker in ["-", " COLOMBO", "COLOMBO ", " SINGAPORE", " DUBLIN", " LONDON", " KANDY", " GALLE", " NEGOMBO", " NUGEGODA", " DEHIWALA", " BATTARAMULLA"] {
            if let range = text.range(of: marker), range.lowerBound > text.startIndex {
                text = String(text[..<range.lowerBound])
            }
        }
        // Trailing two-letter country codes, then trailing numbers and symbols
        text = text.replacingOccurrences(of: #"(\s+[A-Z]{2})+$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[\s\d&\.,#*]+$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return raw.trimmingCharacters(in: .whitespaces) }
        return text
            .split(separator: " ")
            .map { word in word.count <= 2 ? String(word) : word.lowercased().capitalized }
            .joined(separator: " ")
    }

    static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let nsRange = match.range(at: index)
            guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }

    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ""))
    }

    private static func date(_ text: String, formats: [String]) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.uppercased()) { return date }
        }
        return nil
    }

    private static func day(offset: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: target) ?? target
    }

    private static func ignored(_ note: String) -> ParsedSMS {
        var result = ParsedSMS(kind: .ignored)
        result.note = note
        return result
    }
}
