import SwiftUI

struct ProgressBar: View {
    /// 0...1. Values outside are clamped.
    var value: Double
    var tint: Color = Theme.lime
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geometry.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(max(0, min(1, value)) * 100)) percent")
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            trailing()
                .font(.system(size: 14, weight: .medium))
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// Large screen title used at the top of each tab.
struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Card placeholder for features that are coming in a later step.
struct ComingNextCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

/// Row used for transactions and payments: tile, two lines of text, amount on the right.
struct ListRow<Leading: View>: View {
    @ViewBuilder var leading: () -> Leading
    let title: String
    let subtitle: String
    let amount: String
    var amountColor: Color = Theme.textPrimary
    var caption: String? = nil
    var captionColor: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(amount)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(amountColor)
                if let caption {
                    Text(caption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(captionColor)
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// Lime pill segmented control matching the design.
struct PillSegments<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isActive = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isActive ? Theme.onLime : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isActive ? Theme.lime : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Grid of selectable account chips.
struct AccountChips: View {
    let accounts: [Account]
    @Binding var selection: UUID?
    var excluded: UUID? = nil

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(accounts.filter { $0.id != excluded }) { account in
                let isSelected = selection == account.id
                Button {
                    selection = account.id
                } label: {
                    HStack(spacing: 8) {
                        LogoTile(name: account.shortName, colorHex: account.colorHex, logoData: account.logoData, size: 24)
                        Text(account.shortName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accentText : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Small grey label above a group of fields.
struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
    }
}
