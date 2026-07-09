import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenCaptureOverlayController {
    static let shared = ScreenCaptureOverlayController()

    private var windows: [ScreenCaptureOverlayWindow] = []
    private var completion: ((Result<NSImage, Error>) -> Void)?
    private var keyMonitor: Any?
    private var isFinishing = false

    private init() {}

    static var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func start(completion: @escaping (Result<NSImage, Error>) -> Void) {
        cancel(invokeCompletion: false)
        isFinishing = false

        self.completion = completion
        installKeyMonitor()
        let windowTargets = Self.captureWindowTargets()
        windows = NSScreen.screens.map { screen in
            let frozenSnapshot = Self.frozenSnapshot(for: screen)
            let window = ScreenCaptureOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            let overlayView = ScreenCaptureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            overlayView.isInteractionEnabled = true
            overlayView.windowTargets = windowTargets
            overlayView.frozenSnapshot = frozenSnapshot
            overlayView.pixelSampler = frozenSnapshot?.pixelSampler
            overlayView.onComplete = { [weak self, weak window] localRect in
                guard let window else {
                    self?.finish(.failure(ScreenCaptureOverlayError.captureFailed))
                    return
                }

                self?.capture(localRect: localRect, in: window)
            }
            overlayView.onCancel = { [weak self] in
                self?.finish(.failure(CancellationError()))
            }

            window.contentView = overlayView
            return window
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { window in
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
    }

    func cancel() {
        cancel(invokeCompletion: false)
    }

    private func cancel(invokeCompletion: Bool) {
        removeKeyMonitor()
        deactivateOverlayViews()
        windows.forEach { $0.orderOut(nil) }
        windows = []

        guard invokeCompletion else {
            completion = nil
            isFinishing = false
            return
        }

        let completion = completion
        self.completion = nil
        isFinishing = false
        completion?(.failure(CancellationError()))
    }

    private func capture(localRect: NSRect, in window: NSWindow) {
        guard !isFinishing else {
            return
        }

        let frozenImage = (window.contentView as? ScreenCaptureOverlayView)?
            .frozenSnapshot?
            .croppedImage(localRect: localRect)
        let targetScreen = window.screen
        let globalRect = NSRect(
            x: window.frame.minX + localRect.minX,
            y: window.frame.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )

        // Stop interaction/draw side-effects before tearing windows down.
        // Pending CA display commits can still call draw(_:) after orderOut.
        deactivateOverlayViews()
        removeKeyMonitor()
        windows.forEach { $0.orderOut(nil) }
        windows = []

        if let frozenImage {
            finish(.success(frozenImage))
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)

            do {
                let image = try await Self.captureImage(
                    localRect: localRect,
                    screen: targetScreen,
                    fallbackGlobalRect: globalRect
                )
                finish(.success(image))
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<NSImage, Error>) {
        guard !isFinishing else {
            return
        }
        isFinishing = true

        removeKeyMonitor()
        deactivateOverlayViews()
        windows.forEach { $0.orderOut(nil) }
        windows = []

        let completion = completion
        self.completion = nil
        isFinishing = false
        completion?(result)
    }

    private func deactivateOverlayViews() {
        for window in windows {
            (window.contentView as? ScreenCaptureOverlayView)?.isInteractionEnabled = false
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.completion != nil,
                  event.keyCode == 53 else {
                return event
            }

            self.finish(.failure(CancellationError()))
            return nil
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else {
            return
        }

        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private static func coreGraphicsRect(from rect: NSRect) -> CGRect {
        let desktopFrame = NSScreen.screens.reduce(NSRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }

        return CGRect(
            x: rect.minX,
            y: desktopFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func captureImage(localRect: NSRect, screen: NSScreen?, fallbackGlobalRect: NSRect) async throws -> NSImage {
        guard hasScreenCaptureAccess else {
            throw ScreenCaptureOverlayError.screenRecordingPermissionRequired
        }

        if #available(macOS 14.0, *), let screen {
            do {
                return try await screenCaptureKitImage(localRect: localRect, screen: screen)
            } catch {
                guard hasScreenCaptureAccess else {
                    throw ScreenCaptureOverlayError.screenRecordingPermissionRequired
                }

                return try coreGraphicsImage(globalRect: fallbackGlobalRect)
            }
        }

        return try coreGraphicsImage(globalRect: fallbackGlobalRect)
    }

    private static func frozenSnapshot(for screen: NSScreen) -> FrozenScreenSnapshot? {
        if let displayID = displayID(for: screen),
           let cgImage = CGDisplayCreateImage(displayID) {
            return FrozenScreenSnapshot(
                cgImage: cgImage,
                screenSize: screen.frame.size,
                pixelSampler: ScreenPixelSampler(cgImage: cgImage)
            )
        }

        let captureRect = coreGraphicsRect(from: screen.frame)

        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return nil
        }

        return FrozenScreenSnapshot(
            cgImage: cgImage,
            screenSize: screen.frame.size,
            pixelSampler: ScreenPixelSampler(cgImage: cgImage)
        )
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private static func coreGraphicsImage(globalRect: NSRect) throws -> NSImage {
        let captureRect = coreGraphicsRect(from: globalRect)

        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw ScreenCaptureOverlayError.captureFailed
        }

        return NSImage(cgImage: cgImage, size: globalRect.size)
    }

    @available(macOS 14.0, *)
    private static func screenCaptureKitImage(localRect: NSRect, screen: NSScreen) async throws -> NSImage {
        let content = try await SCShareableContent.current
        let displayID = displayID(for: screen)
        let displayForScreen = displayID.flatMap { id in
            content.displays.first { $0.displayID == id }
        }

        guard let display = displayForScreen ?? content.displays.first(where: { $0.frame.intersects(screen.frame) }) else {
            throw ScreenCaptureOverlayError.captureFailed
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentAppWindows = content.windows.filter { window in
            window.owningApplication?.processID == currentPID
        }
        let filter = SCContentFilter(display: display, excludingWindows: currentAppWindows)
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let scale = screen.backingScaleFactor
        let sourceRect = CGRect(
            x: localRect.minX,
            y: screen.frame.height - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        ).integral
        let outputWidth = max(1, Int(round(sourceRect.width * scale)))
        let outputHeight = max(1, Int(round(sourceRect.height * scale)))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = outputWidth
        configuration.height = outputHeight
        configuration.scalesToFit = false
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: image, size: localRect.size)
    }

    private static func captureWindowTargets() -> [CaptureWindowTarget] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier

        return windowInfo.compactMap { info in
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            guard ownerPID != currentPID else {
                return nil
            }

            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else {
                return nil
            }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.05 else {
                return nil
            }

            guard let boundsValue = info[kCGWindowBounds as String],
                  let cgBounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary) else {
                return nil
            }

            let frame = appKitRect(fromCoreGraphicsWindowBounds: cgBounds)
            guard frame.width >= 80, frame.height >= 60 else {
                return nil
            }

            let title = info[kCGWindowName as String] as? String
            let appName = info[kCGWindowOwnerName as String] as? String
            return CaptureWindowTarget(frame: frame, title: title?.isEmpty == false ? title : appName)
        }
    }

    private static func appKitRect(fromCoreGraphicsWindowBounds rect: CGRect) -> NSRect {
        let desktopFrame = NSScreen.screens.reduce(NSRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }

        return NSRect(
            x: rect.minX,
            y: desktopFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

}

fileprivate struct CaptureWindowTarget {
    let frame: NSRect
    let title: String?
}

fileprivate struct FrozenScreenSnapshot {
    let cgImage: CGImage
    let image: NSImage
    let screenSize: NSSize
    let pixelSampler: ScreenPixelSampler?

    init(cgImage: CGImage, screenSize: NSSize, pixelSampler: ScreenPixelSampler?) {
        self.cgImage = cgImage
        self.image = NSImage(cgImage: cgImage, size: screenSize)
        self.screenSize = screenSize
        self.pixelSampler = pixelSampler
    }

    func croppedImage(localRect: NSRect) -> NSImage? {
        guard screenSize.width > 0, screenSize.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / screenSize.width
        let scaleY = CGFloat(cgImage.height) / screenSize.height
        let pixelRect = CGRect(
            x: localRect.minX * scaleX,
            y: (screenSize.height - localRect.maxY) * scaleY,
            width: localRect.width * scaleX,
            height: localRect.height * scaleY
        ).integral
        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        )
        let boundedRect = pixelRect.intersection(imageBounds)

        guard !boundedRect.isNull,
              !boundedRect.isEmpty,
              let cropped = cgImage.cropping(to: boundedRect) else {
            return nil
        }

        return NSImage(cgImage: cropped, size: localRect.size)
    }
}

fileprivate struct PixelSample {
    let x: Int
    let y: Int
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hexString: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var rgbString: String {
        "RGB \(red) \(green) \(blue)"
    }

    var color: NSColor {
        NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

fileprivate final class ScreenPixelSampler {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int
    private let bytesPerRow: Int

    init?(cgImage: CGImage) {
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        let imageBytesPerRow = max(imageWidth * 4, 4)

        guard imageWidth > 0, imageHeight > 0 else {
            return nil
        }

        var normalizedPixels = [UInt8](repeating: 0, count: imageHeight * imageBytesPerRow)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        let didDraw = normalizedPixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: imageBytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }

        guard didDraw else {
            return nil
        }

        width = imageWidth
        height = imageHeight
        bytesPerRow = imageBytesPerRow
        pixels = normalizedPixels
    }

    func sample(at localPoint: NSPoint, in bounds: NSRect) -> PixelSample? {
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(width) / bounds.width
        let scaleY = CGFloat(height) / bounds.height
        let pixelX = clamp(Int(floor(localPoint.x * scaleX)), lower: 0, upper: width - 1)
        let pixelY = clamp(Int(floor((bounds.height - localPoint.y) * scaleY)), lower: 0, upper: height - 1)
        let offset = pixelY * bytesPerRow + pixelX * 4

        guard offset + 2 < pixels.count else {
            return nil
        }

        return PixelSample(
            x: pixelX,
            y: pixelY,
            red: pixels[offset],
            green: pixels[offset + 1],
            blue: pixels[offset + 2]
        )
    }

    private func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}

final class ScreenCaptureOverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        configure()
    }

    convenience init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool,
        screen: NSScreen
    ) {
        self.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        setFrame(screen.frame, display: true)
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hasShadow = false
        isRestorable = false
    }
}

final class ScreenCaptureOverlayView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?
    /// When false, skip interaction and text HUD drawing. Prevents CoreText
    /// crashes from late display commits after the overlay is torn down.
    var isInteractionEnabled = true
    fileprivate var windowTargets: [CaptureWindowTarget] = []
    fileprivate var frozenSnapshot: FrozenScreenSnapshot?
    fileprivate var pixelSampler: ScreenPixelSampler?

    private var dragStart: NSPoint?
    private var selectionRect: NSRect = .zero
    private var hoveredWindowTarget: CaptureWindowTarget?
    private var pressedWindowTarget: CaptureWindowTarget?
    private var cursorPoint: NSPoint?
    private var currentPixelSample: PixelSample?
    private var copyFeedbackText: String?
    private var trackingArea: NSTrackingArea?
    private var didComplete = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        guard isInteractionEnabled, !didComplete else {
            return
        }

        let point = event.locationInWindow
        updateInspector(at: point)
        updateHoveredWindow(at: point)
        updateCursor(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        guard isInteractionEnabled, !didComplete else {
            return
        }

        hoveredWindowTarget = nil
        cursorPoint = nil
        currentPixelSample = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled, !didComplete else {
            return
        }

        let point = event.locationInWindow
        updateInspector(at: point)
        updateHoveredWindow(at: point)

        dragStart = point
        pressedWindowTarget = hoveredWindowTarget
        selectionRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractionEnabled, !didComplete, let dragStart else {
            return
        }

        let currentPoint = event.locationInWindow
        updateInspector(at: currentPoint)

        let distance = hypot(currentPoint.x - dragStart.x, currentPoint.y - dragStart.y)

        if distance > 4 {
            pressedWindowTarget = nil
            selectionRect = normalizedRect(from: dragStart, to: currentPoint)
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractionEnabled, !didComplete else {
            return
        }

        guard let dragStart else {
            completeCapture(with: nil)
            return
        }

        let endPoint = event.locationInWindow
        let distance = hypot(endPoint.x - dragStart.x, endPoint.y - dragStart.y)
        selectionRect = normalizedRect(from: dragStart, to: endPoint)
        self.dragStart = nil

        if distance >= 8, selectionRect.width >= 8, selectionRect.height >= 8 {
            completeCapture(with: selectionRect)
            return
        }

        if let target = pressedWindowTarget ?? target(at: endPoint),
           let rect = localCaptureRect(for: target) {
            completeCapture(with: rect)
            return
        }

        completeCapture(with: nil)
    }

    override func keyDown(with event: NSEvent) {
        guard isInteractionEnabled, !didComplete else {
            return
        }

        if event.keyCode == 53 {
            completeCapture(with: nil)
        } else if event.keyCode == 36 || event.keyCode == 49 || event.keyCode == 76 {
            if !completeCurrentSelectionOrHover() {
                super.keyDown(with: event)
            }
        } else if event.keyCode == 48 {
            copyCurrentColor()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if let frozenImage = frozenSnapshot?.image {
            NSGraphicsContext.current?.imageInterpolation = .high
            frozenImage.draw(
                in: bounds,
                from: NSRect(origin: .zero, size: frozenImage.size),
                operation: .copy,
                fraction: 1
            )
        } else {
            NSColor.black.setFill()
            bounds.fill()
        }

        NSColor.black.withAlphaComponent(0.46).setFill()
        bounds.fill()

        // Late CA commits after teardown must not run CoreText HUD layout —
        // that path crashed with nil font insertion (see DiagnosticReports).
        guard isInteractionEnabled, !didComplete else {
            return
        }

        if selectionRect != .zero {
            drawSelection(selectionRect, title: nil)
        } else if let hoveredWindowTarget,
                  let rect = localCaptureRect(for: hoveredWindowTarget) {
            drawSelection(rect, title: hoveredWindowTarget.title)
        }

        drawCursorGuide()
        drawInspectorHUD()
        drawHint()
    }

    private func completeCapture(with rect: NSRect?) {
        guard !didComplete else {
            return
        }
        didComplete = true
        isInteractionEnabled = false

        if let rect {
            onComplete?(rect)
        } else {
            onCancel?()
        }
    }

    private func updateInspector(at point: NSPoint) {
        cursorPoint = point
        currentPixelSample = pixelSampler?.sample(at: point, in: bounds)
        needsDisplay = true
    }

    private func updateHoveredWindow(at point: NSPoint) {
        guard dragStart == nil else {
            return
        }

        hoveredWindowTarget = target(at: point)
        needsDisplay = true
    }

    private func target(at localPoint: NSPoint) -> CaptureWindowTarget? {
        guard let window else {
            return nil
        }

        let globalPoint = NSPoint(
            x: window.frame.minX + localPoint.x,
            y: window.frame.minY + localPoint.y
        )

        return windowTargets.first { target in
            target.frame.contains(globalPoint) && target.frame.intersects(window.frame)
        }
    }

    private func localCaptureRect(for target: CaptureWindowTarget) -> NSRect? {
        guard let window else {
            return nil
        }

        let localRect = NSRect(
            x: target.frame.minX - window.frame.minX,
            y: target.frame.minY - window.frame.minY,
            width: target.frame.width,
            height: target.frame.height
        )
        let clipped = localRect.intersection(bounds)

        guard !clipped.isNull, clipped.width >= 8, clipped.height >= 8 else {
            return nil
        }

        return clipped
    }

    private func completeCurrentSelectionOrHover() -> Bool {
        if selectionRect.width >= 8, selectionRect.height >= 8 {
            completeCapture(with: selectionRect)
            return true
        }

        if let hoveredWindowTarget,
           let rect = localCaptureRect(for: hoveredWindowTarget) {
            completeCapture(with: rect)
            return true
        }

        if let cursorPoint,
           let target = target(at: cursorPoint),
           let rect = localCaptureRect(for: target) {
            completeCapture(with: rect)
            return true
        }

        return false
    }

    private func drawSelection(_ rect: NSRect, title: String?) {
        let selectionPath = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        selectionPath.fill()

        NSColor.controlAccentColor.withAlphaComponent(0.98).setStroke()
        selectionPath.lineWidth = 2
        selectionPath.stroke()

        if rect.width >= 30, rect.height >= 30 {
            drawSelectionSize(rect)
        }

        guard let title, !title.isEmpty else {
            return
        }
        drawWindowTitle(title, in: rect)
    }

    private func drawWindowTitle(_ title: String, in rect: NSRect) {
        let attributes = OverlayTextStyle.attributes(
            font: OverlayTextStyle.windowTitleFont,
            color: OverlayTextStyle.primaryColor
        )
        let titleSize = OverlayTextStyle.measure(title, attributes: attributes)
        let titleRect = NSRect(
            x: rect.minX + 10,
            y: min(rect.maxY - titleSize.height - 10, bounds.maxY - titleSize.height - 14),
            width: min(titleSize.width, max(40, rect.width - 20)),
            height: titleSize.height
        )
        OverlayTextStyle.draw(title, in: titleRect, attributes: attributes)
    }

    private func drawSelectionSize(_ rect: NSRect) {
        let scale = window?.screen?.backingScaleFactor ?? 1
        let text = "\(Int(round(rect.width * scale))) x \(Int(round(rect.height * scale)))"
        let attributes = OverlayTextStyle.attributes(
            font: OverlayTextStyle.selectionSizeFont,
            color: OverlayTextStyle.primaryColor
        )
        let size = OverlayTextStyle.measure(text, attributes: attributes)
        let bubble = NSRect(
            x: min(max(rect.maxX - size.width - 18, bounds.minX + 10), bounds.maxX - size.width - 18),
            y: max(rect.minY + 10, bounds.minY + 10),
            width: size.width + 12,
            height: size.height + 7
        )

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 5, yRadius: 5).fill()
        OverlayTextStyle.draw(text, at: NSPoint(x: bubble.minX + 6, y: bubble.minY + 4), attributes: attributes)
    }

    private func drawCursorGuide() {
        guard let cursorPoint else {
            return
        }

        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: cursorPoint.x - 18, y: cursorPoint.y))
        guide.line(to: NSPoint(x: cursorPoint.x - 5, y: cursorPoint.y))
        guide.move(to: NSPoint(x: cursorPoint.x + 5, y: cursorPoint.y))
        guide.line(to: NSPoint(x: cursorPoint.x + 18, y: cursorPoint.y))
        guide.move(to: NSPoint(x: cursorPoint.x, y: cursorPoint.y - 18))
        guide.line(to: NSPoint(x: cursorPoint.x, y: cursorPoint.y - 5))
        guide.move(to: NSPoint(x: cursorPoint.x, y: cursorPoint.y + 5))
        guide.line(to: NSPoint(x: cursorPoint.x, y: cursorPoint.y + 18))

        NSColor.white.withAlphaComponent(0.72).setStroke()
        guide.lineWidth = 1
        guide.stroke()

        NSColor.black.withAlphaComponent(0.8).setStroke()
        let dot = NSBezierPath(ovalIn: NSRect(x: cursorPoint.x - 2.5, y: cursorPoint.y - 2.5, width: 5, height: 5))
        dot.lineWidth = 1
        dot.stroke()
    }

    private func drawInspectorHUD() {
        guard let cursorPoint, let sample = currentPixelSample else {
            return
        }

        let titleAttributes = OverlayTextStyle.attributes(
            font: OverlayTextStyle.hudTitleFont,
            color: OverlayTextStyle.primaryColor
        )
        let detailAttributes = OverlayTextStyle.attributes(
            font: OverlayTextStyle.hudDetailFont,
            color: OverlayTextStyle.secondaryColor
        )
        let titleText = copyFeedbackText ?? sample.hexString
        let detailText = "\(sample.rgbString)   X \(sample.x) Y \(sample.y)"
        let titleSize = OverlayTextStyle.measure(titleText, attributes: titleAttributes)
        let detailSize = OverlayTextStyle.measure(detailText, attributes: detailAttributes)
        let hudWidth = max(titleSize.width, detailSize.width) + 46
        let hudHeight: CGFloat = 46
        let hudRect = inspectorRect(near: cursorPoint, width: hudWidth, height: hudHeight)

        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: hudRect, xRadius: 7, yRadius: 7).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        NSBezierPath(roundedRect: hudRect, xRadius: 7, yRadius: 7).stroke()

        let swatchRect = NSRect(x: hudRect.minX + 10, y: hudRect.minY + 13, width: 20, height: 20)
        sample.color.setFill()
        NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).fill()
        NSColor.white.withAlphaComponent(0.32).setStroke()
        NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).stroke()

        OverlayTextStyle.draw(titleText, at: NSPoint(x: hudRect.minX + 38, y: hudRect.minY + 24), attributes: titleAttributes)
        OverlayTextStyle.draw(detailText, at: NSPoint(x: hudRect.minX + 38, y: hudRect.minY + 9), attributes: detailAttributes)
    }

    private func inspectorRect(near point: NSPoint, width: CGFloat, height: CGFloat) -> NSRect {
        var x = point.x + 18
        var y = point.y + 18

        if x + width > bounds.maxX - 12 {
            x = point.x - width - 18
        }

        if y + height > bounds.maxY - 12 {
            y = point.y - height - 18
        }

        return NSRect(
            x: max(bounds.minX + 12, min(x, bounds.maxX - width - 12)),
            y: max(bounds.minY + 12, min(y, bounds.maxY - height - 12)),
            width: width,
            height: height
        )
    }

    private func copyCurrentColor() {
        guard let sample = currentPixelSample else {
            return
        }

        let text = sample.hexString
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copyFeedbackText = "Copied \(text)"
        needsDisplay = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
            guard self?.copyFeedbackText == "Copied \(text)" else {
                return
            }

            self?.copyFeedbackText = nil
            self?.needsDisplay = true
        }
    }

    private func drawHint() {
        let text = "Drag to capture   Click window   Tab copies color   Esc cancels"
        let attributes = OverlayTextStyle.attributes(
            font: OverlayTextStyle.hintFont,
            color: OverlayTextStyle.hintColor
        )
        let size = OverlayTextStyle.measure(text, attributes: attributes)
        let backgroundRect = NSRect(
            x: bounds.midX - (size.width + 24) / 2,
            y: bounds.maxY - size.height - 38,
            width: size.width + 24,
            height: size.height + 12
        )
        NSColor.black.withAlphaComponent(0.58).setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: 7, yRadius: 7).fill()
        OverlayTextStyle.draw(
            text,
            at: NSPoint(
                x: backgroundRect.minX + 12,
                y: backgroundRect.minY + 6
            ),
            attributes: attributes
        )
    }

    private func normalizedRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }

    private func updateCursor(at point: NSPoint) {
        NSCursor.crosshair.set()
    }
}

