import Foundation
import SwiftData
import UIKit

enum InstallmentProvider: String, CaseIterable, Codable, Identifiable {
    case mintpay = "Mintpay"
    case koko = "Koko"
    case other = "Other"

    var id: String { rawValue }

    var colorHex: String {
        switch self {
        case .mintpay: return "#3A3A42"
        case .koko: return "#2E3B2A"
        case .other: return "#33334A"
        }
    }

    /// Website used to fetch the provider's logo.
    var domain: String? {
        switch self {
        case .mintpay: return "mintpay.lk"
        case .koko: return "paykoko.com"
        case .other: return nil
        }
    }

    /// A logo shipped with the app, used instead of downloading one.
    var bundledLogo: Data? {
        switch self {
        case .koko: return UIImage(named: "ProviderKoko")?.pngData()
        case .mintpay, .other: return nil
        }
    }

    /// The provider's logo: the bundled one, or the downloaded one (fetched once at launch).
    var cachedLogo: Data? {
        bundledLogo ?? domain.flatMap { LogoCache.data(for: $0) }
    }
}

/// A buy-now-pay-later purchase split into installments.
@Model
final class InstallmentPlan {
    var id: UUID = UUID()
    var title: String = ""
    var providerRaw: String = InstallmentProvider.mintpay.rawValue
    var totalAmount: Double = 0
    var colorHex: String = "#3A3A42"
    @Attribute(.externalStorage) var logoData: Data?
    var createdAt: Date = Date()

    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Installment.plan)
    var installments: [Installment] = []

    init(title: String, provider: InstallmentProvider, totalAmount: Double, account: Account? = nil) {
        self.title = title
        self.providerRaw = provider.rawValue
        self.totalAmount = totalAmount
        self.colorHex = provider.colorHex
        self.logoData = provider.cachedLogo
        self.account = account
    }

    var provider: InstallmentProvider {
        get { InstallmentProvider(rawValue: providerRaw) ?? .other }
        set { providerRaw = newValue.rawValue }
    }

    var sortedInstallments: [Installment] {
        installments.sorted { $0.number < $1.number }
    }

    var nextDue: Installment? {
        sortedInstallments.first { $0.paidAt == nil }
    }

    var remainingAmount: Double {
        installments.filter { $0.paidAt == nil }.reduce(0) { $0 + $1.amount }
    }

    var isComplete: Bool { nextDue == nil }

    /// Splits `totalAmount` evenly into `count` installments, one every `monthsBetween` months.
    /// Call after inserting the plan into `context`.
    func buildSchedule(count: Int, firstDue: Date, monthsBetween: Int = 1, in context: ModelContext) {
        guard count > 0 else { return }
        let each = (totalAmount / Double(count) * 100).rounded() / 100
        for index in 0..<count {
            let due = Calendar.current.date(byAdding: .month, value: index * monthsBetween, to: firstDue) ?? firstDue
            // The last installment absorbs any rounding difference.
            let amount = index == count - 1 ? totalAmount - each * Double(count - 1) : each
            let installment = Installment(number: index + 1, amount: amount, dueDate: due)
            context.insert(installment)
            installment.plan = self
        }
    }
}

@Model
final class Installment {
    var id: UUID = UUID()
    var number: Int = 1
    var amount: Double = 0
    var dueDate: Date = Date()
    var paidAt: Date?

    var plan: InstallmentPlan?

    init(number: Int, amount: Double, dueDate: Date) {
        self.number = number
        self.amount = amount
        self.dueDate = dueDate
    }

    var isPaid: Bool { paidAt != nil }
}
