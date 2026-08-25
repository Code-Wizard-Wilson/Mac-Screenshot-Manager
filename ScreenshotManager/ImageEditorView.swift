import AppKit
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
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
    @StateObject private var keyboardMonitor = AnnotationKeyboardMonitor()
    @StateObject private var exportController = CaptureExportController()
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
                    if showsBackgroundPanel {
                        MockupWorkspaceView(document: document)
                    } else {
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                annotationToolbar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(minHeight: showsBackgroundPanel ? 54 : 86, alignment: .top)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(AppTheme.softBorder.opacity(0.7))
                            .frame(height: 0.6)
                    }
                    .layoutPriority(1)
            }

            if showsBackgroundPanel {
                Divider()
                BackgroundInspectorView(
                    document: document,
                    onBack: { showsBackgroundPanel = false }
                )
                .frame(width: 280)
                .layoutPriority(2)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
        .onExitCommand {
            store.closeCaptureEditor(animated: true)
        }
        .onAppear(perform: installKeyboardMonitor)
        .onDisappear(perform: removeKeyboardMonitor)
    }

    private var annotationToolbar: some View {
        Group {
            if showsBackgroundPanel {
                HStack(spacing: 10) {
                    Text(captureHint)
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 10)

                    toolbarUtilityButton("pin", title: "Pin as floating reference window") {
                        pinCurrentImage()
                    }

                    toolbarUtilityButton("xmark", title: "Close") {
                        store.closeCaptureEditor()
                    }
                    .keyboardShortcut(.cancelAction)

                    outputActions
                }
                .frame(height: 34)
            } else {
                VStack(spacing: 7) {
                    HStack(spacing: 10) {
                        toolbarCluster(title: "TOOLS") {
                            toolButton(.arrow)
                            toolButton(.line)
                            toolButton(.rectangle)
                            toolButton(.oval)
                            toolButton(.marker)
                            toolButton(.text)
                            toolButton(.mosaic)
                        }

                        toolbarCluster(title: "ADJUST") {
                            toolbarActionButton(
                                "crop",
                                title: "Reset Crop",
                                isEnabled: document.isCropAdjusted
                            ) {
                                document.resetCrop()
                            }

                            toolbarActionButton("rotate.left", title: "Rotate Left") {
                                document.rotate(clockwise: false)
                            }

                            toolbarActionButton("rotate.right", title: "Rotate Right") {
                                document.rotate(clockwise: true)
                            }

                            toolbarActionButton(
                                "arrow.left.and.right.righttriangle.left.righttriangle.right",
                                title: "Flip Horizontal"
                            ) {
                                document.flipHorizontal()
                            }

                            toolbarActionButton(
                                "arrow.uturn.backward",
                                title: "Undo",
                                isEnabled: !document.annotations.isEmpty
                            ) {
                                document.undo()
                            }
                            .keyboardShortcut("z", modifiers: .command)
                        }

                        Spacer(minLength: 10)

                        toolbarUtilityButton("pin", title: "Pin as floating reference window") {
                            pinCurrentImage()
                        }

                        toolbarUtilityButton("xmark", title: "Close") {
                            store.closeCaptureEditor()
                        }
                        .keyboardShortcut(.cancelAction)

                        outputActions
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 10) {
                            HStack(spacing: 7) {
                                Image(systemName: tool.systemImage)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(tool.title)
                                    .font(AppTypography.helper.weight(.semibold))
                            }
                            .frame(minWidth: 72, alignment: .leading)

                            if tool.usesColor {
                                Divider().frame(height: 18)
                                colorPicker
                            }

                            if tool.usesStrokeWidth {
                                Divider().frame(height: 18)
                                strokeWidthControl
                            }

                            if tool == .text {
                                Divider().frame(height: 18)
                                TextField("Text", text: $textValue)
                                    .textFieldStyle(.plain)
                                    .font(AppTypography.helper)
                                    .padding(.horizontal, 9)
                                    .frame(width: 190, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.primary.opacity(0.065))
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(AppTheme.softBorder, lineWidth: 0.7)
                                    }
                            } else if tool == .mosaic {
                                Divider().frame(height: 18)
                                Text("Drag over an area to pixelate")
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.softBorder.opacity(0.65), lineWidth: 0.7)
                        }

                        Spacer(minLength: 8)

                        mockupButton

                        Text(captureHint)
                            .font(AppTypography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(height: 34)
                }
            }
        }
    }

    private var captureHint: String {
        if exportController.isWorking {
            return exportController.statusText
        }
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

    private var finishActionTitle: String {
        switch session.destination {
        case .capture(.clipboard): return "Copy"
        case .capture(.save): return "Save"
        case .edit: return "Update"
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

    private var showsSecondarySaveAction: Bool {
        switch session.destination {
        case .capture(.save):
            return false
        case .capture(.clipboard), .edit:
            return true
        }
    }

    private var secondarySaveTitle: String {
        switch session.destination {
        case .edit:
            return "Save Copy"
        case .capture:
            return "Save"
        }
    }

    private func saveToLibrary() {
        exportController.run(
            document: document,
            store: store,
            destination: .capture(.save)
        )
    }

    private func toolButton(_ value: AnnotationTool) -> some View {
        let isSelected = tool == value

        return Button {
            tool = value
        } label: {
            Image(systemName: value.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.72))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .help(value.title)
    }

    @ViewBuilder
    private func toolbarCluster<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.55)
                .foregroundStyle(.secondary)
                .padding(.leading, 5)
                .padding(.trailing, 3)

            Divider()
                .frame(height: 17)
                .opacity(0.65)

            content()
        }
        .padding(.horizontal, 4)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.softBorder.opacity(0.7), lineWidth: 0.7)
        }
    }

    private func toolbarActionButton(
        _ systemName: String,
        title: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(isEnabled ? 0.72 : 0.28))
                .frame(width: 29, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(title)
    }

    private func toolbarUtilityButton(
        _ systemName: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.68))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.softBorder.opacity(0.65), lineWidth: 0.7)
        }
        .help(title)
    }

    private var actionButtonWidth: CGFloat { 96 }

    private var outputActions: some View {
        HStack(spacing: 6) {
            if showsSecondarySaveAction {
                Button {
                    saveToLibrary()
                } label: {
                    Label(secondarySaveTitle, systemImage: "tray.and.arrow.down")
                        .font(AppTypography.helper.weight(.semibold))
                        .frame(width: actionButtonWidth, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(exportController.isWorking ? 0.38 : 0.78))
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.065))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppTheme.softBorder.opacity(0.8), lineWidth: 0.8)
                }
                .disabled(exportController.isWorking)
                .help("Save the current result as a file in the Screenshot Manager library")
            }

            Button {
                finishCapture()
            } label: {
                HStack(spacing: 6) {
                    if exportController.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text(exportController.buttonTitle)
                    } else {
                        Image(systemName: finishActionIcon)
                        Text(finishActionTitle)
                        Text("↩")
                            .foregroundStyle(Color.white.opacity(0.68))
                    }
                }
                .font(AppTypography.helper.weight(.semibold))
                .frame(width: exportController.isWorking ? actionButtonWidth + 34 : actionButtonWidth + 8, height: 30)
                .animation(.easeOut(duration: 0.12), value: exportController.isWorking)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(exportController.isWorking ? 0.78 : 1))
            )
            .disabled(exportController.isWorking)
            .keyboardShortcut(.defaultAction)
            .help("\(finishActionHelp) — Return")
        }
        .padding(.leading, 2)
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

            SmoothValueSlider(value: $strokeWidth, range: 2...18, step: 1)
                .frame(width: 112, height: 18)

            Text("\(Int(strokeWidth))")
                .font(AppTypography.helper.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
        }
        .help("Stroke Width")
    }

    private var mockupButton: some View {
        Button {
            showsBackgroundPanel.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: showsBackgroundPanel ? "arrow.left" : "photo.on.rectangle.angled")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(showsBackgroundPanel ? "Back to Annotate" : "Mockup")
                    .font(AppTypography.helper.weight(.semibold))
            }
            .foregroundStyle(
                showsBackgroundPanel
                    || document.backgroundSettings.style != .none
                    || document.selectedPhotoMockup != nil
                    || document.selectedDeviceBezel != nil
                    ? Color.accentColor
                    : Color.primary.opacity(0.72)
            )
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    showsBackgroundPanel
                        || document.backgroundSettings.style != .none
                        || document.selectedPhotoMockup != nil
                        || document.selectedDeviceBezel != nil
                        ? Color.accentColor.opacity(0.11)
                        : Color.primary.opacity(0.045)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    showsBackgroundPanel ? Color.accentColor.opacity(0.42) : AppTheme.softBorder.opacity(0.7),
                    lineWidth: 0.8
                )
        }
        .help(showsBackgroundPanel ? "Back to Annotate" : "Open Mockup & Background")
    }

    private var liveTextButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
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
        exportController.run(
            document: document,
            store: store,
            destination: session.destination
        )
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
        let destination = session.destination

        keyboardMonitor.install { [weak store, weak document, weak exportController] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isReturn = event.keyCode == 36 || event.keyCode == 76

            if event.keyCode == 53 {
                store?.closeCaptureEditor(animated: true)
                return nil
            }

            let blockingModifiers = flags.intersection([.shift, .option, .control])
            let returnShouldFinish = isReturn && blockingModifiers.isEmpty

            guard returnShouldFinish,
                  let store,
                  let document,
                  let exportController else {
                return event
            }

            exportController.run(document: document, store: store, destination: destination)
            return nil
        }
    }

    private func removeKeyboardMonitor() {
        keyboardMonitor.remove()
    }
}

@MainActor
private final class AnnotationKeyboardMonitor: ObservableObject {
    private var monitor: Any?

    func install(handler: @escaping (NSEvent) -> NSEvent?) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func remove() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

private struct BackgroundInspectorView: View {
    @ObservedObject var document: AnnotationDocument
    let onBack: () -> Void
    @StateObject private var photoLibrary = PhotoMockupLibrary.shared
    @State private var mockupError: String?
    @State private var expandedFamily: PhotoMockupFamily?
    @State private var expandedModelKey: String?

    private let swatchColumns = [GridItem(.adaptive(minimum: 38), spacing: 7)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                )
                .help("Back to Annotate")

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mockup")
                        .font(AppTypography.sectionTitle)
                    Text("Device & background")
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inspectorCard(title: "Device", systemImage: "laptopcomputer.and.iphone") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(PhotoMockupFamily.allCases) { family in
                                familySection(family)
                            }

