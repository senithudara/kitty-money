import Foundation

/// Latest share prices from the Colombo Stock Exchange website.
/// This uses the same data endpoint the cse.lk company pages use. It isn't an official API,
/// so it could change without notice; prices can always be entered by hand.
enum CSEPrices {
    struct Quote {
        let symbol: String
        let price: Double
        let name: String?
    }

    /// "jkh" → "JKH.N0000". Symbols that already have a suffix are kept as typed.
    static func normalize(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.contains(".") ? trimmed : trimmed + ".N0000"
    }

    static func quote(for symbol: String) async -> Quote? {
        let code = normalize(symbol)
        guard !code.isEmpty, let url = URL(string: "https://www.cse.lk/api/companyInfoSummery") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code
        request.httpBody = "symbol=\(encoded)".data(using: .utf8)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = json["reqSymbolInfo"] as? [String: Any] else { return nil }
            let price = number(info["lastTradedPrice"]) ?? number(info["closingPrice"]) ?? 0
            guard price > 0 else { return nil }
            return Quote(symbol: code, price: price, name: info["name"] as? String)
        } catch {
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
