import SwiftUI
import UIKit

/// Applies the active OSRS theme to already-mounted UIKit controls.
///
/// `UI*.appearance()` only affects controls created after it runs. Theme changes
/// therefore have to walk every connected window and retint live switches,
/// sliders, navigation bars, and the rest. Call this after the theme manager
/// paints windows — not instead of SwiftUI `osrsTheme` environment updates.
enum osrsLiveThemeApplier {
    @MainActor
    static func apply(
        _ theme: any osrsThemeProtocol,
        colorScheme: ColorScheme?
    ) {
        applyAppearanceProxies(theme)
        let resolved = colorScheme ?? .light
        connectedWindows.forEach { window in
            apply(theme, to: window, colorScheme: resolved)
        }
    }

    @MainActor
    static func apply(
        _ theme: any osrsThemeProtocol,
        to window: UIWindow,
        colorScheme: ColorScheme
    ) {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        window.overrideUserInterfaceStyle = style
        apply(theme, toView: window)
        apply(theme, toViewController: window.rootViewController)
    }

    @MainActor
    static func apply(_ theme: any osrsThemeProtocol, toView view: UIView) {
        tint(view, with: theme)
        view.subviews.forEach { apply(theme, toView: $0) }
    }

    @MainActor
    static func apply(_ theme: any osrsThemeProtocol, toViewController viewController: UIViewController?) {
        guard let viewController else { return }
        if let navigationController = viewController as? UINavigationController {
            tint(navigationController.navigationBar, with: theme)
        }
        if let tabBarController = viewController as? UITabBarController {
            tabBarController.tabBar.tintColor = UIColor(theme.primary)
        }
        viewController.children.forEach { apply(theme, toViewController: $0) }
        apply(theme, toViewController: viewController.presentedViewController)
    }

    @MainActor
    static func tint(_ control: UIView, with theme: any osrsThemeProtocol) {
        let primary = UIColor(theme.primary)
        let surface = UIColor(theme.surface)
        let onPrimary = UIColor(theme.onPrimary)
        let onSurface = UIColor(theme.onSurface)
        let surfaceVariant = UIColor(theme.surfaceVariant)

        switch control {
        case let toggle as UISwitch:
            toggle.onTintColor = primary
            toggle.thumbTintColor = switchThumbColor()
        case let slider as UISlider:
            slider.minimumTrackTintColor = primary
            slider.thumbTintColor = primary
            slider.tintColor = primary
        case let segmented as UISegmentedControl:
            segmented.selectedSegmentTintColor = primary
            segmented.setTitleTextAttributes([.foregroundColor: onPrimary], for: .selected)
            segmented.setTitleTextAttributes([.foregroundColor: onSurface], for: .normal)
        case let progress as UIProgressView:
            progress.progressTintColor = primary
            progress.trackTintColor = surfaceVariant
        case let spinner as UIActivityIndicatorView:
            spinner.color = primary
        case let stepper as UIStepper:
            stepper.tintColor = primary
        case let pageControl as UIPageControl:
            pageControl.currentPageIndicatorTintColor = primary
            pageControl.pageIndicatorTintColor = surfaceVariant
        case let searchBar as UISearchBar:
            searchBar.tintColor = primary
        case let refresh as UIRefreshControl:
            refresh.tintColor = primary
        case let navigationBar as UINavigationBar:
            tint(navigationBar, with: theme)
        case let tabBar as UITabBar:
            tabBar.tintColor = primary
        default:
            break
        }
    }

    @MainActor
    static func tint(_ navigationBar: UINavigationBar, with theme: any osrsThemeProtocol) {
        let primary = UIColor(theme.primary)
        navigationBar.tintColor = primary
        if #available(iOS 26.0, *) {
            return
        }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(theme.surface)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(theme.onSurface)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(theme.onSurface)]
        navigationBar.standardAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
    }

    @MainActor
    private static func applyAppearanceProxies(_ theme: any osrsThemeProtocol) {
        let primary = UIColor(theme.primary)
        UINavigationBar.appearance().tintColor = primary
        UITabBar.appearance().tintColor = primary
        UITableView.appearance().backgroundColor = UIColor(theme.background)
        UITableViewCell.appearance().backgroundColor = UIColor(theme.surface)
        UICollectionView.appearance().backgroundColor = UIColor(theme.background)
        UIProgressView.appearance().tintColor = primary
        UIProgressView.appearance().trackTintColor = UIColor(theme.surfaceVariant)
        UIActivityIndicatorView.appearance().color = primary
        UISwitch.appearance().onTintColor = primary
        UISwitch.appearance().thumbTintColor = switchThumbColor()
        UISlider.appearance().tintColor = primary
        UISlider.appearance().thumbTintColor = primary
        UISegmentedControl.appearance().selectedSegmentTintColor = primary
        UISegmentedControl.appearance().setTitleTextAttributes([
            .foregroundColor: UIColor(theme.onPrimary)
        ], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([
            .foregroundColor: UIColor(theme.onSurface)
        ], for: .normal)
        UIStepper.appearance().tintColor = primary
        UIPageControl.appearance().currentPageIndicatorTintColor = primary
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(theme.surfaceVariant)
        UISearchBar.appearance().tintColor = primary
        UIRefreshControl.appearance().tintColor = primary

        if #available(iOS 26.0, *) {
            UIApplication.applyStableTabBarAppearance()
        } else {
            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithOpaqueBackground()
            navAppearance.backgroundColor = UIColor(theme.surface)
            navAppearance.titleTextAttributes = [.foregroundColor: UIColor(theme.onSurface)]
            navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(theme.onSurface)]
            UINavigationBar.appearance().standardAppearance = navAppearance
            UINavigationBar.appearance().compactAppearance = navAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navAppearance

            let tabAppearance = UITabBarAppearance()
            tabAppearance.configureWithOpaqueBackground()
            tabAppearance.backgroundColor = UIColor(theme.surface)
            UITabBar.appearance().standardAppearance = tabAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        }
    }

    /// Android `switch_thumb_tint` uses `osrs_brown_deep` for the checked thumb
    /// in both themes so the gold track stays legible. Parchment-as-thumb reads
    /// as a white pill on light appearance.
    static func switchThumbColor() -> UIColor {
        UIColor(red: 76.0 / 255.0, green: 61.0 / 255.0, blue: 42.0 / 255.0, alpha: 1)
    }

    @MainActor
    private static var connectedWindows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }
}
