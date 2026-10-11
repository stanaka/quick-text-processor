import AppKit

/// Borderless, non-activating floating panel that can still become the key
/// window. `.nonactivatingPanel` lets it take keyboard input WITHOUT
/// activating this app — the target app stays frontmost, keeping its focused
/// element and selection intact for insert-back (Spotlight-style behavior).
/// Borderless windows refuse key status unless `canBecomeKey` is overridden.
final class KeyablePanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func makeFloating(content: NSView) -> KeyablePanel {
        let panel = KeyablePanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                 backing: .buffered,
                                 defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = content
        return panel
    }
}

/// Shared helper: clamp a panel near the mouse pointer onto its screen.
@MainActor
func positionPanelNearMouse(_ panel: NSWindow, offset: CGFloat = 14) {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    let size = panel.frame.size
    var origin = NSPoint(x: mouse.x - size.width / 2,
                         y: mouse.y - size.height - offset)
    origin.x = min(max(origin.x, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
    origin.y = min(max(origin.y, visible.minY + 8), max(visible.minY + 8, visible.maxY - size.height - 8))
    panel.setFrameOrigin(origin)
}