/// Text helpers for the capture overlay.
///
/// Crash reports showed SIGABRT in CoreText `TAttributes::ApplyFont` while measuring
/// `NSAttributedString` built with `NSFont.monospacedSystemFont` during `draw(_:)`.
/// That path intermittently inserts a nil CTFont. We pin concrete faces (Menlo /
/// materialized system fonts) once and measure/draw via NSString attributes instead.
fileprivate enum OverlayTextStyle {
    static var primaryColor: NSColor { NSColor.white.withAlphaComponent(0.96) }
    static var secondaryColor: NSColor { NSColor.white.withAlphaComponent(0.74) }
    static var hintColor: NSColor { NSColor.white.withAlphaComponent(0.88) }

    static var hudTitleFont: NSFont { resolvedMonospaced(size: 12, weight: .semibold) }
    static var hudDetailFont: NSFont { resolvedMonospaced(size: 11, weight: .regular) }
    static var selectionSizeFont: NSFont { resolvedMonospaced(size: 11, weight: .medium) }
    static var windowTitleFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .semibold) }
    static var hintFont: NSFont { NSFont.systemFont(ofSize: 13, weight: .medium) }

    static func attributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color
        ]
    }

    static func measure(_ string: String, attributes: [NSAttributedString.Key: Any]) -> NSSize {
        (string as NSString).size(withAttributes: attributes)
    }

    static func draw(_ string: String, at point: NSPoint, attributes: [NSAttributedString.Key: Any]) {
        (string as NSString).draw(at: point, withAttributes: attributes)
    }

    static func draw(_ string: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        (string as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static func resolvedMonospaced(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        // Prefer a concrete installed face — always resolves to a real CTFont on macOS.
        if weight >= .semibold {
            if let bold = NSFont(name: "Menlo-Bold", size: size) {
                return bold
            }
        } else if let menlo = NSFont(name: "Menlo", size: size) ?? NSFont(name: "Menlo-Regular", size: size) {
            return menlo
        }

        let systemMono = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        if let concrete = NSFont(descriptor: systemMono.fontDescriptor, size: size) {
            return concrete
        }

        return NSFont.userFixedPitchFont(ofSize: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
}

enum ScreenCaptureOverlayError: LocalizedError {
    case captureFailed
    case screenRecordingPermissionRequired

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "Could not capture the selected area."
        case .screenRecordingPermissionRequired:
            return "Screen Recording access is not active. Allow Screenshot Manager in System Settings, then quit and reopen the app."
        }
    }
}
