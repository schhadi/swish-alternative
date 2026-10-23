import SwiftUI

/// Rows keep names and subtitles to one line at standard text sizes and let them wrap at accessibility sizes, so a
/// large text size never cuts a name short (HIG, Dynamic Type).
struct QuidLineLimit: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let lines: Int

    func body(content: Content) -> some View {
        content.lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : lines)
    }
}

extension View {
    func quidLineLimit(_ lines: Int = 1) -> some View {
        modifier(QuidLineLimit(lines: lines))
    }
}
