import UIKit

/// UIKit-driven chrome that SwiftUI cannot style directly: navigation titles and segmented controls use Manrope too.
/// Fonts go through UIFontMetrics, scaled for the text size at the time of the call. Appearance proxies are static,
/// so RootView calls `configure()` again when the text size changes; bars created after that pick up the new size,
/// bars already on screen keep theirs until recreated (SwiftUI content scales live regardless).
enum QuidAppearance {
    static func configure() {
        let navigationBar = UINavigationBar.appearance()
        if let largeTitle = UIFont(name: "Manrope-ExtraBold", size: 34) {
            navigationBar.largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: largeTitle),
            ]
        }
        if let title = UIFont(name: "Manrope-Bold", size: 17) {
            navigationBar.titleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title),
            ]
        }
        if let segmented = UIFont(name: "Manrope-SemiBold", size: 13) {
            let scaled = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: segmented)
            UISegmentedControl.appearance().setTitleTextAttributes([.font: scaled], for: .normal)
            UISegmentedControl.appearance().setTitleTextAttributes([.font: scaled], for: .selected)
        }
    }
}