                            if let mockupError {
                                Text(mockupError)
                                    .font(AppTypography.helper)
                                    .foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 3)
                            }

                            if document.hasSelectedMockup {
                                Button {
                                    document.selectedPhotoMockup = nil
                                    document.selectedDeviceBezel = nil
                                    document.resetMockupTransform()
                                } label: {
                                    Label("Remove device", systemImage: "xmark.circle")
                                        .font(AppTypography.metadata.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }
                        }
                    }

                    if document.hasSelectedMockup {
                        inspectorCard(title: "Transform", systemImage: "move.3d") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Position & angle")
                                        .font(AppTypography.metadata)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Reset") {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            document.resetMockupTransform()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(AppTypography.metadata.weight(.medium))
                                    .foregroundStyle(Color.accentColor)
                                    .disabled(document.mockupTransform.isIdentity)
                                }

                                mockupTransformSlider(
                                    title: "Zoom",
                                    value: Binding(
                                        get: { document.mockupTransform.zoom },
                                        set: { newValue in updateMockupTransform { $0.zoom = newValue } }
                                    ),
                                    range: 0.5...1.8,
                                    step: 0.01,
                                    display: { "\(Int(round($0 * 100)))%" }
                                )

                                mockupTransformSlider(
                                    title: "Tilt",
                                    value: Binding(
                                        get: { document.mockupTransform.tiltDegrees },
                                        set: { newValue in updateMockupTransform { $0.tiltDegrees = newValue } }
                                    ),
                                    range: -25...25,
                                    step: 1,
                                    display: { "\(Int(round($0)))°" }
                                )

                                mockupTransformSlider(
                                    title: "X",
                                    value: Binding(
                                        get: { document.mockupTransform.offsetX },
                                        set: { newValue in updateMockupTransform { $0.offsetX = newValue } }
                                    ),
                                    range: -0.35...0.35,
                                    step: 0.01,
                                    display: { "\(Int(round($0 * 100)))%" }
                                )

                                mockupTransformSlider(
                                    title: "Y",
                                    value: Binding(
                                        get: { document.mockupTransform.offsetY },
                                        set: { newValue in updateMockupTransform { $0.offsetY = newValue } }
                                    ),
                                    range: -0.35...0.35,
                                    step: 0.01,
                                    display: { "\(Int(round($0 * 100)))%" }
                                )
                            }
                        }
                    }


                    inspectorCard(title: "Background", systemImage: "square.on.square") {
                        VStack(alignment: .leading, spacing: 10) {
                            LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: 7) {
                                backgroundSwatch(.none)
                                ForEach(AnnotationBackgroundStyle.backgroundCases) { style in
                                    backgroundSwatch(style)
                                }
                            }

                            if document.backgroundSettings.style != .none {
                                inspectorSlider(title: "Spacing", value: Binding(
                                    get: { document.backgroundSettings.padding },
                                    set: { newValue in updateSettings { $0.padding = newValue } }
                                ), range: 0...180, step: 4)

                                inspectorSlider(title: "Corners", value: Binding(
                                    get: { document.backgroundSettings.cornerRadius },
                                    set: { newValue in updateSettings { $0.cornerRadius = newValue } }
                                ), range: 0...64, step: 2)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .background {
            VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
        }
    }

    private func inspectorCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(AppTypography.helper.weight(.semibold))
                Spacer()
            }

            content()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.softBorder.opacity(0.65), lineWidth: 0.7)
        }
    }

    @ViewBuilder
    private func familySection(_ family: PhotoMockupFamily) -> some View {
        let models = photoLibrary.models(in: family)
        let isExpanded = expandedFamily == family

        VStack(alignment: .leading, spacing: 4) {
            Button {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    mockupError = nil
                    expandedFamily = isExpanded ? nil : family
                    expandedModelKey = nil
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: family.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 26)
                        .foregroundStyle(.secondary)
                    Text(family.title)
                        .font(AppTypography.helper.weight(.semibold))
                    Spacer(minLength: 0)
                    if models.isEmpty {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    } else {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 36)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isExpanded ? Color.accentColor.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .disabled(models.isEmpty)

            if isExpanded {
                ForEach(models, id: \.self) { model in
                    modelSection(family: family, model: model)
                }
            }
        }
    }

    @ViewBuilder
    private func modelSection(family: PhotoMockupFamily, model: String) -> some View {
        let key = "\(family.rawValue)|\(model)"
        let variants = photoLibrary.variants(family: family, model: model)
        let isExpanded = expandedModelKey == key
        let selectedPreset = document.selectedPhotoMockup.flatMap { photoLibrary.preset(id: $0.presetID) }
        let isSelectedModel = selectedPreset?.family == family && selectedPreset?.model == model

        VStack(alignment: .leading, spacing: 3) {
            Button {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    mockupError = nil
                    expandedModelKey = isExpanded ? nil : key
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                    Text(model)
                        .font(AppTypography.helper.weight(isSelectedModel ? .semibold : .regular))
                        .foregroundStyle(isSelectedModel ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelectedModel {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.leading, 13)
                .padding(.trailing, 8)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(variants) { preset in
                    photoPresetButton(preset)
                        .padding(.leading, 24)
                }
            }
        }
    }

    private func photoPresetButton(_ preset: PhotoMockupPreset) -> some View {
        let isSelected = document.selectedPhotoMockup?.presetID == preset.id

        return Button {
            mockupError = nil
            guard let asset = photoLibrary.resolve(preset) else {
                mockupError = "This device resource is missing from the app bundle."
                return
            }
            document.selectedDeviceBezel = nil
            document.selectedPhotoMockup = asset
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                    Image(systemName: preset.orientation == .landscape ? "rectangle" : "rectangle.portrait")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .frame(width: 28, height: 25)

                Text(preset.variantTitle.isEmpty ? "Default" : preset.variantTitle)
                    .font(AppTypography.metadata)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 31)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func mockupTransformSlider(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        display: @escaping (CGFloat) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(AppTypography.helper)
                Spacer()
                Text(display(value.wrappedValue))
                    .font(AppTypography.metadata.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42, alignment: .trailing)
            }
            SmoothValueSlider(
                value: value,
                range: range,
                step: step,
                onEditingChanged: { isEditing in
                    document.setMockupInteraction(isEditing)
                }
            )
            .frame(height: 18)
        }
    }

    private func updateMockupTransform(_ update: (inout MockupTransformSettings) -> Void) {
        var settings = document.mockupTransform
        update(&settings)
        document.mockupTransform = settings
    }

    private func backgroundSwatch(_ style: AnnotationBackgroundStyle) -> some View {
        Button { updateSettings { $0.style = style } } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(style.swatch)
                if style == .none {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 38)
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

    private func inspectorSlider(title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(AppTypography.helper)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(AppTypography.metadata.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42, alignment: .trailing)
            }
            SmoothValueSlider(value: value, range: range, step: step)
                .frame(height: 18)
                .disabled(document.backgroundSettings.autoBalance)
                .opacity(document.backgroundSettings.autoBalance ? 0.45 : 1)
        }
    }

    private func updateSettings(_ update: (inout AnnotationBackgroundSettings) -> Void) {
        var settings = document.backgroundSettings
        update(&settings)
        document.backgroundSettings = settings
    }
}

private enum MockupMoveTarget: String, CaseIterable, Identifiable {
    case device
    case screen

    var id: String { rawValue }
    var title: String { self == .device ? "Device" : "Screen" }
    var systemImage: String { self == .device ? "move.3d" : "rectangle.and.hand.point.up.left" }
}

private struct MockupWorkspaceView: View {
    @ObservedObject var document: AnnotationDocument
    @StateObject private var renderer = MockupPreviewRenderer()
    @State private var dragStartOffset: CGPoint?
    @State private var dragStartScreenOffset: CGPoint?
    @State private var moveTarget: MockupMoveTarget = .device

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("Preview")
                    .font(AppTypography.sectionTitle)

