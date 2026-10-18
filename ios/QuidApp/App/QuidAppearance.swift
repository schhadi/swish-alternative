import UIKit

/// UIKit-driven chrome that SwiftUI cannot style directly: navigation titles and segmented controls use Manrope too.
/// Fonts go through UIFontMetrics, scaled for the current text size. Appearance proxies are static, so RootView calls
/// `configure()` again and rebuilds the tab hierarchy when the user changes their text size while the app is running.
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
