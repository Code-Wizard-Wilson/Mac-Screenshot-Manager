import AppKit
import SwiftUI

enum AppTypography {
    static let productTitle = Font.system(size: 16, weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 13, weight: .semibold, design: .default)
    static let paneTitle = Font.system(size: 17, weight: .semibold, design: .default)
    static let itemTitle = Font.system(size: 13, weight: .medium, design: .default)
    static let metadata = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let helper = Font.system(size: 12, weight: .regular, design: .default)
}

enum AppTheme {
    static let windowBackground = adaptive(light: 0xF3F0EA, dark: 0x151515)
    static let sidebarBackground = adaptive(light: 0xECE8DF, dark: 0x171717)
    static let contentBackground = adaptive(light: 0xF7F4EE, dark: 0x1B1B1B)
    static let toolbarBackground = adaptive(light: 0xF3F0EA, dark: 0x1B1B1B)
    static let panelBackground = adaptive(light: 0xFFFCF7, dark: 0x202020)
    static let cardBackground = adaptive(light: 0xFFFCF7, dark: 0x242424)
    static let cardHoverBackground = adaptive(light: 0xF7F1E8, dark: 0x2B2B2B)
    static let imageWellBackground = adaptive(light: 0xE7E2D8, dark: 0x111111)
    static let searchFieldBackground = adaptive(light: 0xE9E4DA, dark: 0x242424)
    static let searchFocusedBackground = adaptive(light: 0xFFFDF8, dark: 0x2B2B2B)
    static let sidebarIconBackground = adaptive(light: 0xF9F5ED, dark: 0x242424)
    static let sidebarIconHoverBackground = adaptive(light: 0xFFFBF5, dark: 0x303030)
    static let sidebarIconSelectedBackground = Color.accentColor
    static let captureBlue = adaptive(light: 0x0A84FF, dark: 0x2997FF)
    static let libraryAmber = adaptive(light: 0xD9822B, dark: 0xF2A33A)
    static let settingsViolet = adaptive(light: 0x7B61FF, dark: 0x9B87FF)
    static let successGreen = adaptive(light: 0x1F9D63, dark: 0x32D583)
    static let dangerCoral = adaptive(light: 0xD84E3F, dark: 0xFF6B5A)
    static let assetInk = adaptive(light: 0x2B2926, dark: 0xF3F0EA)
    static let assetMuted = adaptive(light: 0x8D8577, dark: 0x858585)
    static let border = adaptive(light: 0xCEC7BA, dark: 0x3B3B3B).opacity(0.82)
    static let softBorder = adaptive(light: 0xD9D2C7, dark: 0x323232).opacity(0.68)
    static let selectedBackground = Color.accentColor.opacity(0.14)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return color(isDark ? dark : light)
        })
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum AppPreferenceKeys {
    static let showsMenuBarItem = "ScreenshotManager.showsMenuBarItem"
    static let didCompleteOnboarding = "ScreenshotManager.didCompleteOnboarding"
}


extension Notification.Name {
    static let screenshotManagerMenuBarVisibilityDidChange = Notification.Name(
        "ScreenshotManager.MenuBarVisibilityDidChange"
    )
}
