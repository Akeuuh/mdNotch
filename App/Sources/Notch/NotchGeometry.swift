import AppKit

/// Frames for the notch drop zone. The notch is only a visual anchor: on a
/// screen without one, everything falls back to a fixed-width zone anchored
/// top-center.
enum NotchGeometry {
    static let fallbackNotchWidth: CGFloat = 200
    static let zoneHeight: CGFloat = 88

    static func notchWidth(for screen: NSScreen) -> CGFloat {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            return screen.frame.width - left.width - right.width
        }
        return fallbackNotchWidth
    }

    static func zoneSize(for screen: NSScreen) -> CGSize {
        CGSize(width: notchWidth(for: screen) + 140, height: zoneHeight)
    }

    /// Window frame: flush with the top edge, centered horizontally.
    static func windowFrame(on screen: NSScreen) -> NSRect {
        let size = zoneSize(for: screen)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Region (screen coordinates) whose mouse hover reveals the settings
    /// gear: the notch itself (or its top-center stand-in).
    static func hoverRegion(on screen: NSScreen) -> NSRect {
        let width = notchWidth(for: screen)
        let height = max(screen.safeAreaInsets.top, 28)
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Region (screen coordinates) in which an approaching file drag makes
    /// the drop zone appear. Larger than the visible zone so the zone opens
    /// before the cursor reaches it.
    static func triggerRegion(on screen: NSScreen) -> NSRect {
        let width = max(zoneSize(for: screen).width + 220, 540)
        let height: CGFloat = 150
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
}
