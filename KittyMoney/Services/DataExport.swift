import SwiftUI
import UIKit

/// Writes all transactions to a CSV file you can save or share.
enum DataExport {
    static func transactionsCSV(_ transactions: [MoneyTransaction]) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines = ["Date,Type,Title,Amount,Account,Category,Note,Source"]
        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            let fields = [
                dateFormatter.string(from: transaction.date),
                transaction.kind.rawValue,
                transaction.title,
                String(format: "%.2f", transaction.amount),
                transaction.account?.shortName ?? "",
                transaction.category?.name ?? "",
                transaction.note,
                transaction.source.rawValue
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KittyMoney-transactions.csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// The standard iOS share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Wraps a file URL so it can drive `.sheet(item:)`.
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
