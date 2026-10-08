import AppKit
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: AppHotkey

    func makeNSView(context: Context) -> HotkeyRecorderControl {
        let control = HotkeyRecorderControl()
        control.hotkey = hotkey
        control.onChange = { capturedHotkey in
            hotkey = capturedHotkey
        }
        return control
    }

    func updateNSView(_ nsView: HotkeyRecorderControl, context: Context) {
        nsView.hotkey = hotkey
    }
}

final class HotkeyRecorderControl: NSView {
    var hotkey: AppHotkey = .defaultValue {
        didSet {
            needsDisplay = true
        }
    }

    var onChange: ((AppHotkey) -> Void)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 150, height: 34)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }
        guard let capturedHotkey = AppHotkey(event: event) else {
            NSSound.beep()
            return
        }

        hotkey = capturedHotkey
        onChange?(capturedHotkey)
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.52).setFill()
        path.fill()

        let strokeColor = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.45)
        strokeColor.setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text = isRecording ? "Press shortcut" : hotkey.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isRecording ? .semibold : .regular),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedText.draw(in: textRect)
    }
}
