import AppKit
import SwiftUI
import Vision

struct ImageEditorView: View {
    @ObservedObject var store: ScreenshotStore
    let item: ScreenshotItem

    @Environment(\.dismiss) private var dismiss
    @State private var workingImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit Image")
                        .font(AppTypography.paneTitle)
                    Text(item.fileName)
                        .font(AppTypography.helper)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(AppTheme.toolbarBackground)

            Divider()

            HStack(spacing: 0) {
                ZStack {
                    AppTheme.contentBackground

                    if let workingImage {
                        Image(nsImage: workingImage)
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                    } else {
                        ContentUnavailableView("Image unavailable", systemImage: "photo")
                    }
                }
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                editorControls
                    .frame(width: 250)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(AppTheme.windowBackground)
        .onExitCommand {
            dismiss()
        }
        .task(id: item.id) {
            workingImage = await store.loadImage(for: item)
        }
    }

    private var editorControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Adjust")
                .font(AppTypography.sectionTitle)

            HStack {
                Button {
                    transform { ImageEditingService.rotate($0, clockwise: false) }
                } label: {
                    Label("Left", systemImage: "rotate.left")
                }

                Button {
                    transform { ImageEditingService.rotate($0, clockwise: true) }
                } label: {
                    Label("Right", systemImage: "rotate.right")
                }
            }

