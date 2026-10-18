import SwiftUI

/// Initials on a tinted circle. Decorative: the surrounding row carries the accessible name.
struct Avatar: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        let tint = AvatarTint.tint(for: name)
        ZStack {
            Circle()
                .fill(tint.background)
            Text(Avatar.initials(for: name))
                .font(.quid(.bold, size: size * 0.36, relativeTo: .body))
                .foregroundStyle(tint.foreground)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// "Priya Patel" -> "PP", "cher" -> "C", "" -> "?"
    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
