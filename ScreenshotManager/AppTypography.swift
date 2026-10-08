import AppKit
import SwiftUI

enum AppTypography {
    static let productTitle = Font.system(size: 14, weight: .semibold, design: .default)
    static let eyebrow = Font.system(size: 10, weight: .semibold, design: .default)
    static let sectionTitle = Font.system(size: 13, weight: .semibold, design: .default)
    static let paneTitle = Font.system(size: 22, weight: .medium, design: .default)
    static let itemTitle = Font.system(size: 13, weight: .medium, design: .default)
    static let metadata = Font.system(size: 10.5, weight: .regular, design: .monospaced)
    static let helper = Font.system(size: 12, weight: .regular, design: .default)
}

enum AppMotion {
    static let fast = Animation.easeOut(duration: 0.18)
    static let normal = Animation.smooth(duration: 0.26, extraBounce: 0)
    static let spring = Animation.spring(response: 0.36, dampingFraction: 1)
}

struct RespectMotionPreferences: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}

enum AppTheme {
    // A warm neutral system inspired by Codex: quiet chrome, strong content
    // contrast, and one restrained accent instead of per-feature colors.
    static let windowBackground = adaptive(light: 0xF1F1EE, dark: 0x121211)
    static let sidebarBackground = adaptive(light: 0xEAEAE6, dark: 0x171716)
    static let contentBackground = adaptive(light: 0xF0EFEC, dark: 0x232322)
    static let toolbarBackground = adaptive(light: 0xF0EFEC, dark: 0x232322)
    static let panelBackground = adaptive(light: 0xF3F3F0, dark: 0x20201E)
    static let cardBackground = adaptive(light: 0xF5F4F1, dark: 0x292928)
    static let cardHoverBackground = adaptive(light: 0xF0F0EC, dark: 0x292927)
    static let imageWellBackground = adaptive(light: 0xE9E9E5, dark: 0x0E0E0D)
    static let searchFieldBackground = adaptive(light: 0xECECE8, dark: 0x242422)
    static let searchFocusedBackground = adaptive(light: 0xF5F4F1, dark: 0x30302E)
    static let sidebarIconBackground = adaptive(light: 0xE2E2DD, dark: 0x222220)
    static let sidebarIconHoverBackground = adaptive(light: 0xDEDED9, dark: 0x292927)
    static let sidebarIconSelectedBackground = adaptive(light: 0xDCDCD6, dark: 0x30302D)

    static let accent = adaptive(light: 0x746B60, dark: 0xABA397)
    static let accentSoft = adaptive(light: 0xE6E2DB, dark: 0x37342F)
    static let primaryButtonBackground = adaptive(light: 0x494743, dark: 0x55524C)
    static let primaryButtonForeground = adaptive(light: 0xF6F4EF, dark: 0xF0EEE9)
    static let captureBlue = accent
    static let libraryAmber = adaptive(light: 0x666660, dark: 0xB4B4AD)
    static let settingsViolet = adaptive(light: 0x666660, dark: 0xB4B4AD)
    static let successGreen = adaptive(light: 0x557665, dark: 0x92B09F)
    static let dangerCoral = adaptive(light: 0xD70015, dark: 0xFF6961)

    static let assetInk = adaptive(light: 0x353430, dark: 0xDEDDD7)
    static let assetMuted = adaptive(light: 0x777771, dark: 0xA2A29C)
    static let border = adaptive(light: 0xDDDBD5, dark: 0x3B3B37)
    static let softBorder = adaptive(light: 0xE4E2DC, dark: 0x343431)
    static let selectedBackground = adaptive(light: 0xE8E8E3, dark: 0x2D2D2A)

    static let editorCanvasBackground = adaptive(light: 0xE7E6E2, dark: 0x222221)
    static let editorSurface = adaptive(light: 0xF1F0EC, dark: 0x2D2D2A)
    static let editorSurfaceHover = cardHoverBackground
    static let editorSelectedBackground = selectedBackground
    static let editorInk = assetInk
    static let editorMuted = assetMuted
    static let editorBorder = softBorder
    static let editorAccent = accent

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
    static let appearance = "ScreenshotManager.appearance"
    static let showsMenuBarItem = "ScreenshotManager.showsMenuBarItem"
    static let didCompleteOnboarding = "ScreenshotManager.didCompleteOnboarding"
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}


extension Notification.Name {
    static let screenshotManagerMenuBarVisibilityDidChange = Notification.Name(
        "ScreenshotManager.MenuBarVisibilityDidChange"
    )
}
