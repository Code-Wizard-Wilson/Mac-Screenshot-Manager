import AppKit
import Foundation
import ImageIO
import QuartzCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class PreparedCaptureOutput: @unchecked Sendable {
    let image: NSImage
    let pngData: Data

    init(image: NSImage, pngData: Data) {
        self.image = image
        self.pngData = pngData
    }

    static func make(from image: NSImage) throws -> PreparedCaptureOutput {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageEditingError.renderFailed
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageEditingError.renderFailed
        }
        return PreparedCaptureOutput(image: image, pngData: pngData)
    }
}

@MainActor
final class ScreenshotStore: ObservableObject {
    static let imageDropTypeIdentifiers: [String] = [
        UTType.fileURL.identifier,
        UTType.url.identifier,
        UTType.image.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.tiff.identifier,
        UTType.heic.identifier,
        UTType.heif.identifier,
        "org.webmproject.webp"
    ]

    @Published private(set) var items: [ScreenshotItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var captureNotice: CaptureNotice?
    @Published private(set) var screenRecordingAccessGranted = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published var selectedItem: ScreenshotItem?
    @Published var searchText = ""
    @Published private(set) var clipboardHotkey: AppHotkey
    @Published private(set) var saveHotkey: AppHotkey
    @Published private(set) var folderURL: URL

    private let folderDefaultsKey = "ScreenshotManager.folderURL"
    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "webp"]
    private var noticeClearTask: Task<Void, Never>?
    private var captureEditorWindowController: NSWindowController?
    private var captureEditorActionInProgress = false
    private var previewWindowController: NSWindowController?
    private var pinnedWindowControllers: [String: NSWindowController] = [:]
    private var pinnedImages: [String: NSImage] = [:]
    private var pinnedWindowCloseObservers: [String: NSObjectProtocol] = [:]
    @Published private(set) var pinnedItemIDs: Set<String> = []
    private var temporaryItems: [ScreenshotItem] = []
    private let temporaryImageDirectoryURL: URL
    private var temporaryImageURLs: [String: URL] = [:]

    var hotkeysDidChange: (() -> Void)?

