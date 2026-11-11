import Foundation
import MapKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Works out a category for a merchant the app hasn't seen before.
/// 1. Apple Maps: finds the place and uses its type (restaurant, supermarket, fuel station...).
/// 2. On-device Apple Intelligence (iOS 26, supported iPhones): guesses from the name.
/// Both are free and need no account. The result is saved as a keyword, so each merchant is looked up once.
enum MerchantClassifier {
    @MainActor
    static func classify(_ merchant: String, among categories: [BudgetCategory]) async -> BudgetCategory? {
        let name = merchant.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3 else { return nil }
        let spending = categories.filter { !$0.isIncome && $0.name != "Other" }

        if let fromMaps = await mapsCategoryName(for: name),
           let match = spending.first(where: { $0.name == fromMaps }) {
            return match
        }
        if let fromAI = await aiCategoryName(for: name, options: spending.map(\.name)),
           let match = spending.first(where: { $0.name == fromAI }) {
            return match
        }
        return nil
    }

    // MARK: Apple Maps

    private static let placeTypes: [MKPointOfInterestCategory: String] = [
        .restaurant: "Eating out",
        .cafe: "Eating out",
        .bakery: "Eating out",
        .brewery: "Eating out",
        .winery: "Eating out",
        .nightlife: "Eating out",
        .foodMarket: "Groceries",
        .gasStation: "Transport",
        .evCharger: "Transport",
        .parking: "Transport",
        .publicTransport: "Transport",
        .store: "Shopping"
    ]

    private static func mapsCategoryName(for name: String) async -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest
        // Sri Lanka
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 7.87, longitude: 80.77),
            span: MKCoordinateSpan(latitudeDelta: 4.5, longitudeDelta: 3.5)
        )

        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }

        // Only trust results whose name shares the merchant's first word, so a search
        // for "Warehouse Restaurant" can't return an unrelated nearby place.
        let firstWord = name.lowercased().split(separator: " ").first.map(String.init) ?? ""
        for item in response.mapItems.prefix(5) {
            guard let type = item.pointOfInterestCategory, let category = placeTypes[type] else { continue }
            let itemName = (item.name ?? "").lowercased()
            if firstWord.count < 3 || itemName.contains(firstWord) {
                return category
            }
        }
        return nil
    }

    // MARK: Apple Intelligence

    private static func aiCategoryName(for name: String, options: [String]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let session = LanguageModelSession(
                instructions: "You categorize card payments made in Sri Lanka. Reply with exactly one category name from the list you are given, or the word Unknown if you can't tell. No other text."
            )
            let prompt = "Merchant name from a bank SMS: \"\(name)\". Categories: \(options.joined(separator: ", ")). Which category fits best?"
            guard let response = try? await session.respond(to: prompt) else { return nil }
            let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Longest match first, so "Eating out" wins over a shorter name inside it.
            return options
                .sorted { $0.count > $1.count }
                .first { answer.localizedCaseInsensitiveContains($0) }
        }
        #endif
        return nil
    }
}
