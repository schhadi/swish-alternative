import SwiftUI

// Manrope (bundled, see Resources/Fonts and Info.plist UIAppFonts). Weights 600/700/800 only.
// Every style is relative to a system text style so Dynamic Type scales it.

enum QuidFontWeight {
    case semibold, bold, extrabold

    var postScriptName: String {
        switch self {
        case .semibold: return "Manrope-SemiBold"
        case .bold: return "Manrope-Bold"
        case .extrabold: return "Manrope-ExtraBold"
        }
    }
}

extension Font {
    static func quid(_ weight: QuidFontWeight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: style)
    }

    static let quidLargeTitle = quid(.extrabold, size: 34, relativeTo: .largeTitle)
    static let quidTitle = quid(.extrabold, size: 28, relativeTo: .title)
    static let quidTitle2 = quid(.bold, size: 22, relativeTo: .title2)
    static let quidTitle3 = quid(.bold, size: 20, relativeTo: .title3)
    static let quidHeadline = quid(.bold, size: 17, relativeTo: .headline)
    static let quidBody = quid(.semibold, size: 17, relativeTo: .body)
    static let quidCallout = quid(.semibold, size: 16, relativeTo: .callout)
    static let quidSubheadline = quid(.semibold, size: 15, relativeTo: .subheadline)
    static let quidFootnote = quid(.semibold, size: 13, relativeTo: .footnote)
    static let quidCaption = quid(.semibold, size: 12, relativeTo: .caption)

    /// Big numbers are always 800.
    static let quidAmountHero = quid(.extrabold, size: 48, relativeTo: .largeTitle)
    static let quidAmountLarge = quid(.extrabold, size: 34, relativeTo: .largeTitle)
    static let quidAmount = quid(.extrabold, size: 17, relativeTo: .body)
}

/// Money rendered with the spec's tight letter-spacing.
struct AmountText: View {
    enum Style {
        case hero, large, inline
    }

    let money: Money
    var style: Style = .inline
    var explicitPlus: Bool = false
    var color: Color? = nil

    var body: some View {
        Text(money.formatted(explicitPlus: explicitPlus))
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color ?? Color.quidInk)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(money.spokenDescription)
    }

    private var font: Font {
        switch style {
        case .hero: return .quidAmountHero
        case .large: return .quidAmountLarge
        case .inline: return .quidAmount
        }
    }

    private var tracking: CGFloat {
        switch style {
        case .hero, .large: return -2
        case .inline: return -0.5
        }
    }
}
