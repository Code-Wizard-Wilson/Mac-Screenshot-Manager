import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ScreenshotStore
    let openSettings: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreferenceKeys.didCompleteOnboarding) private var didCompleteOnboarding = false
    @State private var pendingDelete: ScreenshotItem?
    @State private var editingItem: ScreenshotItem?
    @State private var previewItem: ScreenshotItem?
    @State private var showsOnboarding = false

    init(store: ScreenshotStore, openSettings: @escaping () -> Void = {}) {
        self.store = store
        self.openSettings = openSettings
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let isCompact = width < 900
            let showsPreview = width >= 1240 && !store.filteredItems.isEmpty && store.selectedItem != nil

            ZStack(alignment: .top) {
                GlassSurface(material: .underWindowBackground)
                    .ignoresSafeArea()

                if isCompact {
                    CompactLayoutView(
                        store: store,
                        columns: columns(for: width),
                        pendingDelete: $pendingDelete,
                        editingItem: $editingItem,
                        previewItem: $previewItem,
                        showGuide: presentOnboarding,
                        openSettings: openSettings
                    )
                } else {
                    RegularLayoutView(
                        store: store,
                        columns: columns(for: width - sidebarWidth - (showsPreview ? previewWidth(for: width) : 0)),
                        sidebarWidth: sidebarWidth,
                        previewWidth: previewWidth(for: width),
                        showsPreview: showsPreview,
                        pendingDelete: $pendingDelete,
                        editingItem: $editingItem,
                        previewItem: $previewItem,
                        showGuide: presentOnboarding,
                        openSettings: openSettings
                    )
                }

                if let notice = store.captureNotice {
                    CaptureNoticeView(notice: notice)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                        .allowsHitTesting(false)
                }

                if showsOnboarding {
                    OnboardingOverlayView(
                        clipboardHotkey: store.clipboardHotkey.displayString,
                        saveHotkey: store.saveHotkey.displayString,
                        dismiss: completeOnboarding
                    )
                    .transition(.opacity)
                    .zIndex(3)
                }

                if let previewItem {
                    ScreenshotPreviewOverlayView(
                        store: store,
                        item: previewItem,
                        close: closePreviewOverlay
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(4)
                }
            }
            .animation(AppMotion.normal, value: store.captureNotice)
            .animation(AppMotion.normal, value: isCompact)
            .animation(AppMotion.normal, value: showsPreview)
            .animation(AppMotion.normal, value: showsOnboarding)
            .animation(AppMotion.spring, value: previewItem?.id)
            .onExitCommand {
                if previewItem != nil {
                    closePreviewOverlay()
                }
            }
        }
        .tint(AppTheme.accent)
        .modifier(RespectMotionPreferences())
        .alert(item: $pendingDelete) { item in
            Alert(
                title: Text("Delete screenshot?"),
                message: Text(item.fileName),
                primaryButton: .destructive(Text("Delete")) {
                    store.delete(item)
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $editingItem) { item in
            ImageEditorView(store: store, item: item)
        }
        .task {
            store.refreshRequiredPermissions()
            store.refresh()
            scheduleFirstRunOnboarding()
        }
        .onChange(of: didCompleteOnboarding) { _, isComplete in
            guard !isComplete else {
                return
            }

            presentOnboarding()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }

            store.refreshRequiredPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshRequiredPermissions()
        }
    }

    private var sidebarWidth: CGFloat {
        236
    }

    private func previewWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.28, 320), 400)
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let availableWidth = max(width, 360)
        let minimum = availableWidth < 620 ? 170.0 : 210.0
        let maximum = availableWidth < 620 ? 280.0 : 320.0
        return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 18)]
    }

    private func scheduleFirstRunOnboarding() {
        guard !didCompleteOnboarding else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            presentOnboarding()
        }
    }

    private func presentOnboarding() {
        guard !showsOnboarding else {
            return
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            showsOnboarding = true
        }
    }

    private func completeOnboarding() {
        didCompleteOnboarding = true

        withAnimation(.easeInOut(duration: 0.16)) {
            showsOnboarding = false
        }
    }

    private func closePreviewOverlay() {
        withAnimation(.easeInOut(duration: 0.14)) {
            previewItem = nil
        }
    }
}

private struct RegularLayoutView: View {
    @ObservedObject var store: ScreenshotStore
    let columns: [GridItem]
    let sidebarWidth: CGFloat
    let previewWidth: CGFloat
    let showsPreview: Bool
    @Binding var pendingDelete: ScreenshotItem?
    @Binding var editingItem: ScreenshotItem?
    @Binding var previewItem: ScreenshotItem?
    let showGuide: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(store: store, showGuide: showGuide, openSettings: openSettings)
                .frame(width: sidebarWidth)

            Rectangle()
                .fill(AppTheme.softBorder.opacity(0.6))
                .frame(width: 1)