            Button {
                transform(ImageEditingService.flipHorizontal)
            } label: {
                Label("Flip Horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Divider()

            Button {
                guard let workingImage else {
                    return
                }
                store.copyEditedImage(workingImage)
            } label: {
                Label("Copy Result", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                guard let workingImage else {
                    return
                }
                store.saveEditedCopy(workingImage, source: item)
            } label: {
                Label("Save Copy", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                guard let workingImage else {
                    return
                }
                store.replaceImage(workingImage, item: item)
            } label: {
                Label("Replace Original", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(18)
        .background(AppTheme.sidebarBackground)
    }

    private func transform(_ operation: (NSImage) -> NSImage) {
        guard let workingImage else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            self.workingImage = operation(workingImage)
        }
    }
}

struct CaptureAnnotationView: View {
    @ObservedObject var store: ScreenshotStore
    let session: CaptureAnnotationSession

    @StateObject private var document: AnnotationDocument
    @State private var tool: AnnotationTool = .arrow
    @State private var selectedColor: AnnotationColor = .red
    @State private var customAnnotationColor: Color = Color(.systemOrange)
    @State private var isCustomColorActive = false
    @State private var showsCustomColorPopover = false
    @State private var strokeWidth: CGFloat = 4

    private var activeAnnotationNSColor: NSColor {
        isCustomColorActive ? NSColor(customAnnotationColor) : selectedColor.nsColor
    }
    @State private var textValue = "Text"
    @State private var keyMonitor: Any?
    @State private var showsBackgroundPanel = false

    init(store: ScreenshotStore, session: CaptureAnnotationSession) {
        self.store = store
        self.session = session
        _document = StateObject(wrappedValue: AnnotationDocument(image: session.image))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    AnnotationCanvasView(
                        document: document,
                        tool: tool,
                        color: activeAnnotationNSColor,
                        strokeWidth: strokeWidth,
                        textValue: textValue,
                        onCancel: {
                            store.closeCaptureEditor(animated: true)
                        }
                    )
                    .background(AppTheme.contentBackground)

                    liveTextButton
                        .padding(18)
                }

                Divider()

                annotationToolbar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 74, alignment: .top)
                    .background(AppTheme.toolbarBackground)
                    .layoutPriority(1)
            }

            if showsBackgroundPanel {
                Divider()

                BackgroundInspectorView(document: document)
                    .frame(width: 248)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: showsBackgroundPanel ? 1160 : 980, minHeight: 640)
        .background(AppTheme.windowBackground)
        .animation(.easeOut(duration: 0.18), value: showsBackgroundPanel)
        .onExitCommand {
            store.closeCaptureEditor(animated: true)
        }
        .onAppear(perform: installKeyboardMonitor)
        .onDisappear(perform: removeKeyboardMonitor)
    }

    private var annotationToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Drawing tools
                toolButton(.arrow, icon: "arrow.up.right", title: "Arrow")
                toolButton(.line, icon: "line.diagonal", title: "Line")
                toolButton(.rectangle, icon: "square", title: "Rectangle")
                toolButton(.oval, icon: "oval", title: "Oval")
                toolButton(.marker, icon: "highlighter", title: "Marker")
                toolButton(.text, icon: "textformat", title: "Text")
                toolButton(.mosaic, icon: "square.grid.3x3.fill", title: "Mosaic")

                Divider().frame(height: 20)

                // Crop
                Button {
                    document.resetCrop()
                } label: {
                    toolbarIcon("crop")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!document.isCropAdjusted)
                .help("Reset Crop")

                Spacer(minLength: 8)

                // History
                Button {
                    document.undo()
                } label: {
                    toolbarIcon("arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(document.annotations.isEmpty)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo")

                Divider().frame(height: 20)

                // Actions
                Button {
                    pinCurrentImage()
                } label: {
                    toolbarIcon("pin")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Pin as floating reference window")

                Button {
                    store.closeCaptureEditor()
                } label: {
                    toolbarIcon("xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .help("Close")

                Button {
                    finishCapture()
                } label: {
                    toolbarIcon(finishActionIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .help(finishActionHelp)
            }

            HStack(spacing: 10) {
                colorPicker

                Divider().frame(height: 20)

                strokeWidthControl

                Divider().frame(height: 20)

                backgroundButton

                if tool == .text {
                    TextField("Text", text: $textValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                Text(captureHint)
                    .font(AppTypography.helper)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
        }
    }

    private var captureHint: String {
        switch session.destination {
        case .capture(.clipboard):
            return "Enter to copy"
        case .capture(.save):
            return "Enter to save to Library"
        case .edit:
            return "Enter to update"
        }
    }

    private var finishActionIcon: String {
        switch session.destination {
        case .capture(.clipboard):
            return "doc.on.clipboard"
        case .capture(.save):
            return "tray.and.arrow.down"
        case .edit:
            return "square.and.arrow.down"
        }
    }

    private var finishActionHelp: String {
        switch session.destination {
        case .capture(.clipboard):
            return "Copy final image to the clipboard"
        case .capture(.save):
            return "Save final image to the library"
        case .edit:
            return "Update this screenshot"
        }
    }

    private func toolButton(_ value: AnnotationTool, icon: String, title: String) -> some View {
        Button {
            tool = value
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .frame(width: toolbarButtonContentSize.width, height: toolbarButtonContentSize.height)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(title)
        .background(tool == value ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private var toolbarButtonContentSize: CGSize {
        CGSize(width: 28, height: 26)
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .frame(width: toolbarButtonContentSize.width, height: toolbarButtonContentSize.height)
    }

    private var colorPicker: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationColor.allCases) { color in
                Button {
                    selectedColor = color
                    isCustomColorActive = false
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(!isCustomColorActive && selectedColor == color ? Color.primary : AppTheme.softBorder, lineWidth: !isCustomColorActive && selectedColor == color ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .help(color.name)
            }

            Button {
                showsCustomColorPopover.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(isCustomColorActive ? customAnnotationColor : Color.clear)
                        .frame(width: 18, height: 18)
                    Circle()
                        .strokeBorder(isCustomColorActive ? Color.primary : AppTheme.softBorder, lineWidth: isCustomColorActive ? 2 : 1)
                        .frame(width: 18, height: 18)
                    if !isCustomColorActive {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Custom Color")
            .popover(isPresented: $showsCustomColorPopover, arrowEdge: .bottom) {
                ColorPicker("Custom Color", selection: $customAnnotationColor)
                    .padding(16)
                    .onChange(of: customAnnotationColor) { _, _ in
                        isCustomColorActive = true
                    }
            }
        }
    }

    private var strokeWidthControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "lineweight")
                .foregroundStyle(.secondary)

            Slider(value: $strokeWidth, in: 2...18, step: 1)
                .frame(width: 112)

            Text("\(Int(strokeWidth))")
                .font(AppTypography.helper.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
        }
        .help("Stroke Width")
    }

    private var backgroundButton: some View {
        Button {
            if !showsBackgroundPanel, document.backgroundSettings.style == .none {
                updateBackgroundSettings { settings in
                    settings.style = .ocean
                }
            }
            showsBackgroundPanel.toggle()
        } label: {
            toolbarIcon("photo.on.rectangle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .background(showsBackgroundPanel || document.backgroundSettings.style != .none ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .help("Background")
    }

    private var liveTextButton: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                document.toggleTextRecognition()
            }
        } label: {
            ZStack {
                if document.isRecognizingText {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .foregroundStyle(document.isTextRecognitionEnabled ? Color.white : Color.primary.opacity(0.72))
            .frame(width: 34, height: 34)
            .background {
                Circle()
                    .fill(document.isTextRecognitionEnabled ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.84))
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            }
            .overlay {
                Circle()
                    .stroke(document.isTextRecognitionEnabled ? Color.white.opacity(0.26) : AppTheme.softBorder, lineWidth: 1)
            }
            .scaleEffect(document.isTextRecognitionEnabled ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .help(document.isTextRecognitionEnabled ? "Disable Live Text" : "Enable Live Text")
    }

    private func updateBackgroundSettings(_ update: (inout AnnotationBackgroundSettings) -> Void) {
        var settings = document.backgroundSettings
        update(&settings)
        document.backgroundSettings = settings
    }

    private func finishCapture() {
        store.finishAnnotatedCapture(document.renderedImage(), destination: session.destination)
    }

    private func pinCurrentImage() {
        let title: String
        switch session.destination {
        case .edit(let item):
            title = item.fileName
        case .capture(.clipboard):
            title = "Pinned Clipboard Screenshot"
        case .capture(.save):
            title = "Pinned Screenshot"
        }

        store.pinImage(document.renderedImage(), title: title)
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isReturn = event.keyCode == 36 || event.keyCode == 76

            if event.keyCode == 53 {
                store.closeCaptureEditor(animated: true)
                return nil
            }

            let returnShouldFinish = isReturn && (flags.isEmpty || flags == .numericPad || flags.contains(.command))

            guard returnShouldFinish else {
                return event
            }

            finishCapture()
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        guard let keyMonitor else {
            return
        }

        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

private struct BackgroundInspectorView: View {
    @ObservedObject var document: AnnotationDocument

    private let swatchColumns = [
        GridItem(.adaptive(minimum: 52), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Background")
                    .font(AppTypography.sectionTitle)

                Spacer()

                Button {
                    updateSettings { settings in
                        settings.style = .none
                    }
                } label: {
                    Image(systemName: "slash.circle")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Disable Background")
            }

            BackgroundPreviewView(document: document)
                .frame(height: 152)

            VStack(alignment: .leading, spacing: 10) {
                Text("Style")
                    .font(AppTypography.helper)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: 8) {
                    backgroundSwatch(.none)

                    ForEach(AnnotationBackgroundStyle.backgroundCases) { style in
                        backgroundSwatch(style)
                    }
                }
            }

            Divider()

            inspectorSlider(
                title: "Padding",
                value: Binding(
                    get: { document.backgroundSettings.padding },
                    set: { newValue in
                        updateSettings { settings in
                            settings.padding = newValue
                        }
                    }
                ),
                range: 16...220,
                step: 4,
                icon: "arrow.up.left.and.arrow.down.right"
            )

            inspectorSlider(
                title: "Corners",
                value: Binding(
                    get: { document.backgroundSettings.cornerRadius },
                    set: { newValue in
                        updateSettings { settings in
                            settings.cornerRadius = newValue
                        }
                    }
                ),
                range: 0...64,
                step: 2,
                icon: "rectangle.roundedtop"
            )

            Toggle(
                isOn: Binding(
                    get: { document.backgroundSettings.autoBalance },
                    set: { newValue in
                        updateSettings { settings in
                            settings.autoBalance = newValue
                        }
                    }
                )
            ) {
                Label("Auto-balance", systemImage: "wand.and.stars")
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppTheme.panelBackground)
    }

    private func backgroundSwatch(_ style: AnnotationBackgroundStyle) -> some View {
        Button {
            updateSettings { settings in
                settings.style = style
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(style.swatch)

                if style == .none {
                    Image(systemName: "slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 34)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        document.backgroundSettings.style == style ? Color.accentColor : AppTheme.softBorder,
                        lineWidth: document.backgroundSettings.style == style ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(style.title)
    }

    private func inspectorSlider(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(AppTypography.helper)

                Spacer()

                Text("\(Int(value.wrappedValue))")
                    .font(AppTypography.metadata)
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range, step: step)
                .disabled(document.backgroundSettings.autoBalance)
        }
    }

    private func updateSettings(_ update: (inout AnnotationBackgroundSettings) -> Void) {
        var settings = document.backgroundSettings
        update(&settings)
        document.backgroundSettings = settings
    }
}

private struct BackgroundPreviewView: View {
    @ObservedObject var document: AnnotationDocument

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.imageWellBackground)

            Image(nsImage: document.renderedImage())
                .resizable()
                .scaledToFit()
                .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.softBorder, lineWidth: 1)
        }
    }
}

private enum AnnotationTool: CaseIterable {
    case arrow
    case line
    case rectangle
    case oval
    case marker
    case text
    case mosaic
}

private enum AnnotationColor: String, CaseIterable, Identifiable {
    case red
    case yellow
    case blue
    case green
    case white
    case black

    var id: String { rawValue }

    var name: String {
        rawValue.capitalized
    }

    var nsColor: NSColor {
        switch self {
        case .red:
            return .systemRed
        case .yellow:
            return .systemYellow
        case .blue:
            return .systemBlue
        case .green:
            return .systemGreen
        case .white:
            return .white
        case .black:
            return .black
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}

@MainActor
private final class AnnotationDocument: ObservableObject {
    let image: NSImage
    @Published var annotations: [ImageAnnotation] = []
    @Published var cropRect: NSRect
    @Published var backgroundSettings = AnnotationBackgroundSettings()
    @Published var isTextRecognitionEnabled = false
    @Published var isRecognizingText = false
    @Published var recognizedTextRegions: [RecognizedTextRegion] = []
    private var textRecognitionGeneration = UUID()

    init(image: NSImage) {
        self.image = image
        cropRect = NSRect(origin: .zero, size: image.size)
    }

    func undo() {
        guard !annotations.isEmpty else {
            return
        }

        annotations.removeLast()
    }

    func renderedImage() -> NSImage {
        let contentImage = renderedContentImage()
        return backgroundSettings.renderedImage(wrapping: contentImage)
    }

    private func renderedContentImage() -> NSImage {
        let sourceBounds = NSRect(origin: .zero, size: image.size)
        let crop = normalizedCropRect.intersection(sourceBounds)
        let outputSize = NSSize(width: max(crop.width, 1), height: max(crop.height, 1))
        let output = NSImage(size: outputSize)

        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let outputRect = NSRect(origin: .zero, size: outputSize)
        image.draw(in: outputRect, from: crop, operation: .copy, fraction: 1)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: outputRect).addClip()
        NSGraphicsContext.current?.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
        for annotation in annotations {
            annotation.draw(baseImage: image, scale: 1)
        }
        NSGraphicsContext.restoreGraphicsState()

        output.unlockFocus()
        return output
    }

    func resetCrop() {
        cropRect = NSRect(origin: .zero, size: image.size)
    }

    var isCropAdjusted: Bool {
        normalizedCropRect != NSRect(origin: .zero, size: image.size)
    }

    var normalizedCropRect: NSRect {
        normalizedRect(cropRect).intersection(NSRect(origin: .zero, size: image.size))
    }

    private func normalizedRect(_ rect: NSRect) -> NSRect {
        NSRect(
            x: min(rect.minX, rect.maxX),
            y: min(rect.minY, rect.maxY),
            width: abs(rect.width),
            height: abs(rect.height)
        )
    }

    func toggleTextRecognition() {
        setTextRecognitionEnabled(!isTextRecognitionEnabled)
    }

    func setTextRecognitionEnabled(_ isEnabled: Bool) {
        textRecognitionGeneration = UUID()
        isTextRecognitionEnabled = isEnabled

        guard isEnabled else {
            isRecognizingText = false
            recognizedTextRegions.removeAll()
            return
        }

        recognizeText(generation: textRecognitionGeneration)
    }

    private func recognizeText(generation: UUID) {
        guard recognizedTextRegions.isEmpty, !isRecognizingText else {
            return
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        isRecognizingText = true
        let imageSize = image.size
        Task { [weak self] in
            let regions = await TextRecognitionService.recognize(cgImage: cgImage, imageSize: imageSize)
            guard let self, self.textRecognitionGeneration == generation else {
                return
            }

            self.isRecognizingText = false
            guard self.isTextRecognitionEnabled else {
                return
            }

            self.recognizedTextRegions = regions
        }
    }
}

private struct RecognizedTextRegion: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let sourceText: String
    let boundingBox: NSRect
    let characterBoxes: [RecognizedCharacterBox]
}

private struct RecognizedCharacterBox: Equatable, Sendable {
    let character: String
    let range: Range<String.Index>
    let boundingBox: NSRect
}

private enum TextRecognitionService {
    static func recognize(cgImage: CGImage, imageSize: NSSize) async -> [RecognizedTextRegion] {
        await Task.detached(priority: .utility) {
            recognizeSync(cgImage: cgImage, imageSize: imageSize)
        }.value
    }

    private static func recognizeSync(cgImage: CGImage, imageSize: NSSize) -> [RecognizedTextRegion] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let supportedRevisions = VNRecognizeTextRequest.supportedRevisions
        if supportedRevisions.contains(VNRecognizeTextRequestRevision3) {
            request.revision = VNRecognizeTextRequestRevision3
        } else if let newestSupportedRevision = supportedRevisions.max() {
            request.revision = newestSupportedRevision
        }

        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let originalText = candidate.string
            let text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }

            let leadingWhitespaceCount = originalText.prefix { $0.isWhitespace }.count
            let textStart = originalText.index(originalText.startIndex, offsetBy: leadingWhitespaceCount)
            let textEnd = originalText.index(textStart, offsetBy: text.count)

            let box = observation.boundingBox
            let rect = NSRect(
                x: box.minX * imageSize.width,
                y: box.minY * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )

            guard rect.width >= 2, rect.height >= 2 else {
                return nil
            }

            let characterBoxes = characterBoxes(
                for: candidate,
                textRange: textStart..<textEnd,
                imageSize: imageSize
            )

            return RecognizedTextRegion(
                text: text,
                sourceText: originalText,
                boundingBox: rect,
                characterBoxes: characterBoxes
            )
        }
    }

    private static func characterBoxes(
        for candidate: VNRecognizedText,
        textRange: Range<String.Index>,
        imageSize: NSSize
    ) -> [RecognizedCharacterBox] {
        var boxes: [RecognizedCharacterBox] = []
        var index = textRange.lowerBound

        while index < textRange.upperBound {
            let nextIndex = candidate.string.index(after: index)
            defer {
                index = nextIndex
            }

            guard !candidate.string[index].isWhitespace else {
                continue
            }

            guard let box = (try? candidate.boundingBox(for: index..<nextIndex))??.boundingBox else {
                continue
            }

            let rect = NSRect(
                x: box.minX * imageSize.width,
                y: box.minY * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )

            guard rect.width >= 0.5, rect.height >= 0.5 else {
                continue
            }

            boxes.append(RecognizedCharacterBox(
                character: String(candidate.string[index]),
                range: index..<nextIndex,
                boundingBox: rect
            ))
        }

        return boxes
    }
}

private struct AnnotationBackgroundSettings: Equatable {
    var style: AnnotationBackgroundStyle = .none
    var padding: CGFloat = 72
    var cornerRadius: CGFloat = 18
    var autoBalance = false

    func renderedImage(wrapping image: NSImage) -> NSImage {
        guard style != .none else {
            return image
        }

        let imageSize = image.size
        let clampedPadding = resolvedPadding(for: imageSize)
        let outputSize = NSSize(
            width: max(imageSize.width + clampedPadding * 2, 1),
            height: max(imageSize.height + clampedPadding * 2, 1)
        )
        let output = NSImage(size: outputSize)
        let outputRect = NSRect(origin: .zero, size: outputSize)
        let imageRect = NSRect(
            x: clampedPadding,
            y: clampedPadding,
            width: imageSize.width,
            height: imageSize.height
        )
        let radius = min(resolvedCornerRadius(for: imageSize), min(imageRect.width, imageRect.height) / 2)

        output.lockFocus()
        style.drawBackground(in: outputRect)

        let imagePath = NSBezierPath(roundedRect: imageRect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        imagePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        imagePath.addClip()
        image.draw(in: imageRect, from: NSRect(origin: .zero, size: imageSize), operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.14).setStroke()
        imagePath.lineWidth = 1
        imagePath.stroke()

        output.unlockFocus()
        return output
    }

    private func resolvedPadding(for imageSize: NSSize) -> CGFloat {
        guard autoBalance else {
            return max(padding, 0)
        }

        let longSide = max(imageSize.width, imageSize.height)
        return max(40, min(longSide * 0.055, 160))
    }

    private func resolvedCornerRadius(for imageSize: NSSize) -> CGFloat {
        guard autoBalance else {
            return max(cornerRadius, 0)
        }

        let shortSide = min(imageSize.width, imageSize.height)
        return max(18, min(shortSide * 0.045, 56))
    }
}

private enum AnnotationBackgroundStyle: String, CaseIterable, Identifiable {
    case none
    case graphite
    case ocean
    case mint
    case sunset
    case paper

    var id: String { rawValue }

    static var backgroundCases: [AnnotationBackgroundStyle] {
        allCases.filter { $0 != .none }
    }

    var title: String {
        switch self {
        case .none:
            return "None"
        case .graphite:
            return "Graphite"
        case .ocean:
            return "Ocean"
        case .mint:
            return "Mint"
        case .sunset:
            return "Sunset"
        case .paper:
            return "Paper"
        }
    }

    var swatch: LinearGradient {
        LinearGradient(colors: swiftUIColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var swiftUIColors: [Color] {
        nsColors.map(Color.init(nsColor:))
    }

    private var nsColors: [NSColor] {
        switch self {
        case .none:
            return [.clear, .clear]
        case .graphite:
            return [
                NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.17, alpha: 1),
                NSColor(calibratedRed: 0.34, green: 0.35, blue: 0.38, alpha: 1)
            ]
        case .ocean:
            return [
                NSColor(calibratedRed: 0.05, green: 0.43, blue: 0.91, alpha: 1),
                NSColor(calibratedRed: 0.20, green: 0.86, blue: 0.91, alpha: 1)
            ]
        case .mint:
            return [
                NSColor(calibratedRed: 0.13, green: 0.76, blue: 0.63, alpha: 1),
                NSColor(calibratedRed: 0.74, green: 0.93, blue: 0.77, alpha: 1)
            ]
        case .sunset:
            return [
                NSColor(calibratedRed: 0.98, green: 0.32, blue: 0.42, alpha: 1),
                NSColor(calibratedRed: 0.99, green: 0.72, blue: 0.37, alpha: 1)
            ]
        case .paper:
            return [
                NSColor(calibratedRed: 0.95, green: 0.94, blue: 0.91, alpha: 1),
                NSColor(calibratedRed: 0.99, green: 0.98, blue: 0.95, alpha: 1)
            ]
        }
    }

    func drawBackground(in rect: NSRect) {
        guard let gradient = NSGradient(colors: nsColors) else {
            NSColor.windowBackgroundColor.setFill()
            rect.fill()
            return
        }

        gradient.draw(in: rect, angle: 35)
    }
}

private struct AnnotationCanvasView: NSViewRepresentable {
    @ObservedObject var document: AnnotationDocument
    let tool: AnnotationTool
    let color: NSColor
    let strokeWidth: CGFloat
    let textValue: String
    let onCancel: () -> Void

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        AnnotationCanvasNSView()
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        nsView.document = document
        nsView.tool = tool
        nsView.color = color
        nsView.strokeWidth = strokeWidth
        nsView.textValue = textValue
        nsView.isTextRecognitionEnabled = document.isTextRecognitionEnabled
        nsView.onCancel = onCancel
        nsView.needsDisplay = true
    }
}

private final class AnnotationCanvasNSView: NSView {
    var document: AnnotationDocument? {
        didSet {
            if let selectedAnnotationIndex,
               let document,
               !document.annotations.indices.contains(selectedAnnotationIndex) {
                self.selectedAnnotationIndex = nil
            }
            needsDisplay = true
        }
    }
    var tool: AnnotationTool = .arrow
    var color: NSColor = .systemRed
    var strokeWidth: CGFloat = 4
    var textValue = "Text"
    var isTextRecognitionEnabled = false {
        didSet {
            guard !isTextRecognitionEnabled else {
                return
            }

            textSelectionStart = nil
            textSelectionCurrent = nil
            selectedTextRegionIDs.removeAll()
            selectedTextCharacterIndexes.removeAll()
            selectedRecognizedText = nil
            needsDisplay = true
        }
    }
    var onCancel: (() -> Void)?

    private var dragStart: NSPoint?
    private var currentPoint: NSPoint?
    private var currentMarkerPoints: [NSPoint] = []
    private var activeCropHandle: CropHandle?
    private var cropStartRect: NSRect?
    private var isMovingCrop = false
    private var cropMoveStartPoint: NSPoint?
    private var cropMoveStartRect: NSRect?
    private var selectedAnnotationIndex: Int?
    private var annotationInteraction: AnnotationInteraction?
    private var textSelectionStart: NSPoint?
    private var textSelectionCurrent: NSPoint?
    private var selectedTextRegionIDs = Set<UUID>()
    private var selectedTextCharacterIndexes: [UUID: Set<Int>] = [:]
    private var selectedRecognizedText: String?
    private var textCopyFeedback: String?
    private var trackingArea: NSTrackingArea?

    private let cropHandleSize: CGFloat = 9
    private let minimumCropSize: CGFloat = 24

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        false
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
        let localPoint = convert(event.locationInWindow, from: nil)
        if isTextRecognitionEnabled, recognizedTextRegion(at: localPoint) != nil {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)

        if isTextRecognitionEnabled,
           let textRegion = recognizedTextRegion(at: localPoint) {
            window?.makeFirstResponder(self)
            selectedAnnotationIndex = nil
            annotationInteraction = nil
            textSelectionStart = localPoint
            textSelectionCurrent = localPoint
            selectedTextRegionIDs = [textRegion.id]
            selectedTextCharacterIndexes.removeAll()
            selectedRecognizedText = nil
            needsDisplay = true
            return
        }

        if let interaction = annotationInteraction(at: localPoint) {
            window?.makeFirstResponder(self)
            annotationInteraction = interaction
            needsDisplay = true
            return
        }

        if let handle = cropHandle(at: localPoint) {
            window?.makeFirstResponder(self)
            activeCropHandle = handle
            cropStartRect = document?.normalizedCropRect
            needsDisplay = true
            return
        }

        if cropBorderHit(at: localPoint),
           let point = clampedImagePoint(for: event.locationInWindow) {
            window?.makeFirstResponder(self)
            isMovingCrop = true
            cropMoveStartPoint = point
            cropMoveStartRect = document?.normalizedCropRect
            needsDisplay = true
            return
        }

        guard let imagePoint = imagePoint(for: event.locationInWindow) else {
            return
        }

        window?.makeFirstResponder(self)

        if let index = annotationIndex(at: imagePoint),
           let original = document?.annotations[index] {
            selectedAnnotationIndex = index
            annotationInteraction = .move(index: index, startPoint: imagePoint, original: original)
            needsDisplay = true
            return
        }

        selectedAnnotationIndex = nil
        dragStart = imagePoint
        currentPoint = imagePoint
        currentMarkerPoints = [imagePoint]

        if tool == .text {
            let text = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let annotation = ImageAnnotation.text(
                text.isEmpty ? "Text" : text,
                imagePoint,
                color,
                28
            )
            document?.annotations.append(annotation)
            selectedAnnotationIndex = (document?.annotations.count ?? 1) - 1
            clearDraft()
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if textSelectionStart != nil {
            updateTextSelection(to: convert(event.locationInWindow, from: nil))
            return
        }

        if let annotationInteraction {
            updateAnnotationInteraction(annotationInteraction, with: event)
            return
        }

        if let activeCropHandle {
            resizeCrop(with: event, handle: activeCropHandle)
            return
        }

        if isMovingCrop {
            moveCrop(with: event)
            return
        }

        guard let imagePoint = imagePoint(for: event.locationInWindow), dragStart != nil else {
            return
        }

        currentPoint = imagePoint

        if tool == .marker {
            currentMarkerPoints.append(imagePoint)
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if textSelectionStart != nil {
            updateTextSelection(to: convert(event.locationInWindow, from: nil))
            copySelectedRecognizedText()
            textSelectionStart = nil
            textSelectionCurrent = nil
            needsDisplay = true
            return
        }

        if annotationInteraction != nil {
            annotationInteraction = nil
            needsDisplay = true
            return
        }

        if activeCropHandle != nil {
            activeCropHandle = nil
            cropStartRect = nil
            needsDisplay = true
            return
        }

        if isMovingCrop {
            isMovingCrop = false
            cropMoveStartPoint = nil
            cropMoveStartRect = nil
            needsDisplay = true
            return
        }

        guard let start = dragStart,
              let end = imagePoint(for: event.locationInWindow) ?? currentPoint else {
            clearDraft()
            return
        }

        defer {
            clearDraft()
        }

        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > 4 || tool == .marker else {
            return
        }

        switch tool {
        case .arrow:
            appendAnnotation(.arrow(start, end, color, strokeWidth))
        case .line:
            appendAnnotation(.line(start, end, color, strokeWidth))
        case .rectangle:
            let rect = normalizedRect(from: start, to: end)
            guard rect.width > 6, rect.height > 6 else {
                return
            }
            appendAnnotation(.rectangle(rect, color, strokeWidth))
        case .oval:
            let rect = normalizedRect(from: start, to: end)
            guard rect.width > 6, rect.height > 6 else {
                return
            }
            appendAnnotation(.oval(rect, color, strokeWidth))
        case .marker:
            guard currentMarkerPoints.count > 1 else {
                return
            }
            appendAnnotation(.marker(currentMarkerPoints, color, strokeWidth))
        case .mosaic:
            let rect = normalizedRect(from: start, to: end)
            guard rect.width > 6, rect.height > 6 else {
                return
            }
            appendAnnotation(.mosaic(rect))
        case .text:
            break
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isTextRecognitionEnabled,
           flags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c",
           !selectedTextRegionIDs.isEmpty {
            copySelectedRecognizedText()
            return
        }

        guard let selectedAnnotationIndex,
              let document,
              document.annotations.indices.contains(selectedAnnotationIndex) else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            document.annotations.remove(at: selectedAnnotationIndex)
            self.selectedAnnotationIndex = nil
            needsDisplay = true
            return
        }

        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let delta: NSSize?
        switch event.keyCode {
        case 123:
            delta = NSSize(width: -step, height: 0)
        case 124:
            delta = NSSize(width: step, height: 0)
        case 125:
            delta = NSSize(width: 0, height: -step)
        case 126:
            delta = NSSize(width: 0, height: step)
        default:
            delta = nil
        }

        guard let delta else {
            super.keyDown(with: event)
            return
        }

        document.annotations[selectedAnnotationIndex] = document.annotations[selectedAnnotationIndex].moved(by: delta)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        guard let document else {
            return
        }

        let imageRect = fittedImageRect(for: document.image.size)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: imageRect).addClip()
        document.image.draw(in: imageRect, from: NSRect(origin: .zero, size: document.image.size), operation: .copy, fraction: 1)

        NSGraphicsContext.current?.cgContext.translateBy(x: imageRect.minX, y: imageRect.minY)
        NSGraphicsContext.current?.cgContext.scaleBy(
            x: imageRect.width / document.image.size.width,
            y: imageRect.height / document.image.size.height
        )

        for annotation in document.annotations {
            annotation.draw(baseImage: document.image, scale: 1)
        }

        drawDraft(baseImage: document.image)
        NSGraphicsContext.restoreGraphicsState()

        drawCropOverlay(
            imageRect: imageRect,
            cropRect: document.normalizedCropRect,
            imageSize: document.image.size
        )
        if isTextRecognitionEnabled {
            drawRecognizedTextOverlay(imageRect: imageRect, imageSize: document.image.size)
        }
        drawAnnotationSelection(imageRect: imageRect, imageSize: document.image.size)
        drawTextCopyFeedback()
    }

    private func drawDraft(baseImage: NSImage) {
        guard let start = dragStart, let end = currentPoint else {
            return
        }

        switch tool {
        case .arrow:
            ImageAnnotation.arrow(start, end, color, strokeWidth).draw(baseImage: baseImage, scale: 1)
        case .line:
            ImageAnnotation.line(start, end, color, strokeWidth).draw(baseImage: baseImage, scale: 1)
        case .rectangle:
            ImageAnnotation.rectangle(normalizedRect(from: start, to: end), color, strokeWidth).draw(baseImage: baseImage, scale: 1)
        case .oval:
            ImageAnnotation.oval(normalizedRect(from: start, to: end), color, strokeWidth).draw(baseImage: baseImage, scale: 1)
        case .marker:
            ImageAnnotation.marker(currentMarkerPoints, color, strokeWidth).draw(baseImage: baseImage, scale: 1)
        case .mosaic:
            ImageAnnotation.mosaic(normalizedRect(from: start, to: end)).draw(baseImage: baseImage, scale: 1)
        case .text:
            break
        }
    }

    private func imagePoint(for windowPoint: NSPoint) -> NSPoint? {
        imagePoint(forLocalPoint: convert(windowPoint, from: nil))
    }

    private func imagePoint(forLocalPoint localPoint: NSPoint) -> NSPoint? {
        guard let document else {
            return nil
        }

        let imageRect = fittedImageRect(for: document.image.size)

        guard imageRect.contains(localPoint) else {
            return nil
        }

        let scaleX = document.image.size.width / imageRect.width
        let scaleY = document.image.size.height / imageRect.height
        let imagePoint = NSPoint(
            x: (localPoint.x - imageRect.minX) * scaleX,
            y: (localPoint.y - imageRect.minY) * scaleY
        )

        guard document.normalizedCropRect.contains(imagePoint) else {
            return nil
        }

        return imagePoint
    }

    private func clampedImagePoint(for windowPoint: NSPoint) -> NSPoint? {
        guard let document else {
            return nil
        }

        let localPoint = convert(windowPoint, from: nil)
        let imageRect = fittedImageRect(for: document.image.size)
        let scaleX = document.image.size.width / imageRect.width
        let scaleY = document.image.size.height / imageRect.height
        let rawPoint = NSPoint(
            x: (localPoint.x - imageRect.minX) * scaleX,
            y: (localPoint.y - imageRect.minY) * scaleY
        )

        return NSPoint(
            x: min(max(rawPoint.x, 0), document.image.size.width),
            y: min(max(rawPoint.y, 0), document.image.size.height)
        )
    }

    private func fittedImageRect(for imageSize: NSSize) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return bounds.insetBy(dx: 24, dy: 24)
        }

        let available = bounds.insetBy(dx: 24, dy: 24)
        let imageRatio = imageSize.width / imageSize.height
        let availableRatio = available.width / available.height

        if imageRatio > availableRatio {
            let height = available.width / imageRatio
            return NSRect(x: available.minX, y: available.midY - height / 2, width: available.width, height: height)
        }

        let width = available.height * imageRatio
        return NSRect(x: available.midX - width / 2, y: available.minY, width: width, height: available.height)
    }

    private func clearDraft() {
        dragStart = nil
        currentPoint = nil
        currentMarkerPoints = []
        needsDisplay = true
    }

    private func appendAnnotation(_ annotation: ImageAnnotation) {
        document?.annotations.append(annotation)
        selectedAnnotationIndex = (document?.annotations.count ?? 1) - 1
    }

    private func annotationInteraction(at localPoint: NSPoint) -> AnnotationInteraction? {
        guard let document,
              let selectedAnnotationIndex,
              document.annotations.indices.contains(selectedAnnotationIndex) else {
            return nil
        }

        let imageRect = fittedImageRect(for: document.image.size)
        let annotation = document.annotations[selectedAnnotationIndex]
        let bounds = annotation.bounds(baseImage: document.image)
        let viewBounds = viewRect(for: bounds, imageRect: imageRect, imageSize: document.image.size)

        if let handle = CropHandle.allCases.first(where: { handle in
            handleRect(for: handle, cropViewRect: viewBounds)
                .insetBy(dx: -5, dy: -5)
                .contains(localPoint)
        }) {
            return .resize(index: selectedAnnotationIndex, handle: handle, startBounds: bounds, original: annotation)
        }

        guard let imagePoint = imagePoint(forLocalPoint: localPoint),
              annotation.hitTest(imagePoint, baseImage: document.image, tolerance: hitTolerance(in: imageRect)) else {
            return nil
        }

        return .move(index: selectedAnnotationIndex, startPoint: imagePoint, original: annotation)
    }

    private func annotationIndex(at imagePoint: NSPoint) -> Int? {
        guard let document else {
            return nil
        }

        let imageRect = fittedImageRect(for: document.image.size)
        let tolerance = hitTolerance(in: imageRect)

        return document.annotations.indices.reversed().first { index in
            document.annotations[index].hitTest(imagePoint, baseImage: document.image, tolerance: tolerance)
        }
    }

    private func updateAnnotationInteraction(_ interaction: AnnotationInteraction, with event: NSEvent) {
        guard let document,
              let point = clampedImagePoint(for: event.locationInWindow) else {
            return
        }

        switch interaction {
        case .move(let index, let startPoint, let original):
            guard document.annotations.indices.contains(index) else {
                return
            }

            let delta = NSSize(width: point.x - startPoint.x, height: point.y - startPoint.y)
            document.annotations[index] = original.moved(by: delta)
            selectedAnnotationIndex = index
        case .resize(let index, let handle, let startBounds, let original):
            guard document.annotations.indices.contains(index) else {
                return
            }

            let newBounds = resizedBounds(from: startBounds, handle: handle, point: point)
            document.annotations[index] = original.resized(from: startBounds, to: newBounds)
            selectedAnnotationIndex = index
        }

        needsDisplay = true
    }

    private func resizedBounds(from startBounds: NSRect, handle: CropHandle, point: NSPoint) -> NSRect {
        let minimumSize: CGFloat = 8
        var minX = startBounds.minX
        var maxX = startBounds.maxX
        var minY = startBounds.minY
        var maxY = startBounds.maxY

        if handle.adjustsLeft {
            minX = min(point.x, maxX - minimumSize)
        }

        if handle.adjustsRight {
            maxX = max(point.x, minX + minimumSize)
        }

        if handle.adjustsBottom {
            minY = min(point.y, maxY - minimumSize)
        }

        if handle.adjustsTop {
            maxY = max(point.y, minY + minimumSize)
        }

        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func hitTolerance(in imageRect: NSRect) -> CGFloat {
        guard let document,
              imageRect.width > 0,
              imageRect.height > 0 else {
            return 10
        }

        let scale = max(document.image.size.width / imageRect.width, document.image.size.height / imageRect.height)
        return max(8 * scale, 6)
    }

    private func recognizedTextRegion(at localPoint: NSPoint) -> RecognizedTextRegion? {
        guard let document,
              !document.recognizedTextRegions.isEmpty else {
            return nil
        }

        let imageRect = fittedImageRect(for: document.image.size)
        return document.recognizedTextRegions.first { region in
            viewRect(for: region.boundingBox, imageRect: imageRect, imageSize: document.image.size)
                .insetBy(dx: -3, dy: -3)
                .contains(localPoint)
        }
    }

    private func updateTextSelection(to localPoint: NSPoint) {
        guard let document,
              let textSelectionStart else {
            return
        }

        textSelectionCurrent = localPoint
        let imageRect = fittedImageRect(for: document.image.size)
        let selectionRect = normalizedRect(from: textSelectionStart, to: localPoint)

        if selectionRect.width < 3, selectionRect.height < 3 {
            if let region = recognizedTextRegion(at: localPoint) {
                selectedTextRegionIDs = [region.id]
                selectedTextCharacterIndexes.removeAll()
                selectedRecognizedText = nil
            }
        } else if let fragmentSelection = textFragmentSelection(in: selectionRect, imageRect: imageRect) {
            selectedTextRegionIDs = [fragmentSelection.regionID]
            selectedTextCharacterIndexes = [fragmentSelection.regionID: fragmentSelection.characterIndexes]
            selectedRecognizedText = fragmentSelection.text
        } else {
            let ids = document.recognizedTextRegions.compactMap { region -> UUID? in
                let rect = viewRect(for: region.boundingBox, imageRect: imageRect, imageSize: document.image.size)
                return rect.intersects(selectionRect) ? region.id : nil
            }
            selectedTextRegionIDs = Set(ids)
            selectedTextCharacterIndexes.removeAll()
            selectedRecognizedText = nil
        }

        needsDisplay = true
    }

    private func textFragmentSelection(
        in selectionRect: NSRect,
        imageRect: NSRect
    ) -> (regionID: UUID, characterIndexes: Set<Int>, text: String)? {
        guard let document,
              let textSelectionStart,
              let startRegion = recognizedTextRegion(at: textSelectionStart),
              let currentPoint = textSelectionCurrent,
              let currentRegion = recognizedTextRegion(at: currentPoint),
              startRegion.id == currentRegion.id,
              !startRegion.characterBoxes.isEmpty else {
            return nil
        }

        let selectedCharacterIndexes = startRegion.characterBoxes.enumerated().compactMap { index, box -> Int? in
            let rect = viewRect(for: box.boundingBox, imageRect: imageRect, imageSize: document.image.size)
            return rect.intersects(selectionRect.insetBy(dx: -1.5, dy: -3)) ? index : nil
        }

        guard !selectedCharacterIndexes.isEmpty else {
            return nil
        }

        let indexSet = Set(selectedCharacterIndexes)
        let selectedBoxes = startRegion.characterBoxes.enumerated()
            .filter { indexSet.contains($0.offset) }
            .map(\.element)

        guard let firstSelectedBox = selectedBoxes.first,
              let lastSelectedBox = selectedBoxes.last else {
            return nil
        }

        let text = String(startRegion.sourceText[firstSelectedBox.range.lowerBound..<lastSelectedBox.range.upperBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return nil
        }

        return (startRegion.id, indexSet, text)
    }

    private func copySelectedRecognizedText() {
        guard let document else {
            return
        }

        let selectedRegions = document.recognizedTextRegions
            .filter { selectedTextRegionIDs.contains($0.id) }
            .sorted { first, second in
                if abs(first.boundingBox.midY - second.boundingBox.midY) > 8 {
                    return first.boundingBox.midY > second.boundingBox.midY
                }

                return first.boundingBox.minX < second.boundingBox.minX
            }

        let text = (selectedRecognizedText ?? selectedRegions
            .map(\.text)
            .joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        textCopyFeedback = selectedRecognizedText == nil && selectedRegions.count > 1
            ? "Copied \(selectedRegions.count) text blocks"
            : "Copied text"
        needsDisplay = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.textCopyFeedback = nil
            self?.needsDisplay = true
        }
    }

    private func drawRecognizedTextOverlay(imageRect: NSRect, imageSize: NSSize) {
        guard let document,
              !document.recognizedTextRegions.isEmpty,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return
        }

        for region in document.recognizedTextRegions {
            let rect = viewRect(for: region.boundingBox, imageRect: imageRect, imageSize: imageSize)
            let isSelected = selectedTextRegionIDs.contains(region.id)
            let selectedCharacterIndexes = selectedTextCharacterIndexes[region.id] ?? []
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), xRadius: 3, yRadius: 3)

            if isSelected, selectedCharacterIndexes.isEmpty {
                NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
                path.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
            } else {
                NSColor.controlAccentColor.withAlphaComponent(0.05).setFill()
                path.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.22).setStroke()
            }

            path.lineWidth = isSelected ? 1.5 : 1
            path.stroke()

            guard !selectedCharacterIndexes.isEmpty else {
                continue
            }

            for index in selectedCharacterIndexes.sorted() where region.characterBoxes.indices.contains(index) {
                let characterRect = viewRect(
                    for: region.characterBoxes[index].boundingBox,
                    imageRect: imageRect,
                    imageSize: imageSize
                ).insetBy(dx: -1.5, dy: -2)
                let characterPath = NSBezierPath(roundedRect: characterRect, xRadius: 2.5, yRadius: 2.5)
                NSColor.controlAccentColor.withAlphaComponent(0.34).setFill()
                characterPath.fill()
            }
        }

        if let textSelectionStart, let textSelectionCurrent {
            let selectionRect = normalizedRect(from: textSelectionStart, to: textSelectionCurrent)
            guard selectionRect.width > 3 || selectionRect.height > 3 else {
                return
            }

            let path = NSBezierPath(roundedRect: selectionRect, xRadius: 4, yRadius: 4)
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.72).setStroke()
            path.lineWidth = 1.2
            path.stroke()
        }
    }

    private func drawTextCopyFeedback() {
        guard let textCopyFeedback else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.96)
        ]
        let attributedText = NSAttributedString(string: textCopyFeedback, attributes: attributes)
        let size = attributedText.size()
        let bubble = NSRect(
            x: bounds.midX - (size.width + 24) / 2,
            y: bounds.maxY - size.height - 42,
            width: size.width + 24,
            height: size.height + 12
        )

        NSColor.black.withAlphaComponent(0.68).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 7, yRadius: 7).fill()
        attributedText.draw(at: NSPoint(x: bubble.minX + 12, y: bubble.minY + 6))
    }

    private func cropHandle(at localPoint: NSPoint) -> CropHandle? {
        guard let document else {
            return nil
        }

        let imageRect = fittedImageRect(for: document.image.size)
        let cropViewRect = viewRect(for: document.normalizedCropRect, imageRect: imageRect, imageSize: document.image.size)

        return CropHandle.allCases.first { handle in
            handleRect(for: handle, cropViewRect: cropViewRect)
                .insetBy(dx: -5, dy: -5)
                .contains(localPoint)
        }
    }

    private func cropBorderHit(at localPoint: NSPoint) -> Bool {
        guard let document else {
            return false
        }

        let imageRect = fittedImageRect(for: document.image.size)
        let cropViewRect = viewRect(for: document.normalizedCropRect, imageRect: imageRect, imageSize: document.image.size)
        let outerRect = cropViewRect.insetBy(dx: -9, dy: -9)
        let innerRect = cropViewRect.insetBy(dx: 12, dy: 12)

        return outerRect.contains(localPoint) && !innerRect.contains(localPoint)
    }

    private func resizeCrop(with event: NSEvent, handle: CropHandle) {
        guard let document,
              let cropStartRect,
              let point = clampedImagePoint(for: event.locationInWindow) else {
            return
        }

        var minX = cropStartRect.minX
        var maxX = cropStartRect.maxX
        var minY = cropStartRect.minY
        var maxY = cropStartRect.maxY
        let minSize = min(minimumCropSize, max(min(document.image.size.width, document.image.size.height) / 2, 1))

        if handle.adjustsLeft {
            minX = max(0, min(point.x, maxX - minSize))
        }

        if handle.adjustsRight {
            maxX = min(document.image.size.width, max(point.x, minX + minSize))
        }

        if handle.adjustsBottom {
            minY = max(0, min(point.y, maxY - minSize))
        }

        if handle.adjustsTop {
            maxY = min(document.image.size.height, max(point.y, minY + minSize))
        }

        document.cropRect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        needsDisplay = true
    }

    private func moveCrop(with event: NSEvent) {
        guard let document,
              let cropMoveStartPoint,
              let cropMoveStartRect,
              let point = clampedImagePoint(for: event.locationInWindow) else {
            return
        }

        let deltaX = point.x - cropMoveStartPoint.x
        let deltaY = point.y - cropMoveStartPoint.y
        let maxX = max(document.image.size.width - cropMoveStartRect.width, 0)
        let maxY = max(document.image.size.height - cropMoveStartRect.height, 0)
        let originX = min(max(cropMoveStartRect.minX + deltaX, 0), maxX)
        let originY = min(max(cropMoveStartRect.minY + deltaY, 0), maxY)

        document.cropRect = NSRect(
            x: originX,
            y: originY,
            width: cropMoveStartRect.width,
            height: cropMoveStartRect.height
        )
        needsDisplay = true
    }

    private func drawAnnotationSelection(imageRect: NSRect, imageSize: NSSize) {
        guard let document,
              let selectedAnnotationIndex,
              document.annotations.indices.contains(selectedAnnotationIndex),
              imageSize.width > 0,
              imageSize.height > 0 else {
            return
        }

        let annotation = document.annotations[selectedAnnotationIndex]
        let bounds = annotation.bounds(baseImage: document.image)
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let viewBounds = viewRect(for: bounds, imageRect: imageRect, imageSize: imageSize)
        let path = NSBezierPath(roundedRect: viewBounds, xRadius: 3, yRadius: 3)
        let dash: [CGFloat] = [5, 4]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.lineWidth = 1.2
        NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
        path.stroke()

        CropHandle.allCases.forEach { handle in
            let rect = handleRect(for: handle, cropViewRect: viewBounds)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            NSColor.white.withAlphaComponent(0.86).setStroke()
            let handlePath = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            handlePath.lineWidth = 1
            handlePath.stroke()
        }
    }

    private func drawCropOverlay(imageRect: NSRect, cropRect: NSRect, imageSize: NSSize) {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }

        let cropViewRect = viewRect(for: cropRect, imageRect: imageRect, imageSize: imageSize)
        NSColor.black.withAlphaComponent(0.28).setFill()

        NSBezierPath(rect: NSRect(
            x: imageRect.minX,
            y: imageRect.minY,
            width: imageRect.width,
            height: max(cropViewRect.minY - imageRect.minY, 0)
        )).fill()
        NSBezierPath(rect: NSRect(
            x: imageRect.minX,
            y: cropViewRect.maxY,
            width: imageRect.width,
            height: max(imageRect.maxY - cropViewRect.maxY, 0)
        )).fill()
        NSBezierPath(rect: NSRect(
            x: imageRect.minX,
            y: cropViewRect.minY,
            width: max(cropViewRect.minX - imageRect.minX, 0),
            height: cropViewRect.height
        )).fill()
        NSBezierPath(rect: NSRect(
            x: cropViewRect.maxX,
            y: cropViewRect.minY,
            width: max(imageRect.maxX - cropViewRect.maxX, 0),
            height: cropViewRect.height
        )).fill()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: cropViewRect)
        border.lineWidth = isMovingCrop ? 2.5 : 1.5
        border.stroke()

        CropHandle.allCases.forEach { handle in
            let rect = handleRect(for: handle, cropViewRect: cropViewRect)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            NSColor.controlAccentColor.setStroke()
            let handlePath = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            handlePath.lineWidth = 1.2
            handlePath.stroke()
        }
    }

