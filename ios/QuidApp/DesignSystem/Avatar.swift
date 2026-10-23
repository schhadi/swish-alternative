import SwiftUI

/// Initials on a tinted circle. Decorative: the surrounding row carries the accessible name. The circle grows with the
/// text size up to 1.6 times, so a row still leaves room for the name at the largest sizes, and the initials are sized
/// from the circle, so they always fit.
struct Avatar: View {
    let name: String
    let size: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    init(name: String, size: CGFloat = 44) {
        self.name = name
        self.size = size
    }

    var body: some View {
        let tint = AvatarTint.tint(for: name)
        let side = (size * min(scale, Avatar.maximumScale)).rounded()
        ZStack {
            Circle()
                .fill(tint.background)
            Text(Avatar.initials(for: name))
                .font(.custom(QuidFontWeight.bold.postScriptName, fixedSize: side * 0.36))
                .foregroundStyle(tint.foreground)
                .lineLimit(1)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    static let maximumScale: CGFloat = 1.6

    /// "Priya Patel" -> "PP", "cher" -> "C", "" -> "?"
    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