            LibraryView(
                store: store,
                columns: columns,
                pendingDelete: $pendingDelete,
                editingItem: $editingItem,
                previewItem: $previewItem,
                showGuide: showGuide
            )
            .frame(minWidth: 420)

            if showsPreview {
                Divider()

                PreviewPane(
                    store: store,
                    pendingDelete: $pendingDelete,
                    editingItem: $editingItem,
                    previewItem: $previewItem
                )
                .frame(width: previewWidth)
                .transition(.opacity)
            }
        }
    }
}

private struct CompactLayoutView: View {
    @ObservedObject var store: ScreenshotStore
    let columns: [GridItem]
    @Binding var pendingDelete: ScreenshotItem?
    @Binding var editingItem: ScreenshotItem?
    @Binding var previewItem: ScreenshotItem?
    let showGuide: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CompactHeaderView(store: store, showGuide: showGuide)

            Divider()

            LibraryView(
                store: store,
                columns: columns,
                pendingDelete: $pendingDelete,
                editingItem: $editingItem,
                previewItem: $previewItem,
                showGuide: showGuide
            )
        }
    }
}

private struct CompactHeaderView: View {
    @ObservedObject var store: ScreenshotStore
    let showGuide: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                BrandMarkView(isActive: store.isCapturing)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screenshot Manager")
                        .font(AppTypography.productTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(store.isCapturing ? "Selecting an area…" : "Ready to capture")
                        .font(AppTypography.helper)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button(action: showGuide) {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .help("Guide")
            }

            CaptureButtonRow(store: store, isCompact: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background { GlassSurface() }
    }
}

private struct SidebarView: View {
    @ObservedObject var store: ScreenshotStore
    let showGuide: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMarkView(isActive: store.isCapturing)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Screenshot")
                        .font(AppTypography.productTitle)
                    Text("Manager")
                        .font(AppTypography.helper)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)

            SidebarSectionLabel(title: "Capture")

            VStack(spacing: 6) {
                SidebarCaptureButton(
                    title: store.isCapturing ? "Capturing…" : "Copy capture",
                    shortcut: store.clipboardHotkey.compactDisplayString,
                    systemImage: "viewfinder",
                    isPrimary: true,
                    isDisabled: store.isCapturing
                ) {
                    store.captureToClipboard()
                }

                SidebarCaptureButton(
                    title: "Save capture",
                    shortcut: store.saveHotkey.compactDisplayString,
                    systemImage: "square.and.arrow.down",
                    isPrimary: false,
                    isDisabled: store.isCapturing
                ) {
                    store.captureAndSaveToLibrary()
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 28)

            SidebarSectionLabel(title: "Workspace")

            SidebarNavigationButton(
                title: "Library",
                value: "\(store.filteredItems.count)",
                systemImage: "rectangle.stack",
                isSelected: true
            ) {}
            .padding(.horizontal, 10)

            Spacer(minLength: 16)

            SidebarStatusView(store: store)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            VStack(spacing: 3) {
                SidebarNavigationButton(
                    title: "Quick guide",
                    systemImage: "questionmark.circle"
                ) {
                    showGuide()
                }

                SidebarNavigationButton(
                    title: "Settings",
                    systemImage: "gearshape"
                ) {
                    openSettings()
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { GlassSurface() }
    }
}

private struct SidebarSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTypography.eyebrow)
            .foregroundStyle(AppTheme.assetMuted)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
    }
}

private struct SidebarCaptureButton: View {
    let title: String
    let shortcut: String
    let systemImage: String
    let isPrimary: Bool
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 17)

                Text(title)
                    .font(AppTypography.itemTitle)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(shortcut)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(isPrimary ? AppTheme.primaryButtonForeground.opacity(0.72) : AppTheme.assetMuted)
            }
            .foregroundStyle(isPrimary ? AppTheme.primaryButtonForeground : AppTheme.assetInk)
            .padding(.horizontal, 11)
            .frame(height: 42)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { isHovering = $0 }
        .animation(AppMotion.fast, value: isHovering)
    }

    private var background: Color {
        if isPrimary {
            return AppTheme.primaryButtonBackground.opacity(isHovering ? 0.90 : 1)
        }

        return isHovering ? AppTheme.sidebarIconHoverBackground : AppTheme.sidebarIconBackground.opacity(0.5)
    }
}

private struct SidebarNavigationButton: View {
    let title: String
    var value: String? = nil
    let systemImage: String
    var isSelected = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 17)

                Text(title)
                    .font(AppTypography.itemTitle)

                Spacer(minLength: 6)

                if let value {
                    Text(value)
                        .font(AppTypography.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isSelected ? AppTheme.assetInk : AppTheme.assetMuted)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: 2, height: 16)
                        .offset(x: -1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(AppMotion.fast, value: isHovering)
    }

    private var background: Color {
        if isSelected {
            return AppTheme.sidebarIconSelectedBackground
        }

        if isHovering {
            return AppTheme.sidebarIconHoverBackground
        }

        return .clear
    }
}