    var filteredItems: [ScreenshotItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.fileName.localizedCaseInsensitiveContains(query)
                || item.captureKind.displayName.localizedCaseInsensitiveContains(query)
                || item.createdAt.formatted(date: .abbreviated, time: .omitted).localizedCaseInsensitiveContains(query)
                || item.modifiedAt.formatted(date: .abbreviated, time: .shortened).localizedCaseInsensitiveContains(query)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryImageDirectoryURL)
    }

    init() {
        temporaryImageDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "ScreenshotManager-\(UUID().uuidString)", directoryHint: .isDirectory)

        let legacyHotkey = AppHotkey.load()
        clipboardHotkey = AppHotkey.load(named: "clipboard", fallback: legacyHotkey)
        saveHotkey = AppHotkey.load(named: "save", fallback: .defaultSaveValue)

        let defaultFolderURL = Self.defaultScreenshotFolder()

        if let savedPath = UserDefaults.standard.string(forKey: folderDefaultsKey),
           !Self.isDesktopFolder(URL(filePath: savedPath)) {
            folderURL = URL(filePath: savedPath)
        } else {
            folderURL = defaultFolderURL
            UserDefaults.standard.set(defaultFolderURL.path(percentEncoded: false), forKey: folderDefaultsKey)
        }

        refreshScreenRecordingAccess()
        refreshLaunchAtLoginStatus()
    }

    func updateClipboardHotkey(_ hotkey: AppHotkey) {
        guard clipboardHotkey != hotkey else {
            return
        }

        clipboardHotkey = hotkey
        hotkey.save(named: "clipboard")
        hotkeysDidChange?()
        showNotice(
            title: "Copy Hotkey Updated",
            detail: hotkey.displayString,
            systemImage: "keyboard",
            tone: .success
        )
    }

    func updateSaveHotkey(_ hotkey: AppHotkey) {
        guard saveHotkey != hotkey else {
            return
        }

        saveHotkey = hotkey
        hotkey.save(named: "save")
        hotkeysDidChange?()
        showNotice(
            title: "Library Hotkey Updated",
            detail: hotkey.displayString,
            systemImage: "keyboard",
            tone: .success
        )
    }

    func refresh(selecting selectedURL: URL? = nil) {
        isLoading = true
        errorMessage = nil

        let folderURL = folderURL
        let imageExtensions = imageExtensions

        Task.detached(priority: .userInitiated) {
            do {
                let scannedItems = try Self.scanFolder(folderURL, imageExtensions: imageExtensions)
                await MainActor.run {
                    self.items = self.temporaryItems + scannedItems
                    if let selectedURL {
                        self.selectedItem = self.items.first { $0.url == selectedURL } ?? self.items.first
                    } else {
                        self.selectedItem = self.selectedItem.flatMap { selected in
                            self.items.first(where: { $0.id == selected.id })
                        } ?? self.items.first
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.items = self.temporaryItems
                    self.selectedItem = self.temporaryItems.first
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    var requiredPermissionsGranted: Bool {
        screenRecordingAccessGranted
    }

    var missingRequiredPermissionText: String {
        missingPermissionNames.joined(separator: " and ")
    }

    func captureToClipboard() {
        runOverlayCapture(mode: .clipboard)
    }

    func captureAndSaveToLibrary() {
        runOverlayCapture(mode: .save)
    }

    func refreshRequiredPermissions() {
        refreshScreenRecordingAccess()
    }

    func requestRequiredPermissions() {
        let hadScreenRecording = screenRecordingAccessGranted
        if !hadScreenRecording {
            _ = requestScreenRecordingAccess()
        }

        refreshRequiredPermissions()

        guard !screenRecordingAccessGranted else {
            showNotice(
                title: "Permissions Ready",
                detail: "Screen Recording is active.",
                systemImage: "checkmark.shield",
                tone: .success
            )
            return
        }

        let missing = missingPermissionNames.joined(separator: " and ")
        showNotice(
            title: "Permission Required",
            detail: "Allow \(missing) in System Settings, then quit and reopen the app.",
            systemImage: "lock.rectangle",
            tone: .failure
        )
    }

    func refreshScreenRecordingAccess() {
        let hasAccess = ScreenCaptureOverlayController.hasScreenCaptureAccess
        screenRecordingAccessGranted = hasAccess

        if hasAccess {
            clearScreenRecordingError()
        }
    }

    @discardableResult
    func requestScreenRecordingAccess() -> Bool {
        if ScreenCaptureOverlayController.hasScreenCaptureAccess {
            refreshScreenRecordingAccess()
            return true
        }

        let granted = ScreenCaptureOverlayController.requestScreenCaptureAccess()
        refreshScreenRecordingAccess()
        return granted || screenRecordingAccessGranted
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }

            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            errorMessage = error.localizedDescription
            showNotice(
                title: "Startup Setting Failed",
                detail: error.localizedDescription,
                systemImage: "exclamationmark.triangle",
                tone: .failure
            )
        }
    }

    func openScreenRecordingSettings() {
        openScreenRecordingSettingsURL()
    }

    private func openScreenRecordingSettingsURL() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Screenshot Folder"
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        folderURL = url
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: folderDefaultsKey)
        refresh()
    }

    func revealLibraryFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }

    func open(_ item: ScreenshotItem) {
        guard !item.isTemporary else {
            openPreviewWindow(for: item)
            return
        }

        NSWorkspace.shared.open(item.url)
    }

    func openPreviewWindow(for item: ScreenshotItem) {
        previewWindowController?.close()

        let contentView = ScreenshotPreviewWindowView(store: self, item: item)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = item.fileName
        window.titleVisibility = .hidden
        window.identifier = NSUserInterfaceItemIdentifier("ScreenshotManager.PreviewWindow")
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.minSize = NSSize(width: 760, height: 520)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false

        let controller = NSWindowController(window: window)
        previewWindowController = controller
        showWindowWithEntranceAnimation(controller)
    }

    func isPinned(_ item: ScreenshotItem) -> Bool {
        pinnedItemIDs.contains(item.id)
    }

    func isPinned(id: String) -> Bool {
        pinnedItemIDs.contains(id)
    }

    /// Pins a library/clipboard screenshot as a floating always-on-top reference window.
    func pin(_ item: ScreenshotItem) {
        if let controller = pinnedWindowControllers[item.id], let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        Task { @MainActor in
            guard let image = await loadImage(for: item) else {
                showNotice(
                    title: "Pin Failed",
                    detail: "Could not load this screenshot.",
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
                return
            }

            openPinnedWindow(
                id: item.id,
                title: item.fileName,
                image: image,
                dimensionsText: item.dimensionsText
            )
            showNotice(
                title: "Pinned",
                detail: "Stays on top for reference.",
                systemImage: "pin.fill",
                tone: .success
            )
        }
    }

    /// Pins an arbitrary image (e.g. current annotation result) as a floating reference.
    func pinImage(_ image: NSImage, title: String) {
        let id = "pinned-\(UUID().uuidString)"
        let dimensions = Self.imageDimensions(image: image)
        let dimensionsText: String
        if dimensions.width > 0, dimensions.height > 0 {
            dimensionsText = "\(dimensions.width)x\(dimensions.height)"
        } else {
            dimensionsText = "Pinned"
        }

        openPinnedWindow(
            id: id,
            title: title,
            image: image,
            dimensionsText: dimensionsText
        )
        showNotice(
            title: "Pinned",
            detail: "Stays on top for reference.",
            systemImage: "pin.fill",
            tone: .success
        )
    }

    func togglePin(_ item: ScreenshotItem) {
        if isPinned(item) {
            unpin(id: item.id)
        } else {
            pin(item)
        }
    }

    func unpin(id: String) {
        if let observer = pinnedWindowCloseObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }

        if let controller = pinnedWindowControllers.removeValue(forKey: id) {
            controller.close()
        }

        pinnedImages[id] = nil
        pinnedItemIDs.remove(id)
    }

    func pinnedImage(for id: String) -> NSImage? {
        pinnedImages[id]
    }

    func setPinnedWindowOpacity(id: String, opacity: CGFloat) {
        guard let window = pinnedWindowControllers[id]?.window else {
            return
        }

        let clamped = min(max(opacity, 0.25), 1)
        window.alphaValue = clamped
        window.isOpaque = clamped >= 0.99
        window.backgroundColor = clamped >= 0.99 ? .windowBackgroundColor : .clear
    }

    private func openPinnedWindow(id: String, title: String, image: NSImage, dimensionsText: String) {
        pinnedImages[id] = image

        let contentView = PinnedScreenshotWindowView(
            store: self,
            pinID: id,
            title: title,
            dimensionsText: dimensionsText
        )
        let hostingController = NSHostingController(rootView: contentView)

        let preferredSize = Self.preferredPinnedWindowSize(for: image)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: preferredSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.identifier = NSUserInterfaceItemIdentifier("ScreenshotManager.PinnedWindow.\(id)")
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.hasShadow = true
        window.minSize = NSSize(width: 280, height: 200)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setContentSize(preferredSize)
        window.center()

        // Cascade multiple pins slightly so they don't fully stack.
        let offset = CGFloat(pinnedWindowControllers.count % 6) * 28
        if offset > 0 {
            var frame = window.frame
            frame.origin.x += offset
            frame.origin.y -= offset
            window.setFrame(frame, display: false)
        }

        let controller = NSWindowController(window: window)
        pinnedWindowControllers[id] = controller
        pinnedItemIDs.insert(id)

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePinnedWindowClosed(id: id)
            }
        }
        pinnedWindowCloseObservers[id] = observer

        showWindowWithEntranceAnimation(controller)
    }

    private func handlePinnedWindowClosed(id: String) {
        if let observer = pinnedWindowCloseObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        pinnedWindowControllers[id] = nil
        pinnedImages[id] = nil
        pinnedItemIDs.remove(id)
    }

    private static func preferredPinnedWindowSize(for image: NSImage) -> NSSize {
        let imageSize = image.size
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        let maxWidth: CGFloat = 720
        let maxHeight: CGFloat = 520
        let toolbarHeight: CGFloat = 48
        let scale = min(maxWidth / width, maxHeight / height, 1)
        return NSSize(
            width: max(width * scale, 320),
            height: max(height * scale + toolbarHeight, 240)
        )
    }

    func openAnnotationEditor(for item: ScreenshotItem) {
        Task { @MainActor in
            guard let image = await loadImage(for: item) else {
                showNotice(
                    title: "Edit Failed",
                    detail: "Could not load this screenshot.",
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
                return
            }

            showCaptureEditor(image: image, destination: .edit(item))
        }
    }

    func revealInFinder(_ item: ScreenshotItem) {
        guard !item.isTemporary else {
            showNotice(
                title: "Temporary Clipboard Item",
                detail: "This screenshot is in memory only.",
                systemImage: "memorychip",
                tone: .neutral
            )
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copy(_ item: ScreenshotItem) {
        guard let image = image(for: item) else { return }
        do {
            try Self.writeImageToPasteboard(image)
        } catch {
            errorMessage = error.localizedDescription
            showNotice(
                title: "Copy Failed",
                detail: error.localizedDescription,
                systemImage: "exclamationmark.triangle",
                tone: .failure
            )
        }
    }

    func copyEditedImage(_ image: NSImage) {
        do {
            try Self.writeImageToPasteboard(image)
        } catch {
            errorMessage = error.localizedDescription
            showNotice(
                title: "Copy Failed",
                detail: error.localizedDescription,
                systemImage: "exclamationmark.triangle",
                tone: .failure
            )
        }
    }

    private static func writeImageToPasteboard(_ image: NSImage) throws {
        let prepared = try PreparedCaptureOutput.make(from: image)
        try writePNGDataToPasteboard(prepared.pngData)
    }

    private static func writePNGDataToPasteboard(_ pngData: Data) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png], owner: nil)
        let written = pasteboard.setData(pngData, forType: .png)

        guard written, pasteboard.availableType(from: [.png]) != nil else {
            throw ClipboardImageError.writeFailed
        }
    }

    func importDroppedItems(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else {
            return
        }

        let folderURL = folderURL
        let imageExtensions = imageExtensions

        Task { @MainActor in
            do {
                let importedURLs = try await Self.importDroppedProviders(
                    providers,
                    into: folderURL,
                    imageExtensions: imageExtensions
                )

                guard !importedURLs.isEmpty else {
                    showNotice(
                        title: "Nothing Imported",
                        detail: "Drop PNG, JPG, HEIC, TIFF, WebP, or images from Photos.",
                        systemImage: "photo.badge.exclamationmark",
                        tone: .neutral
                    )
                    return
                }

                refresh(selecting: importedURLs.last)
                showNotice(
                    title: importedURLs.count == 1 ? "Image Imported" : "\(importedURLs.count) Images Imported",
                    detail: importedURLs.count == 1 ? importedURLs[0].lastPathComponent : "Saved to Library.",
                    systemImage: "tray.and.arrow.down",
                    tone: .success
                )
            } catch {
                errorMessage = error.localizedDescription
                showNotice(
                    title: "Import Failed",
                    detail: error.localizedDescription,
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
            }
        }
    }

    func saveEditedCopy(_ image: NSImage, source item: ScreenshotItem) {
        do {
            let savedURL: URL

            if item.isTemporary {
                savedURL = try ScreenshotCaptureService.save(image, in: folderURL, kind: .saved)
            } else {
                savedURL = try ImageEditingService.saveCopy(image, sourceURL: item.url)
            }

            refresh(selecting: savedURL)
        } catch {
            errorMessage = error.localizedDescription
            showNotice(
                title: "Save Failed",
                detail: error.localizedDescription,
                systemImage: "exclamationmark.triangle",
                tone: .failure
            )
        }
    }

    func replaceImage(_ image: NSImage, item: ScreenshotItem) {
        if item.isTemporary {
            replaceTemporaryImage(image, item: item)
            return
        }

        do {
            try ImageEditingService.write(image, to: item.url)
            refresh(selecting: item.url)
        } catch {
            errorMessage = error.localizedDescription
            showNotice(
                title: "Replace Failed",
                detail: error.localizedDescription,
                systemImage: "exclamationmark.triangle",
                tone: .failure
            )
        }
    }

    func delete(_ item: ScreenshotItem) {
        if item.isTemporary {
            if let temporaryURL = temporaryImageURLs.removeValue(forKey: item.id) {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            temporaryItems.removeAll { $0.id == item.id }
            items.removeAll { $0.id == item.id }
            selectedItem = items.first
            return
        }

        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showHotkeyRegistrationFailed(_ hotkey: AppHotkey, name: String) {
        let message = "Could not register \(name) hotkey \(hotkey.displayString). Try another shortcut."
        errorMessage = message
        showNotice(
            title: "Hotkey Unavailable",
            detail: message,
            systemImage: "keyboard.badge.eye",
            tone: .failure
        )
    }

    func finishAnnotatedCapture(_ image: NSImage, mode: CaptureMode) {
        finishAnnotatedCapture(image, destination: .capture(mode))
    }

    func finishAnnotatedCapture(_ image: NSImage, destination: CaptureAnnotationDestination) {
        guard !captureEditorActionInProgress else {
            return
        }
        captureEditorActionInProgress = true

        switch destination {
        case .capture(.clipboard):
            do {
                try Self.writeImageToPasteboard(image)
                let item = try? addTemporaryClipboardImage(image)
                closeCaptureEditor(animated: true)
                showNotice(
                    title: "Copied to Clipboard",
                    detail: "PNG is in the system clipboard. Use Save if you also need a file.",
                    systemImage: "doc.on.clipboard",
                    tone: .success
                )
                if let item { selectedItem = item }
            } catch {
                captureEditorActionInProgress = false
                errorMessage = error.localizedDescription
                showNotice(
                    title: "Copy Failed",
                    detail: error.localizedDescription,
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
            }
        case .capture(.save):
            do {
                let url = try ScreenshotCaptureService.save(image, in: folderURL, kind: .saved)
                let copiedToClipboard = (try? Self.writeImageToPasteboard(image)) != nil
                refresh(selecting: url)
                closeCaptureEditor(animated: true)
                showNotice(
                    title: "Saved to Library",
                    detail: copiedToClipboard
                        ? "\(url.lastPathComponent) · also copied to Clipboard."
                        : "\(url.lastPathComponent)",
                    systemImage: "tray.and.arrow.down",
                    tone: .success
                )
            } catch {
                captureEditorActionInProgress = false
                errorMessage = error.localizedDescription
                showNotice(
                    title: "Save Failed",
                    detail: error.localizedDescription,
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
            }
        case .edit(let item):
            do {
                if item.isTemporary {
                    replaceTemporaryImage(image, item: item, showsNotice: false)
                    let copiedToClipboard = (try? Self.writeImageToPasteboard(image)) != nil
                    closeCaptureEditor(animated: true)
                    showNotice(
                        title: "Screenshot Updated",
                        detail: copiedToClipboard ? "Updated in memory and copied to Clipboard." : "Updated in memory.",
                        systemImage: "square.and.arrow.down",
                        tone: .success
                    )
                } else {
                    try ImageEditingService.write(image, to: item.url)
                    let copiedToClipboard = (try? Self.writeImageToPasteboard(image)) != nil
                    refresh(selecting: item.url)
                    closeCaptureEditor(animated: true)
                    showNotice(
                        title: "Screenshot Updated",
                        detail: copiedToClipboard ? "Saved and copied to Clipboard." : "Saved.",
                        systemImage: "square.and.arrow.down",
                        tone: .success
                    )
                }
            } catch {
                captureEditorActionInProgress = false
                errorMessage = error.localizedDescription
                showNotice(
                    title: "Update Failed",
                    detail: error.localizedDescription,
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
            }
        }
    }

    @discardableResult
    func finishPreparedAnnotatedCapture(
        _ output: PreparedCaptureOutput,
        destination: CaptureAnnotationDestination
    ) -> Bool {
        guard !captureEditorActionInProgress else { return false }
        captureEditorActionInProgress = true

        switch destination {
        case .capture(.clipboard):
            do {
                try Self.writePNGDataToPasteboard(output.pngData)
                let item = try? addTemporaryClipboardImage(output.image, pngData: output.pngData)
                closeCaptureEditor(animated: true)
                showNotice(
                    title: "Copied to Clipboard",
                    detail: "PNG is ready in the system clipboard.",
                    systemImage: "checkmark.circle.fill",
                    tone: .success
                )
                if let item { selectedItem = item }
                return true
            } catch {
                captureEditorActionInProgress = false
                errorMessage = error.localizedDescription
                showNotice(
                    title: "Copy Failed",
                    detail: error.localizedDescription,
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
                return false
            }

        case .capture(.save):
            do {
                let url = try ScreenshotCaptureService.savePNGData(output.pngData, in: folderURL, kind: .saved)
                let copiedToClipboard = (try? Self.writePNGDataToPasteboard(output.pngData)) != nil
                refresh(selecting: url)
                closeCaptureEditor(animated: true)
                showNotice(
                    title: "Saved to Library",
                    detail: copiedToClipboard
                        ? "\(url.lastPathComponent) · also copied to Clipboard."
                        : "\(url.lastPathComponent)",
                    systemImage: "checkmark.circle.fill",
                    tone: .success
                )
                return true
            } catch {
                captureEditorActionInProgress = false
                errorMessage = error.localizedDescription
                showNotice(
                    title: "Save Failed",
                    detail: error.localizedDescription,
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
                return false
            }

        case .edit(let item):
            do {
                if item.isTemporary {
                    try replaceTemporaryImage(item: item, image: output.image, pngData: output.pngData)
                } else if item.url.pathExtension.lowercased() == "png" {
                    try output.pngData.write(to: item.url, options: .atomic)
                    refresh(selecting: item.url)
                } else {
                    try ImageEditingService.write(output.image, to: item.url)
                    refresh(selecting: item.url)
                }

                let copiedToClipboard = (try? Self.writePNGDataToPasteboard(output.pngData)) != nil
                closeCaptureEditor(animated: true)
                showNotice(
                    title: "Screenshot Updated",
                    detail: copiedToClipboard ? "Saved and copied to Clipboard." : "Saved.",
                    systemImage: "checkmark.circle.fill",
                    tone: .success
                )
                return true
            } catch {
                captureEditorActionInProgress = false
                errorMessage = error.localizedDescription
                showNotice(
                    title: "Update Failed",
                    detail: error.localizedDescription,
                    systemImage: "exclamationmark.triangle",
                    tone: .failure
                )
                return false
            }
        }
    }

    func reportCaptureRenderFailure(_ error: Error) {
        captureEditorActionInProgress = false
        errorMessage = error.localizedDescription
        showNotice(
            title: "Render Failed",
            detail: error.localizedDescription,
            systemImage: "exclamationmark.triangle",
            tone: .failure
        )
    }

    func image(for item: ScreenshotItem) -> NSImage? {
        if let url = temporaryImageURLs[item.id] {
            return NSImage(contentsOf: url)
        }

        return NSImage(contentsOf: item.url)
    }

    func loadImage(for item: ScreenshotItem) async -> NSImage? {
        let url = temporaryImageURLs[item.id] ?? item.url
        return await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
    }

    func thumbnail(for item: ScreenshotItem, maxPixelSize: Int) async -> NSImage? {
        let url = temporaryImageURLs[item.id] ?? item.url
        return await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }

            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
    }

    func closeCaptureEditor(animated: Bool = false) {
        guard let controller = captureEditorWindowController,
              let window = controller.window else {
            captureEditorWindowController = nil
            return
        }

        captureEditorWindowController = nil

        guard animated, window.isVisible else {
            window.close()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                window.close()
            }
        }
    }

    private func runOverlayCapture(mode: CaptureMode) {
        guard !isCapturing else {
            return
        }

        refreshRequiredPermissions()

        if !screenRecordingAccessGranted, !requestScreenRecordingAccess() {
            showScreenRecordingRequiredNotice()
            return
        }

        isCapturing = true
        errorMessage = nil
        let hiddenWindows = hideVisibleAppWindowsForCapture()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 45_000_000)

            ScreenCaptureOverlayController.shared.start { [weak self] result in
                guard let self else {
                    return
                }

                isCapturing = false

                switch result {
                case .success(let image):
                    handleCapturedImage(image, mode: mode)
                case .failure(let error) where error is CancellationError:
                    restoreAppWindows(hiddenWindows)
                    showNotice(
                        title: "Capture Cancelled",
                        detail: "No changes made",
                        systemImage: "xmark.circle",
                        tone: .neutral
                    )
                case .failure(let error):
                    restoreAppWindows(hiddenWindows)
                    errorMessage = error.localizedDescription

                    let isPermissionError: Bool
                    if case .screenRecordingPermissionRequired = error as? ScreenCaptureOverlayError {
                        isPermissionError = true
                    } else {
                        isPermissionError = false
                    }

                    showNotice(
                        title: isPermissionError ? "Screen Recording Required" : "Capture Failed",
                        detail: error.localizedDescription,
                        systemImage: isPermissionError ? "lock.rectangle" : "exclamationmark.triangle",
                        tone: .failure
                    )
                }
            }
        }
    }

    private func showScreenRecordingRequiredNotice(openSettings: Bool = false) {
        let message = ScreenCaptureOverlayError.screenRecordingPermissionRequired.localizedDescription
        errorMessage = message
        showNotice(
            title: "Screen Recording Required",
            detail: message,
            systemImage: "lock.rectangle",
            tone: .failure
        )

        if openSettings {
            openScreenRecordingSettingsURL()
        }
    }

    private func clearScreenRecordingError() {
        let permissionMessage = ScreenCaptureOverlayError.screenRecordingPermissionRequired.localizedDescription

        if errorMessage == permissionMessage {
            errorMessage = nil
        }
    }

    private var missingPermissionNames: [String] {
        var names: [String] = []

        if !screenRecordingAccessGranted {
            names.append("Screen Recording")
        }

        return names
    }

    private func handleCapturedImage(_ image: NSImage, mode: CaptureMode) {
        showCaptureEditor(image: image, mode: mode)
    }

    private func addTemporaryClipboardImage(_ image: NSImage, pngData: Data? = nil) throws -> ScreenshotItem {
        let id = "temporary-\(UUID().uuidString)"
        let now = Date()
        let dimensions = Self.imageDimensions(image: image)
        let fileName = "\(CaptureKind.clipboard.filePrefix) Screenshot \(Self.fileTimestamp()).png"
        try FileManager.default.createDirectory(at: temporaryImageDirectoryURL, withIntermediateDirectories: true)
        let temporaryURL = temporaryImageDirectoryURL.appending(path: "\(id).png")
        if let pngData {
            try pngData.write(to: temporaryURL, options: .atomic)
        } else {
            try ImageEditingService.write(image, to: temporaryURL)
        }
        let byteSize = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let item = ScreenshotItem(
            id: id,
            url: URL(string: "memory://clipboard/\(id).png")!,
            fileName: fileName,
            captureKind: .clipboard,
            createdAt: now,
            modifiedAt: now,
            byteSize: byteSize,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height
        )

        temporaryImageURLs[id] = temporaryURL
        temporaryItems.insert(item, at: 0)
        items = temporaryItems + items.filter { !$0.isTemporary }
        return item
    }

    private func replaceTemporaryImage(item: ScreenshotItem, image: NSImage, pngData: Data) throws {
        guard let index = temporaryItems.firstIndex(where: { $0.id == item.id }),
              let temporaryURL = temporaryImageURLs[item.id] else {
            throw ImageEditingError.renderFailed
        }

        try pngData.write(to: temporaryURL, options: .atomic)
        let dimensions = Self.imageDimensions(image: image)
        let byteSize = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let updatedItem = ScreenshotItem(
            id: item.id,
            url: item.url,
            fileName: item.fileName,
            captureKind: item.captureKind,
            createdAt: item.createdAt,
            modifiedAt: Date(),
            byteSize: byteSize,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height
        )
        temporaryItems[index] = updatedItem
        items = temporaryItems + items.filter { !$0.isTemporary }
        selectedItem = updatedItem
    }

    private func replaceTemporaryImage(_ image: NSImage, item: ScreenshotItem, showsNotice: Bool = true) {
        guard let index = temporaryItems.firstIndex(where: { $0.id == item.id }),
              let temporaryURL = temporaryImageURLs[item.id] else {
            return
        }

        do {
            try ImageEditingService.write(image, to: temporaryURL)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let dimensions = Self.imageDimensions(image: image)
        let byteSize = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let updatedItem = ScreenshotItem(
            id: item.id,
            url: item.url,
            fileName: item.fileName,
            captureKind: item.captureKind,
            createdAt: item.createdAt,
            modifiedAt: Date(),
            byteSize: byteSize,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height
        )

        temporaryItems[index] = updatedItem
        items = temporaryItems + items.filter { !$0.isTemporary }
        selectedItem = updatedItem
        guard showsNotice else {
            return
        }

        showNotice(
            title: "Temporary Image Updated",
            detail: "It is still in memory only.",
            systemImage: "memorychip",
            tone: .success
        )
    }

    private func showCaptureEditor(image: NSImage, mode: CaptureMode) {
        showCaptureEditor(image: image, destination: .capture(mode))
    }

    private func showCaptureEditor(image: NSImage, destination: CaptureAnnotationDestination) {
        closeCaptureEditor()
        captureEditorActionInProgress = false

        let session = CaptureAnnotationSession(image: image, destination: destination)
        let contentView = CaptureAnnotationView(store: self, session: session)
        let hostingController = NSHostingController(rootView: contentView)
        let window = CaptureAnnotationWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Annotate"
        window.titleVisibility = .hidden
        window.identifier = NSUserInterfaceItemIdentifier("ScreenshotManager.AnnotationWindow")
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // Keep the full-size transparent titlebar, but never let drags inside the
        // annotation canvas/crop handles move the whole window.
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.minSize = NSSize(width: 980, height: 620)
        window.contentViewController = hostingController
        window.onCancel = { [weak self] in
            self?.closeCaptureEditor(animated: true)
        }
        window.center()
        window.isReleasedWhenClosed = true
        window.isRestorable = false

        let controller = NSWindowController(window: window)
        captureEditorWindowController = controller
        showWindowWithEntranceAnimation(controller)
    }

    private func showWindowWithEntranceAnimation(_ controller: NSWindowController) {
        guard let window = controller.window else {
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        window.alphaValue = 0

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1
        }
    }

    private static func scaledWindowFrame(from frame: NSRect, scale: CGFloat, yOffset: CGFloat) -> NSRect {
        let width = frame.width * scale
        let height = frame.height * scale

        return NSRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2 + yOffset,
            width: width,
            height: height
        )
    }

    private func hideVisibleAppWindowsForCapture() -> [NSWindow] {
        let windows = NSApp.windows.filter { window in
            window.isVisible && window.level == .normal
        }
        windows.forEach { $0.orderOut(nil) }
        return windows
    }

    private func restoreAppWindows(_ windows: [NSWindow]) {
        guard !windows.isEmpty else {
            return
        }

        windows.forEach { $0.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showNotice(title: String, detail: String, systemImage: String, tone: CaptureNotice.Tone) {
        noticeClearTask?.cancel()
        captureNotice = CaptureNotice(title: title, detail: detail, systemImage: systemImage, tone: tone)

        noticeClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            guard !Task.isCancelled else {
                return
            }

            captureNotice = nil
        }
    }

    private static func importDroppedProviders(
        _ providers: [NSItemProvider],
        into folderURL: URL,
        imageExtensions: Set<String>
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var importedURLs: [URL] = []

        for provider in providers {
            guard let payload = try await droppedImagePayload(from: provider, imageExtensions: imageExtensions) else {
                continue
            }

            let destinationURL = uniqueImportURL(
                proposedName: payload.fileName,
                fallbackExtension: payload.fileExtension,
                in: folderURL
            )

            switch payload.source {
            case .file(let sourceURL):
                let didAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }

                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            case .data(let data):
                try data.write(to: destinationURL, options: .atomic)
            }

            importedURLs.append(destinationURL)
        }

        return importedURLs
    }

    private static func droppedImagePayload(
        from provider: NSItemProvider,
        imageExtensions: Set<String>
    ) async throws -> DroppedImagePayload? {
        for urlTypeIdentifier in [UTType.fileURL.identifier, UTType.url.identifier] {
            guard provider.hasItemConformingToTypeIdentifier(urlTypeIdentifier),
                  let fileURL = try await droppedURL(from: provider, typeIdentifier: urlTypeIdentifier),
                  fileURL.isFileURL else {
                continue
            }

            let fileExtension = fileURL.pathExtension.lowercased()

            if imageExtensions.contains(fileExtension) {
                return DroppedImagePayload(
                    source: .file(fileURL),
                    fileName: fileURL.lastPathComponent,
                    fileExtension: fileExtension
                )
            }
        }

        for type in imageDropTypes {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else {
                continue
            }

            if let fileData = try? await droppedFileRepresentationData(from: provider, typeIdentifier: type.identifier),
               !fileData.data.isEmpty {
                return DroppedImagePayload(
                    source: .data(fileData.data),
                    fileName: fileData.fileName ?? provider.suggestedName,
                    fileExtension: fileData.fileExtension ?? type.fileExtension
                )
            }

            if let data = try? await droppedDataRepresentation(from: provider, typeIdentifier: type.identifier),
               !data.isEmpty {
                return DroppedImagePayload(
                    source: .data(data),
                    fileName: provider.suggestedName,
                    fileExtension: type.fileExtension
                )
            }
        }

        return nil
    }

    private static func droppedURL(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let url: URL?

                switch item {
                case let fileURL as URL:
                    url = fileURL
                case let fileURL as NSURL:
                    url = fileURL as URL
                case let data as Data:
                    url = URL(dataRepresentation: data, relativeTo: nil)
                case let string as String:
                    if let parsedURL = URL(string: string), parsedURL.isFileURL {
                        url = parsedURL
                    } else {
                        url = URL(fileURLWithPath: string)
                    }
                default:
                    url = nil
                }

                continuation.resume(returning: url)
            }
        }
    }

    private static func droppedFileRepresentationData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> DroppedFileData? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: DroppedFileData(
                        data: data,
                        fileName: url.lastPathComponent,
                        fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension.lowercased()
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func droppedDataRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    private static func uniqueImportURL(proposedName: String?, fallbackExtension: String, in folderURL: URL) -> URL {
        let fallbackName = "Imported Image \(Self.fileTimestamp())"
        let rawName = (proposedName?.isEmpty == false ? proposedName : fallbackName) ?? fallbackName
        let proposedURL = URL(filePath: rawName)
        let proposedExtension = proposedURL.pathExtension.isEmpty ? fallbackExtension : proposedURL.pathExtension
        let baseName = proposedURL.deletingPathExtension().lastPathComponent
        let safeBaseName = sanitizedFileStem(baseName.isEmpty ? fallbackName : baseName)
        let safeExtension = sanitizedFileExtension(proposedExtension.isEmpty ? fallbackExtension : proposedExtension)

        var candidate = folderURL.appending(path: "\(safeBaseName).\(safeExtension)")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folderURL.appending(path: "\(safeBaseName) \(suffix).\(safeExtension)")
            suffix += 1
        }

        return candidate
    }

    private static func sanitizedFileStem(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = value.components(separatedBy: invalidCharacters)
        let sanitized = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Imported Image \(fileTimestamp())" : sanitized
    }

    private static func sanitizedFileExtension(_ value: String) -> String {
        let sanitized = value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return sanitized.isEmpty ? "png" : String(sanitized)
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    private static func defaultScreenshotFolder() -> URL {
        let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")

        return applicationSupportURL
            .appending(path: "Screenshot Manager", directoryHint: .isDirectory)
            .appending(path: "Captures", directoryHint: .isDirectory)
    }

    private static func isDesktopFolder(_ url: URL) -> Bool {
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop")
        return url.standardizedFileURL.path(percentEncoded: false) == desktopURL.standardizedFileURL.path(percentEncoded: false)
    }

    nonisolated private static func scanFolder(_ folderURL: URL, imageExtensions: Set<String>) throws -> [ScreenshotItem] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        return urls.compactMap { url in
            guard imageExtensions.contains(url.pathExtension.lowercased()) else {
                return nil
            }

            guard let resourceValues = try? url.resourceValues(forKeys: keys),
                  resourceValues.isRegularFile == true else {
                return nil
            }

            let dimensions = imageDimensions(url: url)
            let createdAt = resourceValues.creationDate ?? resourceValues.contentModificationDate ?? .distantPast
            let modifiedAt = resourceValues.contentModificationDate ?? createdAt
            let byteSize = Int64(resourceValues.fileSize ?? 0)

            return ScreenshotItem(
                id: url.path(percentEncoded: false),
                url: url,
                fileName: url.lastPathComponent,
                captureKind: CaptureKind.detect(from: url.lastPathComponent),
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                byteSize: byteSize,
                pixelWidth: dimensions.width,
                pixelHeight: dimensions.height
            )
        }
        .sorted { left, right in
            left.createdAt > right.createdAt
        }
    }

    nonisolated private static func imageDimensions(url: URL) -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (0, 0)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return (width, height)
    }

    private static func imageDimensions(image: NSImage) -> (width: Int, height: Int) {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return (cgImage.width, cgImage.height)
        }

        let bestRepresentation = image.representations.max { left, right in
            (left.pixelsWide * left.pixelsHigh) < (right.pixelsWide * right.pixelsHigh)
        }

        return (
            max(bestRepresentation?.pixelsWide ?? Int(image.size.width), 0),
            max(bestRepresentation?.pixelsHigh ?? Int(image.size.height), 0)
        )
    }

    private static let imageDropTypes: [DroppedImageType] = [
        DroppedImageType(identifier: UTType.png.identifier, fileExtension: "png"),
        DroppedImageType(identifier: UTType.jpeg.identifier, fileExtension: "jpg"),
        DroppedImageType(identifier: UTType.heic.identifier, fileExtension: "heic"),
        DroppedImageType(identifier: UTType.heif.identifier, fileExtension: "heif"),
        DroppedImageType(identifier: UTType.tiff.identifier, fileExtension: "tiff"),
        DroppedImageType(identifier: "org.webmproject.webp", fileExtension: "webp"),
        DroppedImageType(identifier: UTType.image.identifier, fileExtension: "png")
    ]
}

private struct DroppedImageType {
    let identifier: String
    let fileExtension: String
}

private final class CaptureAnnotationWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == 53 {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

private struct DroppedImagePayload {
    enum Source {
        case file(URL)
        case data(Data)
    }

    let source: Source
    let fileName: String?
    let fileExtension: String
}

private struct DroppedFileData {
    let data: Data
    let fileName: String?
    let fileExtension: String?
}

private enum ClipboardImageError: LocalizedError {
    case encodeFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "Could not encode the edited image for the clipboard."
        case .writeFailed:
            return "macOS did not accept the edited image into the clipboard."
        }
    }
}

enum CaptureMode {
    case clipboard
    case save
}

struct CaptureAnnotationSession: Identifiable {
    let id = UUID()
    let image: NSImage
    let destination: CaptureAnnotationDestination
}

enum CaptureAnnotationDestination {
    case capture(CaptureMode)
    case edit(ScreenshotItem)
}

struct CaptureNotice: Identifiable, Equatable {
    enum Tone: Equatable {
        case success
        case neutral
        case failure
    }

    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
    let tone: Tone
}