    private func viewRect(for imageSpaceRect: NSRect, imageRect: NSRect, imageSize: NSSize) -> NSRect {
        NSRect(
            x: imageRect.minX + (imageSpaceRect.minX / imageSize.width) * imageRect.width,
            y: imageRect.minY + (imageSpaceRect.minY / imageSize.height) * imageRect.height,
            width: (imageSpaceRect.width / imageSize.width) * imageRect.width,
            height: (imageSpaceRect.height / imageSize.height) * imageRect.height
        )
    }

    private func handleRect(for handle: CropHandle, cropViewRect: NSRect) -> NSRect {
        let center: NSPoint

        switch handle {
        case .topLeft:
            center = NSPoint(x: cropViewRect.minX, y: cropViewRect.maxY)
        case .top:
            center = NSPoint(x: cropViewRect.midX, y: cropViewRect.maxY)
        case .topRight:
            center = NSPoint(x: cropViewRect.maxX, y: cropViewRect.maxY)
        case .right:
            center = NSPoint(x: cropViewRect.maxX, y: cropViewRect.midY)
        case .bottomRight:
            center = NSPoint(x: cropViewRect.maxX, y: cropViewRect.minY)
        case .bottom:
            center = NSPoint(x: cropViewRect.midX, y: cropViewRect.minY)
        case .bottomLeft:
            center = NSPoint(x: cropViewRect.minX, y: cropViewRect.minY)
        case .left:
            center = NSPoint(x: cropViewRect.minX, y: cropViewRect.midY)
        }

        return NSRect(
            x: center.x - cropHandleSize / 2,
            y: center.y - cropHandleSize / 2,
            width: cropHandleSize,
            height: cropHandleSize
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
}

private enum CropHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var adjustsLeft: Bool {
        self == .topLeft || self == .left || self == .bottomLeft
    }

    var adjustsRight: Bool {
        self == .topRight || self == .right || self == .bottomRight
    }

    var adjustsTop: Bool {
        self == .topLeft || self == .top || self == .topRight
    }

    var adjustsBottom: Bool {
        self == .bottomLeft || self == .bottom || self == .bottomRight
    }
}

private enum AnnotationInteraction {
    case move(index: Int, startPoint: NSPoint, original: ImageAnnotation)
    case resize(index: Int, handle: CropHandle, startBounds: NSRect, original: ImageAnnotation)
}

private enum ImageAnnotation {
    case arrow(NSPoint, NSPoint, NSColor, CGFloat)
    case line(NSPoint, NSPoint, NSColor, CGFloat)
    case rectangle(NSRect, NSColor, CGFloat)
    case oval(NSRect, NSColor, CGFloat)
    case marker([NSPoint], NSColor, CGFloat)
    case text(String, NSPoint, NSColor, CGFloat)
    case mosaic(NSRect)