private struct SidebarStatusView: View {
    @ObservedObject var store: ScreenshotStore

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppTheme.assetInk)
                Text(statusDetail)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(AppTheme.assetMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(AppTheme.sidebarIconBackground.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusTitle: String {
        if store.isCapturing { return "Capture active" }
        return store.requiredPermissionsGranted ? "Ready" : "Action required"
    }

    private var statusDetail: String {
        if store.isCapturing { return "Select an area or window" }
        return store.requiredPermissionsGranted ? "Screen access enabled" : "Screen access is off"
    }

    private var statusColor: Color {
        if store.isCapturing { return AppTheme.accent }
        return store.requiredPermissionsGranted ? AppTheme.successGreen : AppTheme.dangerCoral
    }
}

struct BrandMarkView: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.primaryButtonBackground)

            Image(systemName: "viewfinder")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.primaryButtonForeground)

            Circle()
                .fill(AppTheme.accent)
                .frame(width: 6, height: 6)
                .overlay(Circle().stroke(AppTheme.primaryButtonBackground, lineWidth: 1.5))
                .offset(x: 11, y: -11)
                .opacity(isActive && pulse ? 0.5 : 1)
        }
        .frame(width: 34, height: 34)
        .scaleEffect(isActive && pulse ? 1.035 : 1)
        .onAppear {
            pulse = true
        }
        .animation(isActive ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeInOut(duration: 0.2), value: pulse)
    }
}

private struct CaptureButtonRow: View {
    @ObservedObject var store: ScreenshotStore
    let isCompact: Bool

    var body: some View {
        Group {
            if isCompact {
                HStack(spacing: 8) {
                    captureClipboardButton
                    captureLibraryButton
                }
            } else {
                VStack(spacing: 8) {
                    captureClipboardButton
                    captureLibraryButton
                }
            }
        }
        .controlSize(isCompact ? .regular : .large)
    }

    private var captureClipboardButton: some View {
        Button {
            store.captureToClipboard()
        } label: {
            Label(store.isCapturing ? "Capturing…" : "Copy capture", systemImage: "viewfinder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CodexPrimaryButtonStyle())
        .disabled(store.isCapturing)
    }

    private var captureLibraryButton: some View {
        Button {
            store.captureAndSaveToLibrary()
        } label: {
            Label("Save capture", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CodexSecondaryButtonStyle())
        .disabled(store.isCapturing)
    }

}

private struct CodexPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.itemTitle.weight(.semibold))
            .foregroundStyle(AppTheme.primaryButtonForeground)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(
                AppTheme.primaryButtonBackground.opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.46)
            .animation(AppMotion.fast, value: configuration.isPressed)
    }
}

private struct CodexSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.itemTitle)
            .foregroundStyle(AppTheme.assetInk)
            .padding(.horizontal, 11)
            .frame(minHeight: 32)
            .background(
                configuration.isPressed ? AppTheme.sidebarIconSelectedBackground : AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.46)
            .animation(AppMotion.fast, value: configuration.isPressed)
    }
}

private enum LibrarySortOrder: String, CaseIterable {
    case dateDesc = "Newest First"
    case dateAsc = "Oldest First"
    case nameAsc = "Name A–Z"
    case sizeDesc = "Largest First"
}

private struct LibraryView: View {
    @ObservedObject var store: ScreenshotStore
    let columns: [GridItem]
    @Binding var pendingDelete: ScreenshotItem?
    @Binding var editingItem: ScreenshotItem?
    @Binding var previewItem: ScreenshotItem?
    let showGuide: () -> Void
    @State private var isDropTarget = false
    @State private var sortOrder: LibrarySortOrder = .dateDesc

