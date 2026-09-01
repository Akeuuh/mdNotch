import AppKit

/// Frames for the notch drop zone. The notch is only a visual anchor: on a
/// screen without one, everything falls back to a fixed-width zone anchored
/// top-center.
enum NotchGeometry {
    static let fallbackNotchWidth: CGFloat = 200
    /// Visible height of the drop zone *below* the notch.
    static let zoneBodyHeight: CGFloat = 84
    /// Transparent margin kept around the zone so the glow can bleed out
    /// without being clipped by the window. Must exceed the widest glow
    /// pass's reach (half its stroke plus roughly twice its blur radius),
    /// otherwise the halo ends on a hard window edge.
    static let glowPadding: CGFloat = 76
    /// The settings pill that hangs under the notch on hover.
    static let gearSize = CGSize(width: 128, height: 34)

    static func notchWidth(for screen: NSScreen) -> CGFloat {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            return screen.frame.width - left.width - right.width
        }
        return fallbackNotchWidth
    }

    /// Height of the dead strip at the top of the screen: the notch itself,
    /// or the menu bar on screens without one. Nothing drawn inside it is
    /// visible, so all content sits below it.
    static func topInset(for screen: NSScreen) -> CGFloat {
        screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 24
    }

    static func zoneSize(for screen: NSScreen) -> CGSize {
        CGSize(
            width: notchWidth(for: screen) + 160,
            height: topInset(for: screen) + zoneBodyHeight
        )
    }

    /// Window frame for the drop zone: flush with the top edge, centered,
    /// plus `glowPadding` of transparent bleed on the sides and bottom.
    static func windowFrame(on screen: NSScreen) -> NSRect {
        let size = zoneSize(for: screen)
        return NSRect(
            x: screen.frame.midX - (size.width + glowPadding * 2) / 2,
            y: screen.frame.maxY - size.height - glowPadding,
            width: size.width + glowPadding * 2,
            height: size.height + glowPadding
        )
    }

    /// Window frame for the settings pill: hangs from the bottom edge of the
    /// notch, never overlapping it — content drawn under the notch is
    /// invisible.
    static func gearFrame(on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - gearSize.width / 2,
            y: screen.frame.maxY - topInset(for: screen) - gearSize.height,
            width: gearSize.width,
            height: gearSize.height
        )
    }

    /// Hovering here reveals the settings gear: the notch strip, widened so
    /// the pointer doesn't have to thread the exact notch width.
    static func hoverRegion(on screen: NSScreen) -> NSRect {
        let width = notchWidth(for: screen) + 80
        let height = topInset(for: screen)
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Once the gear is out, it stays out while the pointer is anywhere in
    /// the notch strip or on the pill itself — so it can be moved onto the
    /// gear and clicked.
    static func gearKeepRegion(on screen: NSScreen) -> NSRect {
        hoverRegion(on: screen).union(gearFrame(on: screen).insetBy(dx: -16, dy: -8))
    }

    /// Region in which an approaching file drag makes the drop zone appear.
    /// Larger than the visible zone so the zone opens before the cursor
    /// reaches it.
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