                if let scene = document.selectedPhotoMockup {
                    Text(scene.name)
                        .font(AppTypography.helper)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let bezel = document.selectedDeviceBezel {
                    Text(bezel.name)
                        .font(AppTypography.helper)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if document.hasSelectedMockup {
                    HStack(spacing: 2) {
                        ForEach(MockupMoveTarget.allCases) { target in
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    moveTarget = target
                                }
                                document.flashMockupGrid()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: target.systemImage)
                                        .font(.system(size: 9.5, weight: .semibold))
                                    Text(target.title)
                                        .font(AppTypography.metadata.weight(.semibold))
                                }
                                .foregroundStyle(moveTarget == target ? Color.white : Color.secondary)
                                .padding(.horizontal, 7)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(moveTarget == target ? Color.accentColor : Color.clear)
                                )
                                .scaleEffect(moveTarget == target ? 1 : 0.985)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.softBorder.opacity(0.7), lineWidth: 0.7)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.ultraThinMaterial)

            Divider()

            GeometryReader { proxy in
                let transform = document.mockupTransform
                let horizontalOffset = transform.offsetX * proxy.size.width * 0.72
                let verticalOffset = -transform.offsetY * proxy.size.height * 0.72

                ZStack {
                    if document.backgroundSettings.style != .none {
                        RoundedRectangle(
                            cornerRadius: min(max(document.backgroundSettings.cornerRadius * 0.45, 10), 30),
                            style: .continuous
                        )
                        .fill(document.backgroundSettings.style.swatch)
                        .padding(22)
                    }

                    if let previewFrame = renderer.frame {
                        mockupPreviewContent(
                            frame: previewFrame,
                            in: proxy.size,
                            transform: transform,
                            horizontalOffset: horizontalOffset,
                            verticalOffset: verticalOffset
                        )
                    } else {
                        Image(nsImage: document.image)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFit()
                            .padding(34)
                            .opacity(0.72)
                    }

                    if document.showsMockupGrid {
                        MockupAlignmentGrid(
                            centeredX: moveTarget == .device
                                ? abs(document.mockupTransform.offsetX) < 0.012
                                : abs(document.mockupScreenFraming.offsetX) < 0.03,
                            centeredY: moveTarget == .device
                                ? abs(document.mockupTransform.offsetY) < 0.012
                                : abs(document.mockupScreenFraming.offsetY) < 0.03
                        )
                        .padding(22)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            guard document.hasSelectedMockup else { return }

                            switch moveTarget {
                            case .device:
                                if dragStartOffset == nil {
                                    dragStartOffset = CGPoint(
                                        x: document.mockupTransform.offsetX,
                                        y: document.mockupTransform.offsetY
                                    )
                                    document.setMockupInteraction(true)
                                }

                                guard let start = dragStartOffset else { return }
                                let xScale = max(proxy.size.width * 0.72, 1)
                                let yScale = max(proxy.size.height * 0.72, 1)
                                var newX = start.x + gesture.translation.width / xScale
                                var newY = start.y - gesture.translation.height / yScale

                                newX = min(max(newX, -0.45), 0.45)
                                newY = min(max(newY, -0.45), 0.45)
                                if abs(newX) < 0.018 { newX = 0 }
                                if abs(newY) < 0.018 { newY = 0 }

                                var updated = document.mockupTransform
                                updated.offsetX = newX
                                updated.offsetY = newY
                                document.mockupTransform = updated

                            case .screen:
                                guard let layers = renderer.frame?.layers else { return }

                                if dragStartScreenOffset == nil {
                                    var framing = document.mockupScreenFraming
                                    if framing.zoom < 1.18 {
                                        framing.zoom = 1.18
                                        document.mockupScreenFraming = framing
                                    }
                                    dragStartScreenOffset = CGPoint(
                                        x: framing.offsetX,
                                        y: framing.offsetY
                                    )
                                    document.setMockupInteraction(true)
                                }

                                guard let start = dragStartScreenOffset else { return }
                                let metrics = screenMotionMetrics(
                                    for: layers,
                                    canvasSize: proxy.size,
                                    zoom: document.mockupScreenFraming.zoom
                                )
                                let maxX = max(metrics.maxOffsetX, 0.5)
                                let maxY = max(metrics.maxOffsetY, 0.5)
                                let startVisualX = -start.x * maxX
                                let startVisualY = start.y * maxY
                                let visualX = min(max(startVisualX + gesture.translation.width, -maxX), maxX)
                                let visualY = min(max(startVisualY + gesture.translation.height, -maxY), maxY)

                                var framing = document.mockupScreenFraming
                                framing.offsetX = min(max(-visualX / maxX, -1), 1)
                                framing.offsetY = min(max(visualY / maxY, -1), 1)
                                if abs(visualX) < 2 { framing.offsetX = 0 }
                                if abs(visualY) < 2 { framing.offsetY = 0 }
                                document.mockupScreenFraming = framing
                            }
                        }
                        .onEnded { _ in
                            switch moveTarget {
                            case .device:
                                dragStartOffset = nil
                            case .screen:
                                dragStartScreenOffset = nil
                            }
                            document.setMockupInteraction(false)
                        }
                )
                .onTapGesture(count: 2) {
                    guard document.hasSelectedMockup else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        switch moveTarget {
                        case .device:
                            var updated = document.mockupTransform
                            updated.offsetX = 0
                            updated.offsetY = 0
                            document.mockupTransform = updated
                        case .screen:
                            document.mockupScreenFraming = MockupScreenFramingSettings()
                        }
                    }
                    document.flashMockupGrid()
                }
                .clipped()
                .animation(.easeInOut(duration: 0.20), value: document.showsMockupGrid)
            }
            .background {
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
            }
        }
        .onAppear {
            renderer.schedule(document, delayNanoseconds: 20_000_000)
        }
        .onChange(of: document.selectedPhotoMockup) { _, _ in
            document.mockupScreenFraming = MockupScreenFramingSettings()
            renderer.schedule(document, delayNanoseconds: 20_000_000)
        }
        .onChange(of: document.selectedDeviceBezel) { _, _ in
            renderer.schedule(document, delayNanoseconds: 20_000_000)
        }
        .onChange(of: document.cropRect) { _, _ in
            renderer.schedule(document, delayNanoseconds: 35_000_000)
        }
        .onDisappear {
            renderer.cancel()
        }
    }

    @ViewBuilder
    private func mockupPreviewContent(
        frame: MockupPreviewFrame,
        in canvasSize: CGSize,
        transform: MockupTransformSettings,
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat
    ) -> some View {
        if let layers = frame.layers {
            let metrics = screenMotionMetrics(
                for: layers,
                canvasSize: canvasSize,
                zoom: document.mockupScreenFraming.zoom
            )
            let framing = document.mockupScreenFraming
            let liveX = -framing.offsetX * metrics.maxOffsetX
            let liveY = framing.offsetY * metrics.maxOffsetY
            let anchor = UnitPoint(
                x: layers.screenCenter.x,
                y: layers.screenCenter.y
            )

            ZStack {
                ZStack {
                    Image(nsImage: layers.screenImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .scaleEffect(framing.zoom, anchor: anchor)
                        .offset(x: liveX, y: liveY)
                }
                .mask {
                    Image(nsImage: layers.maskImage)
                        .resizable()
                        .scaledToFit()
                }

                Image(nsImage: layers.bezelImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
            .aspectRatio(layers.canvasSize.width / max(layers.canvasSize.height, 1), contentMode: .fit)
            .padding(30)
            .scaleEffect(transform.zoom)
            .rotationEffect(.degrees(transform.tiltDegrees))
            .offset(x: horizontalOffset, y: verticalOffset)
            .compositingGroup()
            .shadow(
                color: document.showsMockupGrid ? Color.black.opacity(0.14) : .clear,
                radius: 7,
                y: 3
            )
        } else if let image = frame.compositeImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(30)
                .scaleEffect(transform.zoom)
                .rotationEffect(.degrees(transform.tiltDegrees))
                .offset(x: horizontalOffset, y: verticalOffset)
                .compositingGroup()
        }
    }

    private func screenMotionMetrics(
        for layers: PhotoMockupPreviewLayers,
        canvasSize: CGSize,
        zoom: CGFloat
    ) -> (maxOffsetX: CGFloat, maxOffsetY: CGFloat) {
        let availableWidth = max(canvasSize.width - 60, 1)
        let availableHeight = max(canvasSize.height - 60, 1)
        let fitScale = min(
            availableWidth / max(layers.canvasSize.width, 1),
            availableHeight / max(layers.canvasSize.height, 1)
        )
        let screenWidth = layers.screenSize.width * fitScale
        let screenHeight = layers.screenSize.height * fitScale
        let extraScale = max(zoom - 1, 0)
        return (
            maxOffsetX: max(screenWidth * extraScale / 2, 0),
            maxOffsetY: max(screenHeight * extraScale / 2, 0)
        )
    }

}

private extension CaptureAnnotationDestination {
    var isClipboardDestination: Bool {
        if case .capture(.clipboard) = self { return true }
        return false
    }
}

@MainActor
private final class CaptureExportController: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var statusText = ""
    @Published private(set) var buttonTitle = "Rendering…"
    private var task: Task<Void, Never>?

    func run(
        document: AnnotationDocument,
        store: ScreenshotStore,
        destination: CaptureAnnotationDestination
    ) {
        guard !isWorking else { return }

        isWorking = true
        statusText = "Rendering full resolution…"
        buttonTitle = "Rendering…"
        let workItem = document.makeCaptureExportWorkItem()

        task?.cancel()
        task = Task { [weak self, weak store] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try workItem.render() }
            }.value

            guard !Task.isCancelled, let self, let store else { return }

            switch result {
            case .success(let output):
                self.statusText = destination.isClipboardDestination ? "Copying to Clipboard…" : "Saving…"
                self.buttonTitle = destination.isClipboardDestination ? "Copying…" : "Saving…"
                await Task.yield()
                let succeeded = store.finishPreparedAnnotatedCapture(output, destination: destination)
                if !succeeded {
                    self.isWorking = false
                    self.statusText = ""
                }
            case .failure(let error):
                self.isWorking = false
                self.statusText = ""
                store.reportCaptureRenderFailure(error)
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

private final class CaptureExportWorkItem: @unchecked Sendable {
    let contentImage: NSImage
    let photoMockup: PhotoMockupAsset?
    let legacyBezel: ImportedDeviceBezel?
    let screenFraming: MockupScreenFramingSettings
    let transform: MockupTransformSettings
    let background: AnnotationBackgroundSettings

    init(
        contentImage: NSImage,
        photoMockup: PhotoMockupAsset?,
        legacyBezel: ImportedDeviceBezel?,
        screenFraming: MockupScreenFramingSettings,
        transform: MockupTransformSettings,
        background: AnnotationBackgroundSettings
    ) {
        self.contentImage = contentImage
        self.photoMockup = photoMockup
        self.legacyBezel = legacyBezel
        self.screenFraming = screenFraming
        self.transform = transform
        self.background = background
    }

    func render() throws -> PreparedCaptureOutput {
        let photoProduct = photoMockup?.renderedImage(
            wrapping: contentImage,
            screenFraming: screenFraming
        )
        let rawProduct = photoProduct ?? legacyBezel?.renderedImage(wrapping: contentImage) ?? contentImage
        let transformed = (photoMockup != nil || legacyBezel != nil)
            ? transform.renderedImage(wrapping: rawProduct)
            : rawProduct
        let finalImage = background.renderedImage(
            wrapping: transformed,
            preserveTransparentEdges: photoMockup != nil || legacyBezel != nil
        )
        return try PreparedCaptureOutput.make(from: finalImage)
    }
}

@MainActor
private final class MockupPreviewRenderer: ObservableObject {
    @Published private(set) var frame: MockupPreviewFrame?
    private var renderLoopTask: Task<Void, Never>?
    private var pendingWorkItem: MockupPreviewWorkItem?
    private var pendingDelayNanoseconds: UInt64 = 0

    func schedule(
        _ document: AnnotationDocument,
        maxPixelSize: Int = 980,
        delayNanoseconds: UInt64 = 50_000_000
    ) {
        pendingWorkItem = document.makeMockupPreviewWorkItem(maxPixelSize: maxPixelSize)
        pendingDelayNanoseconds = delayNanoseconds

        guard renderLoopTask == nil else { return }
        renderLoopTask = Task { [weak self] in
            await self?.drainRenderQueue()
        }
    }

    private func drainRenderQueue() async {
        defer {
            renderLoopTask = nil
            if pendingWorkItem != nil {
                schedulePendingLoop()
            }
        }

        while !Task.isCancelled, let workItem = pendingWorkItem {
            let delay = pendingDelayNanoseconds
            pendingWorkItem = nil
            pendingDelayNanoseconds = 0

            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }

                // A newer request arrived during the debounce window. Skip the stale
                // frame instead of rendering both and making the preview visibly lag.
                if pendingWorkItem != nil {
                    continue
                }
            }

            let renderedFrame = await Task.detached(priority: .userInitiated) {
                autoreleasepool { workItem.render() }
            }.value

            guard !Task.isCancelled else { return }
            frame = renderedFrame
        }
    }

    private func schedulePendingLoop() {
        guard renderLoopTask == nil, pendingWorkItem != nil else { return }
        renderLoopTask = Task { [weak self] in
            await self?.drainRenderQueue()
        }
    }

    func cancel() {
        pendingWorkItem = nil
        renderLoopTask?.cancel()
        renderLoopTask = nil
    }

    deinit {
        renderLoopTask?.cancel()
    }
}