    private var sortedItems: [ScreenshotItem] {
        switch sortOrder {
        case .dateDesc:
            return store.filteredItems.sorted { $0.createdAt > $1.createdAt }
        case .dateAsc:
            return store.filteredItems.sorted { $0.createdAt < $1.createdAt }
        case .nameAsc:
            return store.filteredItems.sorted { $0.fileName.localizedCompare($1.fileName) == .orderedAscending }
        case .sizeDesc:
            return store.filteredItems.sorted { $0.byteSize > $1.byteSize }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryToolbarView(store: store, sortOrder: $sortOrder)

            Divider()

            if store.filteredItems.isEmpty {
                EmptyStateView(store: store)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(sortedItems) { item in
                            ScreenshotCard(
                                store: store,
                                item: item,
                                isSelected: item.id == store.selectedItem?.id,
                                onSelect: {
                                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                        store.selectedItem = item
                                    }
                                },
                                onOpen: {
                                    withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                                        previewItem = item
                                    }
                                },
                                onEdit: { store.openAnnotationEditor(for: item) },
                                onCopy: { store.copy(item) },
                                onDelete: { pendingDelete = item }
                            )
                            .contextMenu {
                                Button("Edit") { store.openAnnotationEditor(for: item) }
                                Button("Open Preview") { previewItem = item }
                                Button(store.isPinned(item) ? "Unpin Window" : "Pin Window") {
                                    store.togglePin(item)
                                }
                                if !item.isTemporary {
                                    Button("Open in Preview") { store.open(item) }
                                    Button("Reveal in Finder") { store.revealInFinder(item) }
                                }
                                Button("Copy Image") { store.copy(item) }
                                Divider()
                                Button("Delete", role: .destructive) { pendingDelete = item }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity
                            ))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .contentShape(Rectangle())
        .background(AppTheme.contentBackground)
        .overlay {
            if isDropTarget {
                LibraryDropOverlay()
                    .padding(22)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: ScreenshotStore.imageDropTypeIdentifiers,
            isTargeted: $isDropTarget
        ) { providers in
            store.importDroppedItems(providers)
            return true
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: store.filteredItems.isEmpty)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: store.filteredItems.count)
        .animation(.easeInOut(duration: 0.14), value: isDropTarget)
    }
}

private struct LibraryDropOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(AppTheme.captureBlue.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(AppTheme.captureBlue, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            }
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(AppTheme.captureBlue)

                    Text("Drop images to import")
                        .font(AppTypography.sectionTitle)

                    Text("Photos, Finder, PNG, JPG, HEIC, TIFF, or WebP")
                        .font(AppTypography.helper)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.softBorder, lineWidth: 1)
                }
            }
    }
}

private struct LibraryToolbarView: View {
    @ObservedObject var store: ScreenshotStore
    @Binding var sortOrder: LibrarySortOrder

    var body: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(AppTypography.paneTitle)

                Text(itemCountText)
                    .font(AppTypography.helper)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 12)

            SearchField(text: $store.searchText)
                .frame(minWidth: 140, idealWidth: 200, maxWidth: 240)

            Menu {
                ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        if sortOrder == order {
                            Label(order.rawValue, systemImage: "checkmark")
                        } else {
                            Text(order.rawValue)
                        }
                    }
                }

                Divider()

                Button("Refresh Library", systemImage: "arrow.clockwise") {
                    store.refresh()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOrder.rawValue)
                        .lineLimit(1)
                }
                .font(AppTypography.helper.weight(.medium))
                .foregroundStyle(AppTheme.assetInk)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .tint(AppTheme.assetInk)
            .help("Sort and refresh")

            Menu {
                Button {
                    store.captureToClipboard()
                } label: {
                    Label("Capture to Clipboard", systemImage: "doc.on.clipboard")
                }

                Button {
                    store.captureAndSaveToLibrary()
                } label: {
                    Label("Capture to Library", systemImage: "tray.and.arrow.down")
                }
            } label: {
                Label(store.isCapturing ? "Capturing…" : "New capture", systemImage: "viewfinder")
            }
            .buttonStyle(CodexPrimaryButtonStyle())
            .disabled(store.isCapturing)

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 84)
        .background(AppTheme.toolbarBackground)
        .animation(AppMotion.spring, value: store.filteredItems.count)
    }

    private var itemCountText: String {
        let count = store.filteredItems.count
        return "\(count) \(count == 1 ? "item" : "items")"
    }
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search screenshots", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        text = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }
        }
        .font(AppTypography.itemTitle)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(searchBackground, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isFocused ? AppTheme.accent.opacity(0.72) : AppTheme.softBorder, lineWidth: 1)
        }
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.16), value: isFocused)
        .animation(.easeInOut(duration: 0.14), value: isHovering)
    }

    private var searchBackground: Color {
        isFocused || isHovering ? AppTheme.searchFocusedBackground : AppTheme.searchFieldBackground
    }
}

private struct ScreenshotCard: View {
    @ObservedObject var store: ScreenshotStore
    let item: ScreenshotItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @State private var isOpeningPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                ZStack {
                    Rectangle()
                        .fill(AppTheme.imageWellBackground)

                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .transition(.opacity)
                    } else {
                        ThumbnailPlaceholderView()
                    }

                    VStack {
                        HStack {
                            CaptureKindBadge(kind: item.captureKind)
                            Spacer()
                            if isHovering || isSelected {
                                HStack(spacing: 5) {
                                    Button { onEdit() } label: {
                                        CardActionPill(title: "Edit", systemImage: "pencil")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Edit")

                                    Menu {
                                        Button("Open Preview", systemImage: "arrow.up.left.and.arrow.down.right") {
                                            openWithMotion()
                                        }
                                        Button("Copy Image", systemImage: "doc.on.doc") {
                                            onCopy()
                                        }
                                        Divider()
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            onDelete()
                                        }
                                    } label: {
                                        CardActionPill(title: "More", systemImage: "ellipsis")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                    .help("More")
                                }
                                .transition(.opacity)
                            }
                        }
                        Spacer()
                    }
                    .padding(7)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.softBorder.opacity(0.7), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)

