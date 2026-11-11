import Foundation
import SwiftData

/// Shares of one company on the Colombo Stock Exchange.
@Model
final class Holding {
    var id: UUID = UUID()
    /// CSE symbol, e.g. "JKH.N0000".
    var symbol: String = ""
    var companyName: String = ""
    var quantity: Double = 0
    /// Average price paid per share, including fees if you want them counted.
    var averageCost: Double = 0
    /// Latest market price per share. 0 until set or refreshed.
    var lastPrice: Double = 0
    var priceUpdatedAt: Date?
    var note: String = ""
    var createdAt: Date = Date()

    init(symbol: String, companyName: String = "", quantity: Double, averageCost: Double, lastPrice: Double = 0) {
        self.symbol = symbol
        self.companyName = companyName
        self.quantity = quantity
        self.averageCost = averageCost
        self.lastPrice = lastPrice
    }

    var costBasis: Double { quantity * averageCost }

    /// Uses the cost price until a market price is available.
    var marketValue: Double { quantity * (lastPrice > 0 ? lastPrice : averageCost) }

    var gain: Double { marketValue - costBasis }

    var gainPercent: Double { costBasis > 0 ? gain / costBasis : 0 }

    var displayName: String { companyName.isEmpty ? symbol : companyName }

    /// Records buying more shares: updates quantity and the average cost.
    func recordBuy(quantity bought: Double, price: Double) {
        guard bought > 0 else { return }
        let totalCost = costBasis + bought * price
        quantity += bought
        averageCost = quantity > 0 ? totalCost / quantity : 0
    }

    /// Records selling shares. Average cost stays the same.
    func recordSell(quantity sold: Double) {
        quantity = max(0, quantity - sold)
    }
}