    func draw(baseImage: NSImage, scale: CGFloat) {
        switch self {
        case .arrow(let start, let end, let color, let lineWidth):
            drawLine(start: start, end: end, color: color, lineWidth: lineWidth)
            drawArrowHead(start: start, end: end, color: color, lineWidth: lineWidth)
        case .line(let start, let end, let color, let lineWidth):
            drawLine(start: start, end: end, color: color, lineWidth: lineWidth)
        case .rectangle(let rect, let color, let lineWidth):
            drawRectangle(rect, color: color, lineWidth: lineWidth)
        case .oval(let rect, let color, let lineWidth):
            drawOval(rect, color: color, lineWidth: lineWidth)
        case .marker(let points, let color, let lineWidth):
            drawMarker(points: points, color: color, lineWidth: lineWidth)
        case .text(let text, let point, let color, let fontSize):
            drawText(text, at: point, color: color, fontSize: fontSize)
        case .mosaic(let rect):
            drawMosaic(rect: rect, baseImage: baseImage)
        }
    }

    func bounds(baseImage: NSImage) -> NSRect {
        switch self {
        case .arrow(let start, let end, _, let lineWidth),
             .line(let start, let end, _, let lineWidth):
            return boundingRect(for: [start, end])
                .insetBy(dx: -max(lineWidth + 12, 16), dy: -max(lineWidth + 12, 16))
        case .rectangle(let rect, _, _),
             .oval(let rect, _, _),
             .mosaic(let rect):
            return normalizedRect(rect)
        case .marker(let points, _, let lineWidth):
            return boundingRect(for: points)
                .insetBy(dx: -max(lineWidth * 1.4, 12), dy: -max(lineWidth * 1.4, 12))
        case .text(let text, let point, _, let fontSize):
            let size = textSize(text, fontSize: fontSize)
            return NSRect(origin: point, size: size).insetBy(dx: -5, dy: -5)
        }
    }