private final class MockupPreviewWorkItem: @unchecked Sendable {
    let contentImage: NSImage
    let photoMockup: PhotoMockupAsset?
    let legacyBezel: ImportedDeviceBezel?
    let screenFraming: MockupScreenFramingSettings
    let maxPixelSize: Int

    init(
        contentImage: NSImage,
        photoMockup: PhotoMockupAsset?,
        legacyBezel: ImportedDeviceBezel?,
        screenFraming: MockupScreenFramingSettings,
        maxPixelSize: Int
    ) {
        self.contentImage = contentImage
        self.photoMockup = photoMockup
        self.legacyBezel = legacyBezel
        self.screenFraming = screenFraming
        self.maxPixelSize = maxPixelSize
    }

    func render() -> MockupPreviewFrame {
        if let photoMockup,
           let layers = photoMockup.previewLayers(
                wrapping: contentImage,
                maxPixelSize: maxPixelSize
           ) {
            return MockupPreviewFrame(compositeImage: nil, layers: layers)
        }

        let legacyProduct = legacyBezel?.renderedImage(wrapping: contentImage)
        return MockupPreviewFrame(
            compositeImage: legacyProduct ?? contentImage,
            layers: nil
        )
    }
}

private final class MockupPreviewFrame: @unchecked Sendable {
    let compositeImage: NSImage?
    let layers: PhotoMockupPreviewLayers?

    init(compositeImage: NSImage?, layers: PhotoMockupPreviewLayers?) {
        self.compositeImage = compositeImage
        self.layers = layers
    }
}

private final class PhotoMockupPreviewLayers: @unchecked Sendable {
    let bezelImage: NSImage
    let screenImage: NSImage
    let maskImage: NSImage
    let canvasSize: CGSize
    let screenCenter: CGPoint
    let screenSize: CGSize

    init(
        bezelImage: NSImage,
        screenImage: NSImage,
        maskImage: NSImage,
        canvasSize: CGSize,
        screenCenter: CGPoint,
        screenSize: CGSize
    ) {
        self.bezelImage = bezelImage
        self.screenImage = screenImage
        self.maskImage = maskImage
        self.canvasSize = canvasSize
        self.screenCenter = screenCenter
        self.screenSize = screenSize
    }
}

private struct MockupAlignmentGrid: View {
    let centeredX: Bool
    let centeredY: Bool

    var body: some View {
        Canvas { context, size in
            let thirds = Color.white.opacity(0.18)
            let center = Color.accentColor.opacity(0.42)
            let centerStrong = Color.accentColor.opacity(0.78)

            for index in 1...2 {
                let x = size.width * CGFloat(index) / 3
                var vertical = Path()
                vertical.move(to: CGPoint(x: x, y: 0))
                vertical.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(vertical, with: .color(thirds), lineWidth: 0.8)

                let y = size.height * CGFloat(index) / 3
                var horizontal = Path()
                horizontal.move(to: CGPoint(x: 0, y: y))
                horizontal.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(horizontal, with: .color(thirds), lineWidth: 0.8)
            }

            var centerV = Path()
            centerV.move(to: CGPoint(x: size.width / 2, y: 0))
            centerV.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            context.stroke(
                centerV,
                with: .color(centeredX ? centerStrong : center),
                style: StrokeStyle(lineWidth: centeredX ? 1.2 : 0.8, dash: [5, 5])
            )

            var centerH = Path()
            centerH.move(to: CGPoint(x: 0, y: size.height / 2))
            centerH.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                centerH,
                with: .color(centeredY ? centerStrong : center),
                style: StrokeStyle(lineWidth: centeredY ? 1.2 : 0.8, dash: [5, 5])
            )

            let safeRect = CGRect(
                x: size.width * 0.07,
                y: size.height * 0.07,
                width: size.width * 0.86,
                height: size.height * 0.86
            )
            context.stroke(
                Path(roundedRect: safeRect, cornerRadius: 12),
                with: .color(Color.white.opacity(0.10)),
                style: StrokeStyle(lineWidth: 0.7, dash: [3, 5])
            )

            let dotRect = CGRect(
                x: size.width / 2 - 2.5,
                y: size.height / 2 - 2.5,
                width: 5,
                height: 5
            )
            context.fill(
                Path(ellipseIn: dotRect),
                with: .color((centeredX && centeredY) ? centerStrong : center)
            )
        }
    }
}


private struct SmoothValueSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    private var fraction: CGFloat {
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let thumbDiameter: CGFloat = isDragging ? 15 : 13
            let usableWidth = max(proxy.size.width - thumbDiameter, 1)
            let thumbX = thumbDiameter / 2 + usableWidth * fraction

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.11))
                    .frame(height: 5)

                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(isDragging ? 0.95 : 0.82))
                    .frame(width: max(5, thumbX), height: 5)

                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                    }
                    .shadow(color: Color.black.opacity(isDragging ? 0.28 : 0.20), radius: isDragging ? 3.5 : 2.5, y: 1)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .position(x: thumbX, y: proxy.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            onEditingChanged(true)
                        }
                        isDragging = true
                        let clampedX = min(max(gesture.location.x - thumbDiameter / 2, 0), usableWidth)
                        let rawFraction = clampedX / usableWidth
                        let rawValue = range.lowerBound + rawFraction * (range.upperBound - range.lowerBound)
                        let stepped: CGFloat
                        if step > 0 {
                            let steps = ((rawValue - range.lowerBound) / step).rounded()
                            stepped = range.lowerBound + steps * step
                        } else {
                            stepped = rawValue
                        }
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.12)) {
                            isDragging = false
                        }
                        onEditingChanged(false)
                    }
            )
        }
        .frame(minHeight: 18)
        .animation(.easeInOut(duration: 0.16), value: isDragging)
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

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .oval: return "Oval"
        case .marker: return "Marker"
        case .text: return "Text"
        case .mosaic: return "Mosaic"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "square"
        case .oval: return "oval"
        case .marker: return "highlighter"
        case .text: return "textformat"
        case .mosaic: return "square.grid.3x3.fill"
        }
    }

    var usesColor: Bool {
        self != .mosaic
    }

    var usesStrokeWidth: Bool {
        switch self {
        case .arrow, .line, .rectangle, .oval, .marker:
            return true
        case .text, .mosaic:
            return false
        }
    }
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
    @Published var image: NSImage
    @Published var annotations: [ImageAnnotation] = []
    @Published var cropRect: NSRect
    @Published var backgroundSettings = AnnotationBackgroundSettings()
    @Published var mockupTransform = MockupTransformSettings()
    @Published var mockupScreenFraming = MockupScreenFramingSettings()
    @Published var showsMockupGrid = false
    @Published var selectedPhotoMockup: PhotoMockupAsset?
    @Published var selectedDeviceBezel: ImportedDeviceBezel?
    @Published var isTextRecognitionEnabled = false
    @Published var isRecognizingText = false
    @Published var recognizedTextRegions: [RecognizedTextRegion] = []
    private var textRecognitionGeneration = UUID()
    private var mockupGridHideTask: Task<Void, Never>?

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

    func rotate(clockwise: Bool) {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }

        let transform = NSAffineTransform()
        if clockwise {
            transform.translateX(by: sourceSize.height, yBy: 0)
            transform.rotate(byDegrees: 90)
        } else {
            transform.translateX(by: 0, yBy: sourceSize.width)
            transform.rotate(byDegrees: -90)
        }

        applyGeometryTransform(
            newImage: ImageEditingService.rotate(image, clockwise: clockwise),
            transform: transform
        )
    }

    func flipHorizontal() {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }

        let transform = NSAffineTransform()
        transform.translateX(by: sourceSize.width, yBy: 0)
        transform.scaleX(by: -1, yBy: 1)
        applyGeometryTransform(
            newImage: ImageEditingService.flipHorizontal(image),
            transform: transform
        )
    }

    private func applyGeometryTransform(newImage: NSImage, transform: NSAffineTransform) {
        let newBounds = NSRect(origin: .zero, size: newImage.size)
        let newCrop = Self.transformedRect(cropRect, using: transform).intersection(newBounds)
        let newAnnotations = annotations.map { $0.transformed(using: transform) }

        image = newImage
        cropRect = newCrop.isEmpty ? newBounds : newCrop
        annotations = newAnnotations

        textRecognitionGeneration = UUID()
        isRecognizingText = false
        recognizedTextRegions.removeAll()
        if isTextRecognitionEnabled {
            recognizeText(generation: textRecognitionGeneration)
        }
    }

    private static func transformedRect(_ rect: NSRect, using transform: NSAffineTransform) -> NSRect {
        let points = [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY)
        ].map(transform.transform)
        guard let first = points.first else { return .zero }
        let minX = points.dropFirst().reduce(first.x) { min($0, $1.x) }
        let maxX = points.dropFirst().reduce(first.x) { max($0, $1.x) }
        let minY = points.dropFirst().reduce(first.y) { min($0, $1.y) }
        let maxY = points.dropFirst().reduce(first.y) { max($0, $1.y) }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func renderedImage() -> NSImage {
        let contentImage = renderedContentImage()
        let photoProduct = selectedPhotoMockup?.renderedImage(
            wrapping: contentImage,
            screenFraming: mockupScreenFraming
        )
        let rawProductImage = photoProduct ?? selectedDeviceBezel?.renderedImage(wrapping: contentImage) ?? contentImage
        let productImage = hasSelectedMockup ? mockupTransform.renderedImage(wrapping: rawProductImage) : rawProductImage
        return backgroundSettings.renderedImage(
            wrapping: productImage,
            preserveTransparentEdges: selectedPhotoMockup != nil || selectedDeviceBezel != nil
        )
    }

    private static func resizedForPreview(_ image: NSImage, maxPixelSize: Int) -> NSImage {
        let sourceSize = image.size
        let longSide = max(sourceSize.width, sourceSize.height)
        let limit = CGFloat(max(maxPixelSize, 1))
        guard longSide > limit, sourceSize.width > 0, sourceSize.height > 0 else {
            return image
        }

        let scale = limit / longSide
        let outputSize = NSSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )
        let output = NSImage(size: outputSize)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: outputSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        return output
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

    var hasSelectedMockup: Bool {
        selectedPhotoMockup != nil || selectedDeviceBezel != nil
    }

    func resetMockupTransform() {
        mockupTransform = MockupTransformSettings()
    }

    func setMockupInteraction(_ isActive: Bool) {
        mockupGridHideTask?.cancel()

        if isActive {
            showsMockupGrid = true
            return
        }

        mockupGridHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.20)) {
                self?.showsMockupGrid = false
            }
        }
    }

    func flashMockupGrid() {
        setMockupInteraction(true)
        setMockupInteraction(false)
    }

    func makeCaptureExportWorkItem() -> CaptureExportWorkItem {
        CaptureExportWorkItem(
            contentImage: renderedContentImage(),
            photoMockup: selectedPhotoMockup,
            legacyBezel: selectedDeviceBezel,
            screenFraming: mockupScreenFraming,
            transform: mockupTransform,
            background: backgroundSettings
        )
    }

    func makeMockupPreviewWorkItem(maxPixelSize: Int) -> MockupPreviewWorkItem {
        let contentImage = Self.resizedForPreview(renderedContentImage(), maxPixelSize: maxPixelSize)
        return MockupPreviewWorkItem(
            contentImage: contentImage,
            photoMockup: selectedPhotoMockup,
            legacyBezel: selectedDeviceBezel,
            screenFraming: mockupScreenFraming,
            maxPixelSize: maxPixelSize
        )
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

private struct MockupScreenFramingSettings: Equatable, Sendable {
    var zoom: CGFloat = 1.0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    var isIdentity: Bool {
        abs(zoom - 1) < 0.0001 &&
        abs(offsetX) < 0.0001 &&
        abs(offsetY) < 0.0001
    }
}

private struct MockupTransformSettings: Equatable {
    var zoom: CGFloat = 1.0
    var tiltDegrees: CGFloat = 0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    var isIdentity: Bool {
        abs(zoom - 1) < 0.0001 &&
        abs(tiltDegrees) < 0.0001 &&
        abs(offsetX) < 0.0001 &&
        abs(offsetY) < 0.0001
    }

    func renderedImage(wrapping image: NSImage) -> NSImage {
        guard !isIdentity else { return image }

        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }

        let clampedZoom = min(max(zoom, 0.45), 1.8)
        let radians = tiltDegrees * .pi / 180
        let cosA = abs(cos(radians))
        let sinA = abs(sin(radians))
        let scaledWidth = sourceSize.width * clampedZoom
        let scaledHeight = sourceSize.height * clampedZoom
        let rotatedWidth = scaledWidth * cosA + scaledHeight * sinA
        let rotatedHeight = scaledWidth * sinA + scaledHeight * cosA

        let shiftX = offsetX * sourceSize.width
        let shiftY = offsetY * sourceSize.height
        let outputSize = NSSize(
            width: max(sourceSize.width, rotatedWidth + abs(shiftX) * 2),
            height: max(sourceSize.height, rotatedHeight + abs(shiftY) * 2)
        )
        let output = NSImage(size: outputSize)
        output.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            output.unlockFocus()
            return image
        }

        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(
            x: outputSize.width / 2 + shiftX,
            y: outputSize.height / 2 + shiftY
        )
        context.rotate(by: radians)
        context.scaleBy(x: clampedZoom, y: clampedZoom)

        let drawRect = NSRect(
            x: -sourceSize.width / 2,
            y: -sourceSize.height / 2,
            width: sourceSize.width,
            height: sourceSize.height
        )
        image.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1
        )
        context.restoreGState()
        output.unlockFocus()
        return output
    }
}