            Text(item.fileName)
                .font(AppTypography.itemTitle)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Text(item.createdAt, style: .date)
                Spacer()
                Text(item.dimensionsText)
            }
            .font(AppTypography.metadata)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardBorderColor, lineWidth: isOpeningPreview ? 1.5 : 1)
        }
        .scaleEffect(cardScale)
        .shadow(
            color: .black.opacity(isHovering ? 0.035 : 0),
            radius: isHovering ? 8 : 0,
            x: 0,
            y: isHovering ? 3 : 0
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(count: 2) {
            openWithMotion()
        }
        .onTapGesture {
            onSelect()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.fileName)
        .accessibilityAction {
            onSelect()
        }
        .accessibilityAction(named: "Open Preview") {
            onOpen()
        }
        .focusable()
        .onHover { isHovering = $0 }
        .task(id: "\(item.id)-\(item.modifiedAt.timeIntervalSince1970)-\(item.byteSize)") {
            let loadedThumbnail = await store.thumbnail(for: item, maxPixelSize: 640)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                thumbnail = loadedThumbnail
            }
        }
        .animation(AppMotion.normal, value: isSelected)
        .animation(AppMotion.fast, value: isHovering)
        .animation(AppMotion.spring, value: isOpeningPreview)
    }

    private var cardBackground: Color {
        if isSelected {
            return AppTheme.selectedBackground
        }

        if isHovering {
            return AppTheme.cardHoverBackground
        }

        return .clear
    }

    private var cardBorderColor: Color {
        if isOpeningPreview {
            return AppTheme.accent.opacity(0.92)
        }

        if isSelected {
            return AppTheme.accent.opacity(0.72)
        }

        return isHovering ? AppTheme.border : .clear
    }

    private var cardScale: CGFloat {
        if isOpeningPreview {
            return 0.985
        }

        return 1
    }

    private func openWithMotion() {
        guard !isOpeningPreview else {
            return
        }

        onSelect()

        withAnimation(AppMotion.fast) {
            isOpeningPreview = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            onOpen()

            withAnimation(.easeOut(duration: 0.14)) {
                isOpeningPreview = false
            }
        }
    }
}

private struct ThumbnailPlaceholderView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.imageWellBackground)

            VStack(spacing: 7) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.captureBlue.opacity(pulse ? 0.82 : 0.48))

                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.assetMuted.opacity(0.28))
                    .frame(width: 48, height: 4)
            }
        }
        .onAppear {
            pulse = true
        }
        .animation(.easeInOut(duration: 0.22), value: pulse)
    }
}

private struct CardActionPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .labelStyle(.iconOnly)
            .frame(width: 24, height: 24)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
    }
}

private struct ScreenshotPreviewOverlayView: View {
    @ObservedObject var store: ScreenshotStore
    let item: ScreenshotItem
    let close: () -> Void

