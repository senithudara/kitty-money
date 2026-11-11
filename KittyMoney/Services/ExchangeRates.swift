import Foundation

enum Currency: String, CaseIterable, Codable, Identifiable {
    case lkr = "LKR"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .lkr: return "Rs."
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        }
    }
}

/// Rupees per unit of foreign currency, from free public rate services. Cached on the phone.
enum ExchangeRates {
    private static let ratesKey = "fxRatesToLKR"
    private static let fetchedKey = "fxFetchedAt"

    /// How many rupees one unit of `code` costs, using the last saved rates.
    static func cachedRate(for code: String) -> Double? {
        if code == Currency.lkr.rawValue { return 1 }
        let rates = UserDefaults.standard.dictionary(forKey: ratesKey) as? [String: Double]
        return rates?[code]
    }

    static var fetchedAt: Date? {
        UserDefaults.standard.object(forKey: fetchedKey) as? Date
    }

    /// Fetches new rates when the saved ones are older than `maxAge` seconds.
    @discardableResult
    static func refreshIfNeeded(maxAge: TimeInterval = 6 * 3600) async -> Bool {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge { return true }
        return await refresh()
    }

    @discardableResult
    static func refresh() async -> Bool {
        var rates = await fetchFromOpenER()
        if rates == nil {
            rates = await fetchFromCurrencyAPI()
        }
        guard let rates, !rates.isEmpty else { return false }
        UserDefaults.standard.set(rates, forKey: ratesKey)
        UserDefaults.standard.set(Date(), forKey: fetchedKey)
        return true
    }

    /// open.er-api.com: free, no key. Base LKR gives foreign units per rupee, so invert.
    private static func fetchFromOpenER() async -> [String: Double]? {
        struct Response: Decodable {
            let result: String
            let rates: [String: Double]
        }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/LKR") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard response.result == "success" else { return nil }
            return invert(response.rates)
        } catch {
            return nil
        }
    }

    /// Backup source: fawazahmed0 currency API on jsDelivr. Keys are lowercase.
    private static func fetchFromCurrencyAPI() async -> [String: Double]? {
        guard let url = URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/lkr.json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let table = json["lkr"] as? [String: Any] else { return nil }
            var perRupee: [String: Double] = [:]
            for (key, value) in table {
                if let number = value as? Double {
                    perRupee[key.uppercased()] = number
                } else if let number = value as? NSNumber {
                    perRupee[key.uppercased()] = number.doubleValue
                }
            }
            return invert(perRupee)
        } catch {
            return nil
        }
    }

    private static func invert(_ perRupee: [String: Double]) -> [String: Double]? {
        var result: [String: Double] = [:]
        for currency in Currency.allCases where currency != .lkr {
            if let value = perRupee[currency.rawValue], value > 0 {
                result[currency.rawValue] = 1 / value
            }
        }
        return result.isEmpty ? nil : result
    }
}
