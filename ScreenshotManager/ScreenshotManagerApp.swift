import AppKit
import SwiftUI

@main
struct ScreenshotManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

struct MenuBarPanelView: View {
    @ObservedObject var store: ScreenshotStore
    let openManager: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void
    @AppStorage(AppPreferenceKeys.didCompleteOnboarding) private var didCompleteOnboarding = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                BrandMarkView(isActive: store.isCapturing)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screenshot Manager")
                        .font(.system(size: 14, weight: .semibold))

                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)

            VStack(alignment: .leading, spacing: 5) {
                Text("CAPTURE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)

                MenuBarCaptureRow(
                    title: "Clipboard",
                    subtitle: "Capture, edit, then copy",
                    shortcut: store.clipboardHotkey.displayString,
                    systemImage: "doc.on.clipboard",
                    tint: AppTheme.libraryAmber,
                    isDisabled: store.isCapturing
                ) {
                    store.captureToClipboard()
                }

                MenuBarCaptureRow(
                    title: "Library",
                    subtitle: "Capture and save as PNG",
                    shortcut: store.saveHotkey.displayString,
                    systemImage: "tray.and.arrow.down",
                    tint: AppTheme.successGreen,
                    isDisabled: store.isCapturing
                ) {
                    store.captureAndSaveToLibrary()
                }
            }
            .padding(.horizontal, 8)

            if !store.requiredPermissionsGranted {
                MenuBarPermissionView(store: store)
                    .padding(.horizontal, 8)
            }

            Divider()
                .opacity(0.55)
                .padding(.horizontal, 8)

            Button(action: openManager) {
                HStack(spacing: 9) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.captureBlue)
                        .frame(width: 25, height: 25)
                        .background(AppTheme.captureBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Open Library")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("\(store.items.count) screenshot\(store.items.count == 1 ? "" : "s")")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuBarHoverButtonStyle())
            .padding(.horizontal, 8)

            HStack(spacing: 4) {
                MenuBarFooterButton(title: "Settings", systemImage: "gearshape", action: openSettings)
                MenuBarFooterButton(title: "Refresh", systemImage: "arrow.clockwise") { store.refresh() }
                MenuBarFooterButton(title: "Guide", systemImage: "questionmark.circle") {
                    didCompleteOnboarding = false
                    openManager()
                }
                MenuBarFooterButton(title: "Quit", systemImage: "power", action: quit)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 292)
        .background {
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                Color.primary.opacity(0.018)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            store.refreshRequiredPermissions()
        }
    }

    private var statusText: String {
        if store.isCapturing { return "Capturing…" }
        return store.requiredPermissionsGranted ? "Ready" : "Permissions needed"
    }

    private var statusColor: Color {
        if store.isCapturing { return AppTheme.libraryAmber }
        return store.requiredPermissionsGranted ? AppTheme.successGreen : AppTheme.dangerCoral
    }
}

private struct MenuBarCaptureRow: View {
    let title: String
    let subtitle: String
    let shortcut: String
    let systemImage: String
    let tint: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(shortcut)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 0.6)
                    }
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuBarHoverButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
    }
}

private struct MenuBarHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.085 : 0.025))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045), lineWidth: 0.7)
            }
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

private struct MenuBarPermissionView: View {
    @ObservedObject var store: ScreenshotStore

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.dangerCoral)

            VStack(alignment: .leading, spacing: 1) {
                Text("Screen access required")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Enable Screen Recording to capture")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Fix") {
                store.requestRequiredPermissions()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
        .background(AppTheme.dangerCoral.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppTheme.dangerCoral.opacity(0.16), lineWidth: 0.7)
        }
    }
}

private struct MenuBarFooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuBarHoverButtonStyle())
    }
}