    func hitTest(_ point: NSPoint, baseImage: NSImage, tolerance: CGFloat) -> Bool {
        switch self {
        case .arrow(let start, let end, _, let lineWidth),
             .line(let start, let end, _, let lineWidth):
            return distance(from: point, toSegmentFrom: start, to: end) <= max(tolerance, lineWidth + 8)
        case .rectangle(let rect, _, _),
             .oval(let rect, _, _),
             .mosaic(let rect):
            return normalizedRect(rect)
                .insetBy(dx: -tolerance, dy: -tolerance)
                .contains(point)
        case .marker(let points, _, let lineWidth):
            guard points.count > 1 else {
                return bounds(baseImage: baseImage).contains(point)
            }

            let allowedDistance = max(tolerance, lineWidth * 1.7)
            return zip(points, points.dropFirst()).contains { start, end in
                distance(from: point, toSegmentFrom: start, to: end) <= allowedDistance
            }
        case .text:
            return bounds(baseImage: baseImage)
                .insetBy(dx: -tolerance, dy: -tolerance)
                .contains(point)
        }
    }

    func moved(by delta: NSSize) -> ImageAnnotation {
        switch self {
        case .arrow(let start, let end, let color, let lineWidth):
            return .arrow(start.offsetBy(dx: delta.width, dy: delta.height), end.offsetBy(dx: delta.width, dy: delta.height), color, lineWidth)
        case .line(let start, let end, let color, let lineWidth):
            return .line(start.offsetBy(dx: delta.width, dy: delta.height), end.offsetBy(dx: delta.width, dy: delta.height), color, lineWidth)
        case .rectangle(let rect, let color, let lineWidth):
            return .rectangle(rect.offsetBy(dx: delta.width, dy: delta.height), color, lineWidth)
        case .oval(let rect, let color, let lineWidth):
            return .oval(rect.offsetBy(dx: delta.width, dy: delta.height), color, lineWidth)
        case .marker(let points, let color, let lineWidth):
            return .marker(points.map { $0.offsetBy(dx: delta.width, dy: delta.height) }, color, lineWidth)
        case .text(let text, let point, let color, let fontSize):
            return .text(text, point.offsetBy(dx: delta.width, dy: delta.height), color, fontSize)
        case .mosaic(let rect):
            return .mosaic(rect.offsetBy(dx: delta.width, dy: delta.height))
        }
    }