private struct AnnotationBackgroundSettings: Equatable {
    var style: AnnotationBackgroundStyle = .none
    var padding: CGFloat = 28
    var cornerRadius: CGFloat = 18
    var autoBalance = false

    func renderedImage(wrapping image: NSImage, preserveTransparentEdges: Bool = false) -> NSImage {
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

        if preserveTransparentEdges {
            image.draw(
                in: imageRect,
                from: NSRect(origin: .zero, size: imageSize),
                operation: .sourceOver,
                fraction: 1
            )
        } else {
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
        }

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

private struct NormalizedPhotoQuad: Codable, Equatable, Hashable, Sendable {
    let topLeftX: CGFloat, topLeftY: CGFloat
    let topRightX: CGFloat, topRightY: CGFloat
    let bottomRightX: CGFloat, bottomRightY: CGFloat
    let bottomLeftX: CGFloat, bottomLeftY: CGFloat

    func points(width: CGFloat, height: CGFloat) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        (CGPoint(x: topLeftX * width, y: topLeftY * height), CGPoint(x: topRightX * width, y: topRightY * height), CGPoint(x: bottomRightX * width, y: bottomRightY * height), CGPoint(x: bottomLeftX * width, y: bottomLeftY * height))
    }
}

private enum PhotoMockupFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case macBook
    case iPhone
    case iPad
    case appleWatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macBook: return "MacBook"
        case .iPhone: return "iPhone"
        case .iPad: return "iPad"
        case .appleWatch: return "Apple Watch"
        }
    }

    var systemImage: String {
        switch self {
        case .macBook: return "laptopcomputer"
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .appleWatch: return "applewatch"
        }
    }
}

private enum PhotoMockupOrientation: String, Codable, Sendable {
    case portrait
    case landscape
    case front

    var title: String {
        switch self {
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        case .front: return "Front"
        }
    }
}

private struct PhotoMockupPreset: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let family: PhotoMockupFamily
    let model: String
    let color: String
    let orientation: PhotoMockupOrientation
    let bezelPath: String
    let maskPath: String
    let quad: NormalizedPhotoQuad

    var compactTitle: String { model }
    var subtitle: String {
        let details = [color, orientation == .front ? nil : orientation.title].compactMap { $0 }
        return details.isEmpty ? model : "\(model) · \(details.joined(separator: " · "))"
    }
    var variantTitle: String {
        let showsOrientation = family == .iPhone || family == .iPad
        let orientationTitle = showsOrientation && orientation != .front ? orientation.title : nil
        return [color, orientationTitle].compactMap { $0 }.joined(separator: " · ")
    }
    var systemImage: String { family.systemImage }
    var sourcePageURL: URL? { URL(string: "https://developer.apple.com/design/resources/") }
}

private enum PhotoMockupCatalog {
    static func load() -> [PhotoMockupPreset] {
        guard let root = Bundle.main.resourceURL else { return [] }
        let url = root
            .appending(path: "DeviceBezels", directoryHint: .isDirectory)
            .appending(path: "catalog.json")
        guard let data = try? Data(contentsOf: url),
              let presets = try? JSONDecoder().decode([PhotoMockupPreset].self, from: data) else {
            return []
        }
        return presets
    }
}

private enum PhotoMockupOverlayStyle: String, Codable, Sendable { case none, dynamicIsland }

private struct PhotoMockupAsset: Identifiable, Codable, Equatable, Sendable {
    private static let renderContext = CIContext(options: [.cacheIntermediates: false])

    let id: UUID
    let presetID: String
    let name: String
    let fileURL: URL
    let screenMaskURL: URL
    let quad: NormalizedPhotoQuad
    let visibleBounds: CGRect?
    let screenCornerRadius: CGFloat
    let overlayStyle: PhotoMockupOverlayStyle
    let sourcePageURL: URL?
    let credit: String

    func renderedImage(
        wrapping screenshot: NSImage,
        maxPixelSize: Int? = nil,
        screenFraming: MockupScreenFramingSettings = MockupScreenFramingSettings()
    ) -> NSImage? {
        let photoCI: CIImage
        let maskCI: CIImage
        if let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let maskSource = CGImageSourceCreateWithURL(screenMaskURL as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let maskThumbnail = CGImageSourceCreateThumbnailAtIndex(maskSource, 0, options as CFDictionary) else { return nil }
            photoCI = CIImage(cgImage: thumbnail)
            maskCI = CIImage(cgImage: maskThumbnail)
        } else {
            guard let original = CIImage(contentsOf: fileURL, options: [.applyOrientationProperty: true]),
                  let mask = CIImage(contentsOf: screenMaskURL, options: [.applyOrientationProperty: true]) else { return nil }
            photoCI = original
            maskCI = mask
        }

        guard let screenshotCG = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let extent = photoCI.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        let p = quad.points(width: extent.width, height: extent.height)
        let tl=p.0, tr=p.1, br=p.2, bl=p.3
        let targetWidth=max(hypot(tr.x-tl.x,tr.y-tl.y),hypot(br.x-bl.x,br.y-bl.y))
        let targetHeight=max(hypot(tl.x-bl.x,tl.y-bl.y),hypot(tr.x-br.x,tr.y-br.y))
        guard targetWidth > 4, targetHeight > 4 else { return nil }
        let screenshotCI=CIImage(cgImage:screenshotCG)
        let fittedBase=Self.aspectFillCanvas(source:screenshotCI,targetAspect:targetWidth/targetHeight)
        let fitted=Self.applyScreenFraming(fittedBase, settings: screenFraming)

        // Bleed the screenshot slightly underneath the physical bezel. Apple's PNG
        // aperture edges are anti-aliased, so mapping exactly to the transparent-pixel
        // boundary can leave a thin visible seam even when the aspect ratio is correct.
        let center = CGPoint(
            x: (tl.x + tr.x + br.x + bl.x) / 4,
            y: (tl.y + tr.y + br.y + bl.y) / 4
        )
        let overscanScale: CGFloat = 1.012
        func overscanned(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: center.x + (point.x - center.x) * overscanScale,
                y: center.y + (point.y - center.y) * overscanScale
            )
        }
        let renderTL = overscanned(tl)
        let renderTR = overscanned(tr)
        let renderBR = overscanned(br)
        let renderBL = overscanned(bl)