    @State private var image: NSImage?
    @State private var fitToWindow = true
    @State private var keyMonitor: Any?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName)
                                .font(AppTypography.sectionTitle)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text("\(item.dimensionsText) · \(item.displaySize)")
                                .font(AppTypography.helper)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            store.pin(item)
                        } label: {
                            Label(store.isPinned(item) ? "Pinned" : "Pin", systemImage: store.isPinned(item) ? "pin.fill" : "pin")
                        }
                        .help("Pin as floating reference window")

                        Button {
                            close()
                            store.openAnnotationEditor(for: item)
                        } label: {
                            Label("Edit", systemImage: "slider.horizontal.3")
                        }

                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                fitToWindow.toggle()
                            }
                        } label: {
                            Label(fitToWindow ? "Actual Size" : "Fit", systemImage: fitToWindow ? "plus.magnifyingglass" : "arrow.down.right.and.arrow.up.left")
                        }

                        Button {
                            store.copy(item)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        Button {
                            close()
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 24, height: 22)
                        }
                        .keyboardShortcut(.cancelAction)
                        .help("Close")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(AppTheme.toolbarBackground)

                    Divider()

                    ZStack {
                        AppTheme.contentBackground

                        if let image {
                            if fitToWindow {
                                GeometryReader { imageProxy in
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .frame(width: imageProxy.size.width, height: imageProxy.size.height)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) {
                                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                                fitToWindow = false
                                            }
                                        }
                                }
                                .padding(18)
                                .transition(.opacity.combined(with: .scale(scale: 0.992)))
                            } else {
                                ScrollView([.horizontal, .vertical]) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: actualPreviewSize.width, height: actualPreviewSize.height)
                                        .padding(22)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) {
                                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                                fitToWindow = true
                                            }
                                        }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.992)))
                            }
                        } else {
                            ProgressView()
                                .controlSize(.large)
                        }
                    }
                }
                .frame(width: panelSize(for: proxy.size).width, height: panelSize(for: proxy.size).height)
                .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            }
        }
        .task(id: item.id) {
            image = nil
            let loadedImage = await store.loadImage(for: item)
            withAnimation(.easeOut(duration: 0.14)) {
                image = loadedImage
            }
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
    }

    private func panelSize(for available: CGSize) -> CGSize {
        CGSize(
            width: min(max(available.width - 96, 680), 1180),
            height: min(max(available.height - 96, 460), 780)
        )
    }

    private var actualPreviewSize: CGSize {
        guard item.pixelWidth > 0, item.pixelHeight > 0 else {
            return CGSize(width: max(image?.size.width ?? 1, 1), height: max(image?.size.height ?? 1, 1))
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return CGSize(
            width: max(CGFloat(item.pixelWidth) / scale, 1),
            height: max(CGFloat(item.pixelHeight) / scale, 1)
        )
    }

    private func installKeyMonitor() {
        removeKeyMonitor()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else {
                return event
            }

            close()
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
}

struct ScreenshotPreviewWindowView: View {
	    @ObservedObject var store: ScreenshotStore
	    let item: ScreenshotItem
	    @State private var image: NSImage?
	    @State private var fitToWindow = true

    private var isPinned: Bool {
        store.isPinned(item)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(AppTypography.sectionTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("\(item.dimensionsText) · \(item.displaySize)")
                        .font(AppTypography.helper)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.togglePin(item)
                } label: {
                    Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                }
                .help(isPinned ? "Close pinned reference window" : "Pin as floating reference window")

                Button {
                    store.openAnnotationEditor(for: item)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        fitToWindow.toggle()
                    }
                } label: {
                    Label(fitToWindow ? "Actual Size" : "Fit", systemImage: fitToWindow ? "plus.magnifyingglass" : "arrow.down.right.and.arrow.up.left")
                }

                Button {
                    store.copy(item)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                if !item.isTemporary {
                    Button {
                        store.revealInFinder(item)
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }

                    Button {
                        store.open(item)
                    } label: {
                        Label("Preview", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(AppTheme.toolbarBackground)

            Divider()

            ZStack {
                AppTheme.contentBackground
                    .ignoresSafeArea()

	                if let image {
	                    if fitToWindow {
	                        GeometryReader { proxy in
	                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                        fitToWindow = false
                                    }
	                                }
	                        }
	                        .padding(18)
	                        .transition(.opacity.combined(with: .scale(scale: 0.992)))
	                    } else {
	                        ScrollView([.horizontal, .vertical]) {
	                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: actualPreviewSize.width, height: actualPreviewSize.height)
                                .padding(24)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                        fitToWindow = true
                                    }
	                                }
	                        }
	                        .transition(.opacity.combined(with: .scale(scale: 0.992)))
	                    }
	                } else {
	                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
	        .frame(minWidth: 900, minHeight: 620)
	        .task(id: item.id) {
	            let loadedImage = await store.loadImage(for: item)
	            withAnimation(.easeOut(duration: 0.16)) {
	                image = loadedImage
	            }
	        }
    }

    private var actualPreviewSize: CGSize {
        guard item.pixelWidth > 0, item.pixelHeight > 0 else {
            return CGSize(width: max(image?.size.width ?? 1, 1), height: max(image?.size.height ?? 1, 1))
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return CGSize(
            width: max(CGFloat(item.pixelWidth) / scale, 1),
            height: max(CGFloat(item.pixelHeight) / scale, 1)
        )
    }
}

/// Floating always-on-top reference window for comparing a screenshot while working elsewhere.
struct PinnedScreenshotWindowView: View {
    @ObservedObject var store: ScreenshotStore
    let pinID: String
    let title: String
    let dimensionsText: String

    @State private var image: NSImage?
    @State private var opacity: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppTypography.helper.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(dimensionsText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                opacityControl

                Button {
                    if let image {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.writeObjects([image])
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Copy image")

                Button {
                    store.unpin(id: pinID)
                } label: {
                    Image(systemName: "pin.slash")
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Unpin and close")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(AppTheme.toolbarBackground)

            Divider()

            ZStack {
                AppTheme.contentBackground

                if let image {
                    GeometryReader { proxy in
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .padding(10)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(minWidth: 280, minHeight: 200)
        .background(AppTheme.windowBackground)
        .task(id: pinID) {
            image = store.pinnedImage(for: pinID)
        }
        .onChange(of: opacity) { _, newValue in
            store.setPinnedWindowOpacity(id: pinID, opacity: newValue)
        }
    }

    private var opacityControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Slider(value: $opacity, in: 0.25...1, step: 0.05)
                .frame(width: 72)
                .controlSize(.mini)
                .help("Window opacity — useful when overlaying on another UI")
        }
    }
}

private struct CaptureKindBadge: View {
    let kind: CaptureKind

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 21, height: 21)
            .background(badgeColor, in: RoundedRectangle(cornerRadius: 5))
            .help(kind.displayName)
    }

    private var badgeColor: Color {
        switch kind {
        case .clipboard:
            return AppTheme.libraryAmber
        case .saved:
            return AppTheme.successGreen
        }
    }
}

private struct PreviewPane: View {
    @ObservedObject var store: ScreenshotStore
    @Binding var pendingDelete: ScreenshotItem?
    @Binding var editingItem: ScreenshotItem?
    @Binding var previewItem: ScreenshotItem?

    var body: some View {
        ZStack {
            AppTheme.panelBackground

            if let item = store.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Preview")
                            .font(AppTypography.paneTitle)

                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(AppTheme.imageWellBackground)

                            AsyncPreviewImageView(store: store, item: item)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(8)
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1.2, contentMode: .fit)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(AppTheme.softBorder, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                        .onTapGesture(count: 2) {
                            previewItem = item
                        }
                        .contextMenu {
                            Button("Open Large Preview") { previewItem = item }
                            Button(store.isPinned(item) ? "Unpin Window" : "Pin Window") {
                                store.togglePin(item)
                            }
                            if !item.isTemporary {
                                Button("Open in Preview") { store.open(item) }
                            }
                        }

                        Text("DETAILS")
                            .font(AppTypography.eyebrow)
                            .tracking(0.7)
                            .foregroundStyle(AppTheme.assetMuted)

                        VStack(alignment: .leading, spacing: 8) {
                            MetadataRow(title: "Type", value: item.captureKind.displayName)
                            MetadataRow(title: "Name", value: item.fileName)
                            MetadataRow(title: "Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            MetadataRow(title: "Dimensions", value: item.dimensionsText)
                            MetadataRow(title: "File size", value: item.displaySize)
                        }
                        .padding(12)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(AppTheme.softBorder, lineWidth: 1)
                        }

                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Button {
                                    store.openAnnotationEditor(for: item)
                                } label: {
                                    Label("Edit", systemImage: "slider.horizontal.3")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(CodexPrimaryButtonStyle())

                                Button {
                                    previewItem = item
                                } label: {
                                    Label("Large View", systemImage: "arrow.up.left.and.arrow.down.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(CodexSecondaryButtonStyle())
                            }

                            HStack(spacing: 8) {
                                Button {
                                    store.copy(item)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(CodexSecondaryButtonStyle())

                                Button {
                                    store.togglePin(item)
                                } label: {
                                    Label(
                                        store.isPinned(item) ? "Unpin" : "Pin",
                                        systemImage: store.isPinned(item) ? "pin.slash" : "pin"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(CodexSecondaryButtonStyle())
                                .help(store.isPinned(item) ? "Close pinned reference" : "Pin as floating reference")
                            }

                            if !item.isTemporary {
                                Button {
                                    store.revealInFinder(item)
                                } label: {
                                    Label("Finder", systemImage: "folder")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(CodexSecondaryButtonStyle())
                            }

                            Button(role: .destructive) {
                                pendingDelete = item
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(18)
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)

                    Text("Select a screenshot")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: store.selectedItem?.id)
    }
}

private struct CaptureNoticeView: View {
    let notice: CaptureNotice

    private var tint: Color {
        switch notice.tone {
        case .success:
            return AppTheme.accent
        case .neutral:
            return .secondary
        case .failure:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.callout.weight(.semibold))

                Text(notice.detail)
                    .font(AppTypography.helper)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .frame(maxWidth: 440)
    }
}

private struct OnboardingOverlayView: View {
    let clipboardHotkey: String
    let saveHotkey: String
    let dismiss: () -> Void

    @State private var selectedStep = 0
    @State private var didAppear = false
    @State private var pulse = false

    private var steps: [OnboardingStep] {
        [
            OnboardingStep(
                icon: "doc.on.clipboard",
                tint: AppTheme.accent,
                title: "Choose the result",
                body: "Use Clipboard for a temporary copied image. Use Library when you want a file plus clipboard copy.",
                action: "\(clipboardHotkey) copies and keeps it in memory"
            ),
            OnboardingStep(
                icon: "crop",
                tint: AppTheme.accent,
                title: "Select an area or window",
                body: "Drag a rectangle, or click a window. Return confirms the current selection; Escape cancels.",
                action: "The overlay shows XY and color while you move"
            ),
            OnboardingStep(
                icon: "checkmark.circle",
                tint: AppTheme.accent,
                title: "Finish in the editor",
                body: "Press Enter to finish. Clipboard stays in memory; Library writes a file and also copies it.",
                action: "\(saveHotkey) saves to Library"
            ),
            OnboardingStep(
                icon: "photo.stack",
                tint: AppTheme.accent,
                title: "Open it later",
                body: "Copied captures still appear in Library. Double-click a card for the large preview window.",
                action: "The Guide button opens this anytime"
            )
        ]
    }

    private var currentStep: OnboardingStep {
        steps[selectedStep]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.captureBlue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick Guide")
                            .font(AppTypography.productTitle)

                        Text("The capture flow in four steps")
                            .font(AppTypography.helper)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Close Guide")
                }
                .padding(16)

                Divider()

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(steps.indices, id: \.self) { index in
                            OnboardingStepRow(
                                step: steps[index],
                                isSelected: index == selectedStep
                            ) {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                                    selectedStep = index
                                }
                            }
                        }
                    }
                    .frame(width: 190)
                    .padding(12)

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        OnboardingMotionPreview(step: currentStep, pulse: pulse)
                            .frame(height: 138)
                            .frame(maxWidth: .infinity)
                            .id(selectedStep)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))

                        VStack(alignment: .leading, spacing: 7) {
                            Text(currentStep.title)
                                .font(AppTypography.paneTitle)

                            Text(currentStep.body)
                                .font(AppTypography.itemTitle)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Label(currentStep.action, systemImage: "info.circle")
                                .font(AppTypography.helper)
                                .foregroundStyle(currentStep.tint)
                                .padding(.top, 2)
                        }
                        .contentTransition(.opacity)

                        Spacer(minLength: 4)

                        HStack(spacing: 8) {
                            ForEach(steps.indices, id: \.self) { index in
                                Capsule()
                                    .fill(index == selectedStep ? currentStep.tint : AppTheme.softBorder)
                                    .frame(width: index == selectedStep ? 22 : 7, height: 7)
                                    .animation(.spring(response: 0.24, dampingFraction: 0.86), value: selectedStep)
                            }

                            Spacer()

                            Button("Skip") {
                                dismiss()
                            }

                            Button {
                                if selectedStep == steps.count - 1 {
                                    dismiss()
                                } else {
                                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                                        selectedStep += 1
                                    }
                                }
                            } label: {
                                Label(selectedStep == steps.count - 1 ? "Done" : "Next", systemImage: selectedStep == steps.count - 1 ? "checkmark" : "arrow.right")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(18)
                    .frame(width: 390)
                }
            }
            .frame(width: 604, height: 414)
            .background(AppTheme.panelBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
            .scaleEffect(didAppear ? 1 : 0.97)
            .opacity(didAppear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                didAppear = true
            }

            pulse = true
        }
        .animation(.easeInOut(duration: 0.24), value: pulse)
    }
}

private struct OnboardingStep: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let title: String
    let body: String
    let action: String
}

private struct OnboardingStepRow: View {
    let step: OnboardingStep
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: step.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : step.tint)
                    .frame(width: 18)

                Text(step.title)
                    .font(AppTypography.itemTitle)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isSelected ? step.tint : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingMotionPreview: View {
    let step: OnboardingStep
    let pulse: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.imageWellBackground)

            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.softBorder, lineWidth: 1)

            HStack(spacing: 12) {
                Image(systemName: step.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(step.tint)
                    .frame(width: 52, height: 52)
                    .background(step.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                    .scaleEffect(pulse ? 1.04 : 0.98)

                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.assetMuted.opacity(0.45))
                        .frame(width: 168, height: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(step.tint.opacity(0.72))
                        .frame(width: pulse ? 132 : 96, height: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.assetMuted.opacity(0.3))
                        .frame(width: 118, height: 8)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }
}

private struct MetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(AppTypography.helper)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(AppTypography.itemTitle)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EmptyStateView: View {
    @ObservedObject var store: ScreenshotStore
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 12) {
            if store.isLoading {
                ProgressView()
                    .controlSize(.large)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.cardBackground)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.softBorder, lineWidth: 1)
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 58, height: 58)
                .padding(.bottom, 4)
                .opacity(didAppear ? 1 : 0)

                Text("No screenshots found")
                    .font(AppTypography.paneTitle)
                    .opacity(didAppear ? 1 : 0)

                Text("Choose a folder, capture, or drag images here.")
                    .font(AppTypography.itemTitle)
                    .foregroundStyle(.secondary)
                    .opacity(didAppear ? 1 : 0)

                HStack(spacing: 8) {
                    Button {
                        store.chooseFolder()
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }
                    .buttonStyle(CodexSecondaryButtonStyle())

                    Button {
                        store.captureToClipboard()
                    } label: {
                        Label("Capture", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(CodexPrimaryButtonStyle())
                    .disabled(store.isCapturing)
                }
                .padding(.top, 4)
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 6)
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                didAppear = true
            }
        }
    }
}

private struct AsyncPreviewImageView: View {
    @ObservedObject var store: ScreenshotStore
    let item: ScreenshotItem
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: item.id) {
            image = await store.loadImage(for: item)
        }
    }
}