    func resized(from oldBounds: NSRect, to newBounds: NSRect) -> ImageAnnotation {
        let safeOldBounds = oldBounds.width > 0 && oldBounds.height > 0
            ? oldBounds
            : NSRect(x: oldBounds.minX, y: oldBounds.minY, width: 1, height: 1)

        switch self {
        case .arrow(let start, let end, let color, let lineWidth):
            return .arrow(transform(start, from: safeOldBounds, to: newBounds), transform(end, from: safeOldBounds, to: newBounds), color, lineWidth)
        case .line(let start, let end, let color, let lineWidth):
            return .line(transform(start, from: safeOldBounds, to: newBounds), transform(end, from: safeOldBounds, to: newBounds), color, lineWidth)
        case .rectangle(_, let color, let lineWidth):
            return .rectangle(newBounds, color, lineWidth)
        case .oval(_, let color, let lineWidth):
            return .oval(newBounds, color, lineWidth)
        case .marker(let points, let color, let lineWidth):
            return .marker(points.map { transform($0, from: safeOldBounds, to: newBounds) }, color, lineWidth)
        case .text(let text, _, let color, let fontSize):
            let scale = max(newBounds.width / max(safeOldBounds.width, 1), newBounds.height / max(safeOldBounds.height, 1))
            let newFontSize = min(max(fontSize * scale, 8), 160)
            return .text(text, NSPoint(x: newBounds.minX + 5, y: newBounds.minY + 5), color, newFontSize)
        case .mosaic:
            return .mosaic(newBounds)
        }
    }