        guard let perspective=CIFilter(name:"CIPerspectiveTransform") else { return nil }
        perspective.setValue(fitted,forKey:kCIInputImageKey)
        perspective.setValue(CIVector(cgPoint:renderTL),forKey:"inputTopLeft")
        perspective.setValue(CIVector(cgPoint:renderTR),forKey:"inputTopRight")
        perspective.setValue(CIVector(cgPoint:renderBR),forKey:"inputBottomRight")
        perspective.setValue(CIVector(cgPoint:renderBL),forKey:"inputBottomLeft")
        guard let warped = perspective.outputImage else { return nil }
        // Keep the screenshot underneath the bezel, but clip it with a mask extracted
        // from the bezel's enclosed transparent display aperture. This preserves the
        // exact rounded display corners while preventing the screenshot from leaking
        // into the transparent canvas outside the physical device.
        let screenLayer = warped.cropped(to: extent)
        let normalizedMask = maskCI
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / max(maskCI.extent.width, 1),
                y: extent.height / max(maskCI.extent.height, 1)
            ))
            .cropped(to: extent)
        let transparent = CIImage(color: .clear).cropped(to: extent)
        let clippedScreen = screenLayer.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: transparent,
                kCIInputMaskImageKey: normalizedMask
            ]
        )
        let composite = photoCI.composited(over: clippedScreen).cropped(to: extent)
        let renderExtent: CGRect
        if let visibleBounds {
            renderExtent = CGRect(
                x: extent.minX + visibleBounds.minX * extent.width,
                y: extent.minY + visibleBounds.minY * extent.height,
                width: visibleBounds.width * extent.width,
                height: visibleBounds.height * extent.height
            ).intersection(extent).integral
        } else {
            renderExtent = extent
        }
        guard renderExtent.width > 1, renderExtent.height > 1,
              let cgOutput=Self.renderContext.createCGImage(composite,from:renderExtent) else { return nil }
        let output=NSImage(cgImage:cgOutput,size:NSSize(width:renderExtent.width,height:renderExtent.height))
        if overlayStyle != .none {
            output.lockFocus()
            NSColor.black.setFill()
            switch overlayStyle {
            case .dynamicIsland:
                let islandRect = NSRect(
                    x: extent.width * 0.405 - renderExtent.minX,
                    y: extent.height * 0.928 - renderExtent.minY,
                    width: extent.width * 0.190,
                    height: extent.height * 0.024
                )
                NSBezierPath(
                    roundedRect: islandRect,
                    xRadius: islandRect.height / 2,
                    yRadius: islandRect.height / 2
                ).fill()
            case .none:
                break
            }
            output.unlockFocus()
        }
        return output
    }

    func previewLayers(
        wrapping screenshot: NSImage,
        maxPixelSize: Int
    ) -> PhotoMockupPreviewLayers? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let maskSource = CGImageSourceCreateWithURL(screenMaskURL as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let maskThumbnail = CGImageSourceCreateThumbnailAtIndex(maskSource, 0, options as CFDictionary),
              let screenshotCG = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let photoCI = CIImage(cgImage: thumbnail)
        let maskCI = CIImage(cgImage: maskThumbnail)
        let extent = photoCI.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }

        let p = quad.points(width: extent.width, height: extent.height)
        let tl = p.0, tr = p.1, br = p.2, bl = p.3
        let targetWidth = max(hypot(tr.x - tl.x, tr.y - tl.y), hypot(br.x - bl.x, br.y - bl.y))
        let targetHeight = max(hypot(tl.x - bl.x, tl.y - bl.y), hypot(tr.x - br.x, tr.y - br.y))
        guard targetWidth > 4, targetHeight > 4 else { return nil }

        let screenshotCI = CIImage(cgImage: screenshotCG)
        let fitted = Self.aspectFillCanvas(source: screenshotCI, targetAspect: targetWidth / targetHeight)
        let center = CGPoint(
            x: (tl.x + tr.x + br.x + bl.x) / 4,
            y: (tl.y + tr.y + br.y + bl.y) / 4
        )
        let overscanScale: CGFloat = 1.012
        func overscanned(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: center.x + (point.x - center.x) * overscanScale,
                y: center.y + (point.y - center.y) * overscanScale
            )
        }

        guard let perspective = CIFilter(name: "CIPerspectiveTransform") else { return nil }
        perspective.setValue(fitted, forKey: kCIInputImageKey)
        perspective.setValue(CIVector(cgPoint: overscanned(tl)), forKey: "inputTopLeft")
        perspective.setValue(CIVector(cgPoint: overscanned(tr)), forKey: "inputTopRight")
        perspective.setValue(CIVector(cgPoint: overscanned(br)), forKey: "inputBottomRight")
        perspective.setValue(CIVector(cgPoint: overscanned(bl)), forKey: "inputBottomLeft")
        guard let warped = perspective.outputImage else { return nil }

        let screenLayer = warped.cropped(to: extent)
        let normalizedMask = maskCI
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / max(maskCI.extent.width, 1),
                y: extent.height / max(maskCI.extent.height, 1)
            ))
            .cropped(to: extent)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        let transparent = CIImage(color: .clear).cropped(to: extent)
        let alphaMask = white.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: transparent,
                kCIInputMaskImageKey: normalizedMask
            ]
        )

        let renderExtent: CGRect
        if let visibleBounds {
            renderExtent = CGRect(
                x: extent.minX + visibleBounds.minX * extent.width,
                y: extent.minY + visibleBounds.minY * extent.height,
                width: visibleBounds.width * extent.width,
                height: visibleBounds.height * extent.height
            ).intersection(extent).integral
        } else {
            renderExtent = extent
        }
        guard renderExtent.width > 1, renderExtent.height > 1 else { return nil }

        func renderImage(_ image: CIImage) -> NSImage? {
            guard let cg = Self.renderContext.createCGImage(image, from: renderExtent) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: renderExtent.width, height: renderExtent.height))
        }

        guard let screenImage = renderImage(screenLayer),
              let maskImage = renderImage(alphaMask),
              let bezelImage = renderImage(photoCI) else {
            return nil
        }

        if overlayStyle != .none {
            bezelImage.lockFocus()
            NSColor.black.setFill()
            if overlayStyle == .dynamicIsland {
                let islandRect = NSRect(
                    x: extent.width * 0.405 - renderExtent.minX,
                    y: extent.height * 0.928 - renderExtent.minY,
                    width: extent.width * 0.190,
                    height: extent.height * 0.024
                )
                NSBezierPath(
                    roundedRect: islandRect,
                    xRadius: islandRect.height / 2,
                    yRadius: islandRect.height / 2
                ).fill()
            }
            bezelImage.unlockFocus()
        }

        let centerX = min(max((center.x - renderExtent.minX) / renderExtent.width, 0), 1)
        let centerYCI = min(max((center.y - renderExtent.minY) / renderExtent.height, 0), 1)
        return PhotoMockupPreviewLayers(
            bezelImage: bezelImage,
            screenImage: screenImage,
            maskImage: maskImage,
            canvasSize: renderExtent.size,
            screenCenter: CGPoint(x: centerX, y: 1 - centerYCI),
            screenSize: CGSize(width: targetWidth, height: targetHeight)
        )
    }

    func thumbnailImage(maxPixelSize:Int)->NSImage? {
        guard let source=CGImageSourceCreateWithURL(fileURL as CFURL,nil) else { return nil }
        let options:[CFString:Any]=[kCGImageSourceShouldCache:false,kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:maxPixelSize,kCGImageSourceCreateThumbnailWithTransform:true]
        guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else { return nil }
        return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
    }

    private static func applyScreenFraming(
        _ source: CIImage,
        settings: MockupScreenFramingSettings
    ) -> CIImage {
        let extent = source.extent.integral
        guard extent.width > 0, extent.height > 0 else { return source }

        let zoom = min(max(settings.zoom, 1), 2.5)
        guard zoom > 1.0001 || abs(settings.offsetX) > 0.0001 || abs(settings.offsetY) > 0.0001 else {
            return source
        }

        let normalized = source.transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: zoom, y: zoom))
        let overflowX = max(scaled.extent.width - extent.width, 0)
        let overflowY = max(scaled.extent.height - extent.height, 0)
        let focusX = min(max((settings.offsetX + 1) / 2, 0), 1)
        let focusY = min(max((settings.offsetY + 1) / 2, 0), 1)
        let cropOriginX = overflowX * focusX
        let cropOriginY = overflowY * focusY

        return scaled
            .transformed(by: CGAffineTransform(
                translationX: -cropOriginX,
                y: -cropOriginY
            ))
            .cropped(to: CGRect(origin: .zero, size: extent.size))
    }

    private static func aspectFillCanvas(source: CIImage, targetAspect: CGFloat) -> CIImage {
        let sourceExtent = source.extent.integral
        guard sourceExtent.width > 0, sourceExtent.height > 0, targetAspect > 0 else { return source }
        let normalized = source.transformed(by: CGAffineTransform(
            translationX: -sourceExtent.minX,
            y: -sourceExtent.minY
        ))
        let sourceAspect = sourceExtent.width / sourceExtent.height
        let targetSize: CGSize
        if sourceAspect > targetAspect {
            targetSize = CGSize(width: sourceExtent.height * targetAspect, height: sourceExtent.height)
        } else {
            targetSize = CGSize(width: sourceExtent.width, height: sourceExtent.width / targetAspect)
        }
        let targetRect = CGRect(origin: .zero, size: targetSize)
        let scale = max(targetSize.width / sourceExtent.width, targetSize.height / sourceExtent.height)
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        return scaled.transformed(by: CGAffineTransform(
            translationX: (targetSize.width - scaledExtent.width) / 2 - scaledExtent.minX,
            y: (targetSize.height - scaledExtent.height) / 2 - scaledExtent.minY
        )).cropped(to: targetRect)
    }
}

@MainActor
private final class PhotoMockupLibrary: ObservableObject {
    static let shared = PhotoMockupLibrary()

    @Published private(set) var assets: [PhotoMockupAsset]
    @Published private(set) var presets: [PhotoMockupPreset]

    private init() {
        assets = []
        presets = PhotoMockupCatalog.load()
    }

    func models(in family: PhotoMockupFamily) -> [String] {
        Array(Set(presets.filter { $0.family == family }.map(\.model))).sorted()
    }

    func variants(family: PhotoMockupFamily, model: String) -> [PhotoMockupPreset] {
        presets
            .filter { $0.family == family && $0.model == model }
            .sorted { lhs, rhs in
                if lhs.orientation.rawValue != rhs.orientation.rawValue {
                    return lhs.orientation.rawValue < rhs.orientation.rawValue
                }
                return lhs.color.localizedCaseInsensitiveCompare(rhs.color) == .orderedAscending
            }
    }

    func preset(id: String) -> PhotoMockupPreset? {
        presets.first { $0.id == id }
    }

