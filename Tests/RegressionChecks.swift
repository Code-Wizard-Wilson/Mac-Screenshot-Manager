import AppKit
import SwiftUI

@main
struct RegressionChecks {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotManager-Checks-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        UserDefaults.standard.setVolatileDomain([
            "ScreenshotManager.folderURL": folder.path,
            AppPreferenceKeys.didCompleteOnboarding: true
        ], forName: UserDefaults.argumentDomain)

        let delegate = AppDelegate()
        precondition(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        precondition(!delegate.responds(to: #selector(NSWindowDelegate.windowWillClose(_:))))
        print("PASS: closing the library does not terminate the application")

        for theme in AppAppearance.allCases {
            theme.apply()
            switch theme {
            case .system: precondition(NSApp.appearance == nil)
            case .light: precondition(NSApp.appearance?.name == .aqua)
            case .dark: precondition(NSApp.appearance?.name == .darkAqua)
            }
        }
        print("PASS: system, light and dark appearance")

        let store = delegate.store
        let clipboardShortcut = store.clipboardHotkey
        let saveShortcut = store.saveHotkey
        store.updateClipboardHotkey(saveShortcut)
        store.updateSaveHotkey(clipboardShortcut)
        precondition(store.clipboardHotkey == clipboardShortcut && store.saveHotkey == saveShortcut)
        print("PASS: conflicting shortcuts leave both actions available")

        let sample = NSImage(size: NSSize(width: 640, height: 400), flipped: false) { rect in
            NSColor(calibratedRed: 0.91, green: 0.89, blue: 0.84, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.19, green: 0.28, blue: 0.25, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 70, dy: 70), xRadius: 20, yRadius: 20).fill()
            ("A little more clarity." as NSString).draw(at: NSPoint(x: 108, y: 200), withAttributes: [
                .font: NSFont.systemFont(ofSize: 32, weight: .medium), .foregroundColor: NSColor.white
            ])
            return true
        }
        let output = try PreparedCaptureOutput.make(from: sample)
        precondition(NSImage(data: output.pngData) != nil)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try ScreenshotStore.writePNGDataToPasteboard(output.pngData, pasteboard: pasteboard)
        precondition(pasteboard.data(forType: .png) == output.pngData)
        print("PASS: Copy writes a readable PNG to an isolated pasteboard")
        let first = try ScreenshotCaptureService.savePNGData(output.pngData, in: folder)
        let second = try ScreenshotCaptureService.savePNGData(output.pngData, in: folder)
        precondition(first != second)
        let savedData = try Data(contentsOf: first)
        precondition(savedData == output.pngData)
        print("PASS: PNG export round trip and unique file names")

        store.refresh(selecting: first)
        store.refresh(selecting: second)
        for _ in 0..<100 where store.isLoading {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(!store.isLoading && store.selectedItem?.url.standardizedFileURL == second.standardizedFileURL,
            "Refresh mismatch: folder=\(store.folderURL), selected=\(String(describing: store.selectedItem?.url)), expected=\(second), error=\(String(describing: store.errorMessage)), loading=\(store.isLoading)")
        print("PASS: latest library refresh wins")

        try await EditorRegressionChecks.run(image: sample, store: store)

        if let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try await Task.sleep(for: .milliseconds(3100))
            let destination = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for theme in [AppAppearance.light, .dark] {
                theme.apply()
                try await snapshot(SettingsView(store: store), size: NSSize(width: 820, height: 580), to: destination.appendingPathComponent("settings-\(theme.rawValue).png"))
                try await snapshot(ContentView(store: store), size: NSSize(width: 1180, height: 760), to: destination.appendingPathComponent("library-\(theme.rawValue).png"))
                try await snapshot(CaptureAnnotationView(store: store, session: CaptureAnnotationSession(image: sample, destination: .capture(.clipboard))), size: NSSize(width: 1280, height: 760), to: destination.appendingPathComponent("editor-\(theme.rawValue).png"))
            }
            print("PASS: six offscreen layout snapshots at \(path)")
        }
        // Only this run's generated fixtures are removed.
        try FileManager.default.removeItem(at: folder)
        print("All regression checks passed.")
    }

    @MainActor
    private static func snapshot<V: View>(_ view: V, size: NSSize, to url: URL) async throws {
        let host = FirstMouseHostingView(rootView: view)
        precondition(host.acceptsFirstMouse(for: nil))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try data.write(to: url)
        window.close()
    }
}