    private func drawLine(start: NSPoint, end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func drawRectangle(_ rect: NSRect, color: NSColor, lineWidth: CGFloat) {
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        let path = NSBezierPath(roundedRect: rect, xRadius: min(8, rect.width / 5), yRadius: min(8, rect.height / 5))
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func drawOval(_ rect: NSRect, color: NSColor, lineWidth: CGFloat) {
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private func drawArrowHead(start: NSPoint, end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 18
        let spread = CGFloat.pi / 7
        let left = NSPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let right = NSPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        let path = NSBezierPath()
        path.move(to: left)
        path.line(to: end)
        path.line(to: right)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func drawMarker(points: [NSPoint], color: NSColor, lineWidth: CGFloat) {
        guard let first = points.first else {
            return
        }

        let path = NSBezierPath()
        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = max(lineWidth * 2.4, lineWidth + 4)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.withAlphaComponent(0.72).setStroke()
        path.stroke()
    }

    private func drawText(_ text: String, at point: NSPoint, color: NSColor, fontSize: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .strokeColor: NSColor.black.withAlphaComponent(0.45),
            .strokeWidth: -2
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        attributedText.draw(at: point)
    }

    private func drawMosaic(rect: NSRect, baseImage: NSImage) {
        guard rect.width > 2, rect.height > 2 else {
            return
        }

        let blockSize: CGFloat = 14
        let smallSize = NSSize(width: max(1, ceil(rect.width / blockSize)), height: max(1, ceil(rect.height / blockSize)))
        let pixelatedImage = NSImage(size: smallSize)

        pixelatedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .low
        baseImage.draw(
            in: NSRect(origin: .zero, size: smallSize),
            from: rect,
            operation: .copy,
            fraction: 1
        )
        pixelatedImage.unlockFocus()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        pixelatedImage.draw(
            in: rect,
            from: NSRect(origin: .zero, size: smallSize),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.12).setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1
        border.stroke()
    }

    private func boundingRect(for points: [NSPoint]) -> NSRect {
        guard let first = points.first else {
            return .zero
        }

        let minX = points.reduce(first.x) { min($0, $1.x) }
        let maxX = points.reduce(first.x) { max($0, $1.x) }
        let minY = points.reduce(first.y) { min($0, $1.y) }
        let maxY = points.reduce(first.y) { max($0, $1.y) }
        return NSRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    private func normalizedRect(_ rect: NSRect) -> NSRect {
        NSRect(
            x: min(rect.minX, rect.maxX),
            y: min(rect.minY, rect.maxY),
            width: abs(rect.width),
            height: abs(rect.height)
        )
    }

    private func textSize(_ text: String, fontSize: CGFloat) -> NSSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        ]
        return NSAttributedString(string: text, attributes: attributes).size()
    }

    private func transform(_ point: NSPoint, from oldBounds: NSRect, to newBounds: NSRect) -> NSPoint {
        let relativeX = (point.x - oldBounds.minX) / max(oldBounds.width, 1)
        let relativeY = (point.y - oldBounds.minY) / max(oldBounds.height, 1)
        return NSPoint(
            x: newBounds.minX + relativeX * newBounds.width,
            y: newBounds.minY + relativeY * newBounds.height
        )
    }

    private func distance(from point: NSPoint, toSegmentFrom start: NSPoint, to end: NSPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let projection = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let closest = NSPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - closest.x, point.y - closest.y)
    }
}

private extension NSPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> NSPoint {
        NSPoint(x: x + dx, y: y + dy)
    }
}

enum ImageEditingService {
    static func rotate(_ image: NSImage, clockwise: Bool) -> NSImage {
        let sourceSize = image.size
        let targetSize = NSSize(width: sourceSize.height, height: sourceSize.width)
        let output = NSImage(size: targetSize)

        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let transform = NSAffineTransform()
        if clockwise {
            transform.translateX(by: targetSize.width, yBy: 0)
            transform.rotate(byDegrees: 90)
        } else {
            transform.translateX(by: 0, yBy: targetSize.height)
            transform.rotate(byDegrees: -90)
        }
        transform.concat()

        image.draw(
            in: NSRect(origin: .zero, size: sourceSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()

        return output
    }

    static func flipHorizontal(_ image: NSImage) -> NSImage {
        let sourceSize = image.size
        let output = NSImage(size: sourceSize)

        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let transform = NSAffineTransform()
        transform.translateX(by: sourceSize.width, yBy: 0)
        transform.scaleX(by: -1, yBy: 1)
        transform.concat()

        image.draw(
            in: NSRect(origin: .zero, size: sourceSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()

        return output
    }

    static func saveCopy(_ image: NSImage, sourceURL: URL) throws -> URL {
        let destinationURL = uniqueEditedURL(for: sourceURL)
        try write(image, to: destinationURL)
        return destinationURL
    }

    static func write(_ image: NSImage, to url: URL) throws {
        let data = try imageData(for: image, url: url)
        try data.write(to: url, options: .atomic)
    }

    private static func imageData(for image: NSImage, url: URL) throws -> Data {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageEditingError.renderFailed
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg":
            guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
                throw ImageEditingError.renderFailed
            }
            return data
        case "tif", "tiff":
            guard let data = bitmap.representation(using: .tiff, properties: [:]) else {
                throw ImageEditingError.renderFailed
            }
            return data
        case "png":
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw ImageEditingError.renderFailed
            }
            return data
        default:
            throw ImageEditingError.unsupportedReplaceFormat
        }
    }

    private static func uniqueEditedURL(for sourceURL: URL) -> URL {
        let folderURL = sourceURL.deletingLastPathComponent()
        let baseName = "\(sourceURL.deletingPathExtension().lastPathComponent) Edited"
        var candidate = folderURL.appending(path: "\(baseName).png")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folderURL.appending(path: "\(baseName) \(suffix).png")
            suffix += 1
        }

        return candidate
    }
}

enum ImageEditingError: LocalizedError {
    case renderFailed
    case unsupportedReplaceFormat

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Could not render edited image."
        case .unsupportedReplaceFormat:
            return "This file type cannot be replaced directly. Use Save Copy."
        }
    }
}