    func asset(for preset: PhotoMockupPreset) -> PhotoMockupAsset? {
        assets.first { $0.presetID == preset.id }
    }

    func resolve(_ preset: PhotoMockupPreset) -> PhotoMockupAsset? {
        if let existing = asset(for: preset) { return existing }
        guard let asset = Self.makeOfficialAsset(preset) else { return nil }
        assets.append(asset)
        return asset
    }

    func preloadAll() async { }

    nonisolated private static func makeOfficialAsset(_ preset: PhotoMockupPreset) -> PhotoMockupAsset? {
        let resourceRoot = Bundle.main.resourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let deviceRoot = resourceRoot.appendingPathComponent("DeviceBezels", isDirectory: true)
        let sourceURL = deviceRoot.appendingPathComponent(preset.bezelPath)
        let maskURL = deviceRoot.appendingPathComponent(preset.maskPath)

        // catalog.json is loaded from the same DeviceBezels directory. Selection is
        // deliberately non-installing and non-throwing: use the bundled Apple assets
        // in place instead of copying/re-validating them on every click.
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              FileManager.default.fileExists(atPath: maskURL.path) else {
            return nil
        }

        return PhotoMockupAsset(
            id: UUID(),
            presetID: preset.id,
            name: preset.subtitle,
            fileURL: sourceURL,
            screenMaskURL: maskURL,
            quad: preset.quad,
            visibleBounds: nil,
            screenCornerRadius: 0,
            overlayStyle: .none,
            sourcePageURL: preset.sourcePageURL,
            credit: "Apple Product Bezels"
        )
    }
}

private enum ProductRenderIsolation {
    struct Prepared: Sendable {
        let quad: NormalizedPhotoQuad
        let visibleBounds: CGRect
    }

    enum IsolationError: LocalizedError {
        case unreadableImage
        case couldNotEncode

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "Could not load the device product render."
            case .couldNotEncode: return "Could not prepare the transparent device mockup."
            }
        }
    }

    static func prepare(
        sourceURL: URL,
        destinationURL: URL,
        sourceCrop: CGRect,
        screenQuad: NormalizedPhotoQuad,
        backgroundTolerance: Int,
        screenCornerRadius: CGFloat = 0,
        hardwareNotchSourceURL: URL? = nil
    ) throws -> Prepared {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let sourceImage = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) else {
            throw IsolationError.unreadableImage
        }

        let sourceWidth = sourceImage.width
        let sourceHeight = sourceImage.height
        let normalizedCrop = sourceCrop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard normalizedCrop.width > 0, normalizedCrop.height > 0 else {
            throw IsolationError.unreadableImage
        }

        let pixelCrop = CGRect(
            x: normalizedCrop.minX * CGFloat(sourceWidth),
            y: (1 - normalizedCrop.maxY) * CGFloat(sourceHeight),
            width: normalizedCrop.width * CGFloat(sourceWidth),
            height: normalizedCrop.height * CGFloat(sourceHeight)
        ).integral

        guard let croppedImage = sourceImage.cropping(to: pixelCrop),
              croppedImage.width > 1,
              croppedImage.height > 1 else {
            throw IsolationError.unreadableImage
        }

        let width = croppedImage.width
        let height = croppedImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let rendered = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw IsolationError.unreadableImage }

        func remap(_ x: CGFloat, _ y: CGFloat) -> (CGFloat, CGFloat) {
            (
                (x - normalizedCrop.minX) / normalizedCrop.width,
                (y - normalizedCrop.minY) / normalizedCrop.height
            )
        }

        let tl = remap(screenQuad.topLeftX, screenQuad.topLeftY)
        let tr = remap(screenQuad.topRightX, screenQuad.topRightY)
        let br = remap(screenQuad.bottomRightX, screenQuad.bottomRightY)
        let bl = remap(screenQuad.bottomLeftX, screenQuad.bottomLeftY)
        let preparedQuad = NormalizedPhotoQuad(
            topLeftX: tl.0, topLeftY: tl.1,
            topRightX: tr.0, topRightY: tr.1,
            bottomRightX: br.0, bottomRightY: br.1,
            bottomLeftX: bl.0, bottomLeftY: bl.1
        )

        func rgb(at index: Int) -> (Int, Int, Int) {
            let offset = index * 4
            return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
        }

        let cornerIndices = [0, width - 1, (height - 1) * width, height * width - 1]
        let cornerAlphas = cornerIndices.map { Int(pixels[$0 * 4 + 3]) }
        let sourceAlreadyTransparent = cornerAlphas.allSatisfy { $0 <= 12 }
        let cornerColors = cornerIndices.map(rgb)
        let background = (
            cornerColors.map(\.0).reduce(0, +) / cornerColors.count,
            cornerColors.map(\.1).reduce(0, +) / cornerColors.count,
            cornerColors.map(\.2).reduce(0, +) / cornerColors.count
        )

        func isBackground(_ pixelIndex: Int) -> Bool {
            let (r, g, b) = rgb(at: pixelIndex)
            return abs(r - background.0) <= backgroundTolerance
                && abs(g - background.1) <= backgroundTolerance
                && abs(b - background.2) <= backgroundTolerance
        }

        if !sourceAlreadyTransparent {
            var visited = [UInt8](repeating: 0, count: width * height)
            var queue = [Int]()
            queue.reserveCapacity(width * 2 + height * 2)

            func enqueue(_ x: Int, _ y: Int) {
                guard x >= 0, x < width, y >= 0, y < height else { return }
                let index = y * width + x
                guard visited[index] == 0, isBackground(index) else { return }
                visited[index] = 1
                queue.append(index)
            }

            for x in 0..<width {
                enqueue(x, 0)
                enqueue(x, height - 1)
            }
            for y in 0..<height {
                enqueue(0, y)
                enqueue(width - 1, y)
            }

            var head = 0
            while head < queue.count {
                let index = queue[head]
                head += 1
                pixels[index * 4 + 3] = 0
                let x = index % width
                let y = index / width
                enqueue(x - 1, y)
                enqueue(x + 1, y)
                enqueue(x, y - 1)
                enqueue(x, y + 1)
            }
        }

        // Official Apple bezel PNGs already have a transparent display aperture and
        // include the real notch / camera hardware. Preserve those pixels exactly.
        // Only synthesize an aperture for legacy opaque source renders.
        if !sourceAlreadyTransparent {
            pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return }

            let p = preparedQuad.points(width: CGFloat(width), height: CGFloat(height))
            let screenRect = CGRect(
                x: min(p.0.x, p.3.x),
                y: min(p.2.y, p.3.y),
                width: max(p.1.x, p.2.x) - min(p.0.x, p.3.x),
                height: max(p.0.y, p.1.y) - min(p.2.y, p.3.y)
            )
            let radius = min(
                min(screenRect.width, screenRect.height) / 2,
                screenCornerRadius * CGFloat(min(width, height))
            )
            let path = CGPath(
                roundedRect: screenRect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
                        // The screen aperture comes directly from the official Apple PSD bounds.
            context.saveGState()
            context.setShouldAntialias(true)
            context.setBlendMode(.clear)
                        context.addPath(path)
            context.fillPath()
            context.restoreGState()

            // Real camera housing pixels extracted from an official Apple product reference.
            // No rounded-rectangle or custom-drawn notch is used here.
            if let hardwareNotchSourceURL,
               let notchSource = CGImageSourceCreateWithURL(hardwareNotchSourceURL as CFURL, nil),
               let notchImage = CGImageSourceCreateImageAtIndex(notchSource, 0, nil) {
                let notchWidth = screenRect.width * 0.157
                let notchHeight = notchWidth * CGFloat(notchImage.height) / CGFloat(notchImage.width)
                // The reference housing overlaps the top bezel slightly and only
                // descends into the active display, so it remains visually connected
                // to the hardware instead of becoming an isolated pill in the image.
                let notchRect = CGRect(
                    x: screenRect.midX - notchWidth / 2,
                    y: screenRect.maxY - notchHeight * 0.977,
                    width: notchWidth,
                    height: notchHeight
                )
                context.saveGState()
                context.interpolationQuality = .high
                context.setBlendMode(.normal)
                context.draw(notchImage, in: notchRect)
                context.restoreGState()
            }
            }
        }
        // Trim large empty transparent margins when presenting/rendering. Keep a
        // very small breathing room so shadows and hardware edges are not clipped.
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * 4 + 3]
                guard alpha > 8 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        let visibleBounds: CGRect
        if maxX >= minX, maxY >= minY {
            let margin = max(4, Int(CGFloat(max(width, height)) * 0.018))
            let x0 = max(0, minX - margin)
            let y0 = max(0, minY - margin)
            let x1 = min(width - 1, maxX + margin)
            let y1 = min(height - 1, maxY + margin)
            visibleBounds = CGRect(
                x: CGFloat(x0) / CGFloat(width),
                y: CGFloat(height - 1 - y1) / CGFloat(height),
                width: CGFloat(x1 - x0 + 1) / CGFloat(width),
                height: CGFloat(y1 - y0 + 1) / CGFloat(height)
            )
        } else {
            visibleBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        var outputImage: CGImage?
        pixels.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
            outputImage = context?.makeImage()
        }

        guard let outputImage,
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw IsolationError.couldNotEncode
        }
        CGImageDestinationAddImage(destination, outputImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw IsolationError.couldNotEncode
        }

        return Prepared(quad: preparedQuad, visibleBounds: visibleBounds)
    }
}