struct SettingsView: View {
    @ObservedObject var store: ScreenshotStore
    @AppStorage(AppPreferenceKeys.showsMenuBarItem) private var showsMenuBarItem = true
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 168)

            Divider()
                .opacity(0.6)

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedSection.title)
                            .font(.system(size: 20, weight: .semibold))

                        Text(selectedSection.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

                ScrollView {
                    Group {
                        switch selectedSection {
                        case .general:
                            generalSection
                        case .hotkeys:
                            hotkeysSection
                        case .permissions:
                            permissionsSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.primary.opacity(0.012))
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 440, idealHeight: 500)
        .background {
            VisualEffectView(material: .contentBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
        .onAppear {
            store.refreshRequiredPermissions()
            store.refreshLaunchAtLoginStatus()
        }
        .onChange(of: showsMenuBarItem) { _, isVisible in
            NotificationCenter.default.post(
                name: .screenshotManagerMenuBarVisibilityDidChange,
                object: isVisible
            )
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandMarkView(isActive: false)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("Screenshot Manager")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 18)

            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: section.icon)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(selectedSection == section ? section.tint : Color.secondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    section.tint.opacity(selectedSection == section ? 0.13 : 0),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )

                            Text(section.title)
                                .font(.system(size: 12.5, weight: selectedSection == section ? .semibold : .medium))
                                .foregroundStyle(selectedSection == section ? Color.primary : Color.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(selectedSection == section ? 0.065 : 0))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            Text("Changes are saved automatically")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(.ultraThinMaterial)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "App") {
                SettingsRow(
                    icon: "menubar.rectangle",
                    tint: AppTheme.captureBlue,
                    title: "Show in menu bar",
                    detail: showsMenuBarItem
                        ? "Keep Screenshot Manager available from the top menu bar."
                        : "Hidden from the menu bar. Re-enable it here from the main app."
                ) {
                    Toggle("", isOn: $showsMenuBarItem)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    icon: "power",
                    tint: AppTheme.successGreen,
                    title: "Open at login",
                    detail: "Launch Screenshot Manager automatically when you sign in."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.launchAtLoginEnabled },
                            set: { store.updateLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            SettingsCard(title: "Storage") {
                SettingsRow(
                    icon: "folder",
                    tint: AppTheme.libraryAmber,
                    title: "Library folder",
                    detail: store.folderURL.path(percentEncoded: false)
                ) {
                    HStack(spacing: 6) {
                        Button("Choose") {
                            store.chooseFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            store.revealLibraryFolder()
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                }
            }
        }
    }

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Capture shortcuts") {
                SettingsRow(
                    icon: "doc.on.clipboard",
                    tint: AppTheme.libraryAmber,
                    title: "Capture to clipboard",
                    detail: "Capture, annotate, then copy the final image."
                ) {
                    HotkeyRecorderView(
                        hotkey: Binding(
                            get: { store.clipboardHotkey },
                            set: { store.updateClipboardHotkey($0) }
                        )
                    )
                    .frame(width: 220, height: 32)
                }

                SettingsDivider()

                SettingsRow(
                    icon: "tray.and.arrow.down",
                    tint: AppTheme.successGreen,
                    title: "Capture to library",
                    detail: "Capture, annotate, then save a permanent PNG."
                ) {
                    HotkeyRecorderView(
                        hotkey: Binding(
                            get: { store.saveHotkey },
                            set: { store.updateSaveHotkey($0) }
                        )
                    )
                    .frame(width: 220, height: 32)
                }
            }

            SettingsInfoBanner(
                systemImage: "keyboard",
                text: "Hotkeys keep working even when the menu bar icon is hidden."
            )
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Screen capture") {
                SettingsRow(
                    icon: store.screenRecordingAccessGranted ? "checkmark.shield.fill" : "lock.rectangle",
                    tint: store.screenRecordingAccessGranted ? AppTheme.successGreen : AppTheme.dangerCoral,
                    title: "Screen Recording",
                    detail: store.screenRecordingAccessGranted
                        ? "Access is enabled and Screenshot Manager can capture your screen."
                        : "Required to capture windows and screen regions."
                ) {
                    if store.screenRecordingAccessGranted {
                        Label("Allowed", systemImage: "checkmark")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AppTheme.successGreen)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(AppTheme.successGreen.opacity(0.10), in: Capsule())
                    } else {
                        Button("Open Settings") {
                            store.openScreenRecordingSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Refresh Status") {
                    store.refreshRequiredPermissions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !store.requiredPermissionsGranted {
                    Button("Request Access") {
                        store.requestRequiredPermissions()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

private enum SettingsSection: CaseIterable, Identifiable {
    case general
    case hotkeys
    case permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .hotkeys: return "Hotkeys"
        case .permissions: return "Permissions"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "App behavior, menu bar, and storage"
        case .hotkeys: return "Keyboard shortcuts for fast capture"
        case .permissions: return "System access required for screen capture"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .hotkeys: return "keyboard"
        case .permissions: return "lock.shield"
        }
    }

    var tint: Color {
        switch self {
        case .general: return AppTheme.settingsViolet
        case .hotkeys: return AppTheme.libraryAmber
        case .permissions: return AppTheme.captureBlue
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.65)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.7)
            }
        }
    }
}

private struct SettingsRow<Controls: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder var controls: Controls

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))

                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            controls
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(minHeight: 58)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .opacity(0.55)
            .padding(.leading, 54)
    }
}

private struct SettingsInfoBanner: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppTheme.captureBlue)

            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(AppTheme.captureBlue.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppTheme.captureBlue.opacity(0.10), lineWidth: 0.6)
        }
    }
}
