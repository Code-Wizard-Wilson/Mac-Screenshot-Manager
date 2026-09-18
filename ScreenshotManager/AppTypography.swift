import AppKit
import SwiftUI

enum AppTypography {
    static let productTitle = Font.system(size: 15, weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 13, weight: .semibold, design: .default)
    static let paneTitle = Font.system(size: 19, weight: .semibold, design: .default)
    static let itemTitle = Font.system(size: 13, weight: .medium, design: .default)
    static let metadata = Font.system(size: 11, weight: .regular, design: .default).monospacedDigit()
    static let helper = Font.system(size: 12, weight: .regular, design: .default)
}

enum AppMotion {
    static let fast = Animation.easeOut(duration: 0.12)
    static let normal = Animation.easeInOut(duration: 0.18)
    static let spring = Animation.spring(response: 0.28, dampingFraction: 0.88)
}

enum AppTheme {
    static let windowBackground = adaptive(light: 0xF7F7F8, dark: 0x151515)
    static let sidebarBackground = adaptive(light: 0xFAFAFA, dark: 0x171717)
    static let contentBackground = adaptive(light: 0xF7F7F8, dark: 0x1B1B1B)
    static let toolbarBackground = adaptive(light: 0xFFFFFF, dark: 0x1B1B1B)
    static let panelBackground = adaptive(light: 0xFFFFFF, dark: 0x202020)
    static let cardBackground = adaptive(light: 0xFFFFFF, dark: 0x242424)
    static let cardHoverBackground = adaptive(light: 0xF4F4F5, dark: 0x2B2B2B)
    static let imageWellBackground = adaptive(light: 0xF1F1F3, dark: 0x111111)
    static let searchFieldBackground = adaptive(light: 0xF4F4F5, dark: 0x242424)
    static let searchFocusedBackground = adaptive(light: 0xFFFFFF, dark: 0x2B2B2B)
    static let sidebarIconBackground = adaptive(light: 0xF4F4F5, dark: 0x242424)
    static let sidebarIconHoverBackground = adaptive(light: 0xEEEEF0, dark: 0x303030)
    static let sidebarIconSelectedBackground = adaptive(light: 0xEEEEF0, dark: 0x343434)

    // Transitional semantic aliases used by the current UI. The next UI pass
    // removes per-section colors and keeps one accent plus destructive red.
    static let captureBlue = Color.accentColor
    static let libraryAmber = adaptive(light: 0x60646C, dark: 0xB7B7BD)
    static let settingsViolet = adaptive(light: 0x60646C, dark: 0xB7B7BD)
    static let successGreen = Color.accentColor
    static let dangerCoral = adaptive(light: 0xD70015, dark: 0xFF6961)

    static let assetInk = adaptive(light: 0x18181B, dark: 0xF4F4F5)
    static let assetMuted = adaptive(light: 0x8A8A93, dark: 0x8E8E93)
    static let border = adaptive(light: 0xE5E7EB, dark: 0x3B3B3B)
    static let softBorder = adaptive(light: 0xECEDEF, dark: 0x323232)
    static let selectedBackground = adaptive(light: 0xF0F1F3, dark: 0x2C2C2E)

    // Annotation editor: Claude-inspired warm neutrals with restrained contrast.
    static let editorCanvasBackground = adaptive(light: 0xF7F6F2, dark: 0xF7F6F2)
    static let editorSurface = adaptive(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let editorSurfaceHover = adaptive(light: 0xF7F6F2, dark: 0xF7F6F2)
    static let editorSelectedBackground = adaptive(light: 0xECEAE4, dark: 0xECEAE4)
    static let editorInk = adaptive(light: 0x2D2C2A, dark: 0x2D2C2A)
    static let editorMuted = adaptive(light: 0x77746F, dark: 0x77746F)
    static let editorBorder = adaptive(light: 0xE4E1DA, dark: 0xE4E1DA)
    static let editorAccent = adaptive(light: 0xCC785C, dark: 0xCC785C)

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