private enum PhotoMockupScreenDetector {
    enum DetectionError:LocalizedError { case noScreenFound; var errorDescription:String? { "Could not detect the device screen in this mockup photo." } }
    static func detectScreenQuad(in url:URL,expectedAspect:CGFloat) throws -> NormalizedPhotoQuad {
        let request=VNDetectRectanglesRequest(); request.maximumObservations=30; request.minimumConfidence=0.42; request.minimumSize=0.08; request.quadratureTolerance=35
        let handler=VNImageRequestHandler(url:url,options:[:]); try handler.perform([request])
        guard let observations=request.results,!observations.isEmpty else { throw DetectionError.noScreenFound }
        func dist(_ a:CGPoint,_ b:CGPoint)->CGFloat { hypot(a.x-b.x,a.y-b.y) }
        let scored=observations.compactMap { obs -> (VNRectangleObservation,CGFloat)? in
            let width=(dist(obs.topLeft,obs.topRight)+dist(obs.bottomLeft,obs.bottomRight))/2
            let height=(dist(obs.topLeft,obs.bottomLeft)+dist(obs.topRight,obs.bottomRight))/2
            guard width>0.02,height>0.02 else { return nil }
            let aspect=width/height, penalty=abs(log(max(aspect,0.001)/max(expectedAspect,0.001))), area=obs.boundingBox.width*obs.boundingBox.height
            let center=CGPoint(x:obs.boundingBox.midX,y:obs.boundingBox.midY), centerDistance=hypot(center.x-0.5,center.y-0.5)
            return (obs,area*exp(-2.6*penalty)*max(0.45,1-centerDistance*0.65))
        }
        guard let best=scored.max(by:{$0.1<$1.1})?.0 else { throw DetectionError.noScreenFound }
        let center = CGPoint(
            x: (best.topLeft.x + best.topRight.x + best.bottomRight.x + best.bottomLeft.x) / 4,
            y: (best.topLeft.y + best.topRight.y + best.bottomRight.y + best.bottomLeft.y) / 4
        )
        func inset(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x + (center.x - point.x) * 0.035,
                y: point.y + (center.y - point.y) * 0.035
            )
        }
        let tl = inset(best.topLeft), tr = inset(best.topRight), br = inset(best.bottomRight), bl = inset(best.bottomLeft)
        return NormalizedPhotoQuad(topLeftX:tl.x,topLeftY:tl.y,topRightX:tr.x,topRightY:tr.y,bottomRightX:br.x,bottomRightY:br.y,bottomLeftX:bl.x,bottomLeftY:bl.y)
    }
}

private struct ImportedDeviceBezel: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let fileURL: URL
    let screenX: CGFloat
    let screenY: CGFloat
    let screenWidth: CGFloat
    let screenHeight: CGFloat

    var normalizedScreenRect: NSRect {
        NSRect(x: screenX, y: screenY, width: screenWidth, height: screenHeight)
    }

    func renderedImage(wrapping screenshot: NSImage) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let bezelCGImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }

        let width = bezelCGImage.width
        let height = bezelCGImage.height
        guard width > 0, height > 0 else {
            return nil
        }

        let outputSize = NSSize(width: width, height: height)
        let output = NSImage(size: outputSize)
        let screenRect = NSRect(
            x: normalizedScreenRect.minX * outputSize.width,
            y: normalizedScreenRect.minY * outputSize.height,
            width: normalizedScreenRect.width * outputSize.width,
            height: normalizedScreenRect.height * outputSize.height
        )

        output.lockFocus()
        defer { output.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        let screenshotSourceRect = Self.aspectFillSourceRect(
            sourceSize: screenshot.size,
            targetSize: screenRect.size
        )
        screenshot.draw(
            in: screenRect,
            from: screenshotSourceRect,
            operation: .copy,
            fraction: 1
        )

        let bezelImage = NSImage(cgImage: bezelCGImage, size: outputSize)
        bezelImage.draw(
            in: NSRect(origin: .zero, size: outputSize),
            from: NSRect(origin: .zero, size: outputSize),
            operation: .sourceOver,
            fraction: 1
        )

        return output
    }

    func thumbnailImage(maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func aspectFillSourceRect(sourceSize: NSSize, targetSize: NSSize) -> NSRect {
        guard sourceSize.width > 0, sourceSize.height > 0, targetSize.width > 0, targetSize.height > 0 else {
            return NSRect(origin: .zero, size: sourceSize)
        }

        let sourceAspect = sourceSize.width / sourceSize.height
        let targetAspect = targetSize.width / targetSize.height

        if sourceAspect > targetAspect {
            let width = sourceSize.height * targetAspect
            return NSRect(
                x: (sourceSize.width - width) / 2,
                y: 0,
                width: width,
                height: sourceSize.height
            )
        }

        let height = sourceSize.width / targetAspect
        return NSRect(
            x: 0,
            y: (sourceSize.height - height) / 2,
            width: sourceSize.width,
            height: height
        )
    }
}

@MainActor
private final class DeviceBezelLibrary: ObservableObject {
    static let shared = DeviceBezelLibrary()

    @Published private(set) var assets: [ImportedDeviceBezel] = []

    private let directoryURL: URL
    private let metadataURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        directoryURL = support
            .appending(path: "Screenshot Manager", directoryHint: .isDirectory)
            .appending(path: "Device Bezels", directoryHint: .isDirectory)
        metadataURL = directoryURL.appending(path: "bezels.json")
        load()
    }

    func importBezel(from sourceURL: URL) throws -> ImportedDeviceBezel {
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let rect = try DeviceBezelAnalyzer.detectScreenRect(in: sourceURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let id = UUID()
        let destination = directoryURL.appending(path: "\(id.uuidString).png")
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let rawName = sourceURL.deletingPathExtension().lastPathComponent
        let displayName = rawName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let asset = ImportedDeviceBezel(
            id: id,
            name: displayName.isEmpty ? "Device Bezel" : displayName,
            fileURL: destination,
            screenX: rect.minX,
            screenY: rect.minY,
            screenWidth: rect.width,
            screenHeight: rect.height
        )
        assets.append(asset)
        assets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try save()
        return asset
    }

    func remove(_ bezel: ImportedDeviceBezel) {
        assets.removeAll { $0.id == bezel.id }
        try? FileManager.default.removeItem(at: bezel.fileURL)
        try? save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([ImportedDeviceBezel].self, from: data) else {
            assets = []
            return
        }
        assets = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path(percentEncoded: false)) }
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(assets)
        try data.write(to: metadataURL, options: .atomic)
    }
}

private enum DeviceBezelAnalyzer {
    enum AnalyzerError: LocalizedError {
        case unreadableImage
        case noTransparentScreen

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return "Could not read this PNG bezel."
            case .noTransparentScreen:
                return "No enclosed transparent screen cutout was found. Use a transparent bezel PNG where the display area is transparent."
            }
        }
    }

    static func detectScreenRect(in url: URL) throws -> NSRect {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AnalyzerError.unreadableImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AnalyzerError.unreadableImage
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 2, height > 2 else {
            throw AnalyzerError.unreadableImage
        }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else {
            throw AnalyzerError.unreadableImage
        }

        let count = width * height
        var transparent = [Bool](repeating: false, count: count)
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                let alphaIndex = y * bytesPerRow + x * 4 + 3
                transparent[pixelIndex] = pixels[alphaIndex] <= 24
            }
        }

        var outside = [Bool](repeating: false, count: count)
        var queue = [Int]()
        queue.reserveCapacity(count / 4)

        func enqueue(_ x: Int, _ y: Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let idx = y * width + x
            guard transparent[idx], !outside[idx] else { return }
            outside[idx] = true
            queue.append(idx)
        }

        for x in 0..<width {
            enqueue(x, 0)
            enqueue(x, height - 1)
        }
        for y in 0..<height {
            enqueue(0, y)
            enqueue(width - 1, y)
        }

        var head = 0
        while head < queue.count {
            let idx = queue[head]
            head += 1
            let x = idx % width
            let y = idx / width
            enqueue(x - 1, y)
            enqueue(x + 1, y)
            enqueue(x, y - 1)
            enqueue(x, y + 1)
        }

        var visited = outside
        var bestArea = 0
        var bestBounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        var componentQueue = [Int]()
        componentQueue.reserveCapacity(count / 3)

        for startIndex in 0..<count {
            guard transparent[startIndex], !visited[startIndex] else { continue }

            componentQueue.removeAll(keepingCapacity: true)
            componentQueue.append(startIndex)
            visited[startIndex] = true
            var componentHead = 0
            var area = 0
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0

            while componentHead < componentQueue.count {
                let idx = componentQueue[componentHead]
                componentHead += 1
                area += 1
                let x = idx % width
                let y = idx / width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)

                let neighbors = [
                    (x - 1, y),
                    (x + 1, y),
                    (x, y - 1),
                    (x, y + 1)
                ]
                for (nx, ny) in neighbors {
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let next = ny * width + nx
                    guard transparent[next], !visited[next] else { continue }
                    visited[next] = true
                    componentQueue.append(next)
                }
            }

            if area > bestArea {
                bestArea = area
                bestBounds = (minX, minY, maxX, maxY)
            }
        }

        guard let bestBounds,
              bestArea >= Int(Double(count) * 0.025) else {
            throw AnalyzerError.noTransparentScreen
        }

        let rectWidth = bestBounds.maxX - bestBounds.minX + 1
        let rectHeight = bestBounds.maxY - bestBounds.minY + 1
        guard rectWidth > width / 10, rectHeight > height / 10 else {
            throw AnalyzerError.noTransparentScreen
        }

        return NSRect(
            x: CGFloat(bestBounds.minX) / CGFloat(width),
            y: CGFloat(bestBounds.minY) / CGFloat(height),
            width: CGFloat(rectWidth) / CGFloat(width),
            height: CGFloat(rectHeight) / CGFloat(height)
        )
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

    func transformed(using transform: NSAffineTransform) -> ImageAnnotation {
        func point(_ value: NSPoint) -> NSPoint { transform.transform(value) }
        func rect(_ value: NSRect) -> NSRect {
            let points = [
                NSPoint(x: value.minX, y: value.minY),
                NSPoint(x: value.maxX, y: value.minY),
                NSPoint(x: value.maxX, y: value.maxY),
                NSPoint(x: value.minX, y: value.maxY)
            ].map(point)
            guard let first = points.first else { return .zero }
            let minX = points.dropFirst().reduce(first.x) { min($0, $1.x) }
            let maxX = points.dropFirst().reduce(first.x) { max($0, $1.x) }
            let minY = points.dropFirst().reduce(first.y) { min($0, $1.y) }
            let maxY = points.dropFirst().reduce(first.y) { max($0, $1.y) }
            return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        switch self {
        case .arrow(let start, let end, let color, let lineWidth):
            return .arrow(point(start), point(end), color, lineWidth)
        case .line(let start, let end, let color, let lineWidth):
            return .line(point(start), point(end), color, lineWidth)
        case .rectangle(let value, let color, let lineWidth):
            return .rectangle(rect(value), color, lineWidth)
        case .oval(let value, let color, let lineWidth):
            return .oval(rect(value), color, lineWidth)
        case .marker(let points, let color, let lineWidth):
            return .marker(points.map(point), color, lineWidth)
        case .text(let text, let origin, let color, let fontSize):
            return .text(text, point(origin), color, fontSize)
        case .mosaic(let value):
            return .mosaic(rect(value))
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
