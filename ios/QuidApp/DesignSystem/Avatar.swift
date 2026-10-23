import SwiftUI

/// Initials on a tinted circle. Decorative: the surrounding row carries the accessible name. The circle grows with the
/// text size, by the same factor as the initials, so they never have to shrink to fit.
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
        let side = (size * scale).rounded()
        ZStack {
            Circle()
                .fill(tint.background)
            Text(Avatar.initials(for: name))
                .font(.quid(.bold, size: size * 0.36, relativeTo: .body))
                .foregroundStyle(tint.foreground)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// "Priya Patel" -> "PP", "cher" -> "C", "" -> "?"
    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
