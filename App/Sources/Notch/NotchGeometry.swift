import AppKit
import SwiftUI

/// Frames for the drop zone. The zone hangs from the notch by default — on a
/// screen without one, from a fixed-width strip anchored top-center — and can
/// be moved to any screen corner instead. Whatever the anchor, the zone is
/// flush with the screen edges it touches and only bleeds inward.
enum NotchGeometry {
    static let fallbackNotchWidth: CGFloat = 200
    /// Visible height of the notch-anchored drop zone *below* the notch.
    static let zoneBodyHeight: CGFloat = 84
    /// Visible size of a corner-anchored zone. No dead strip to clear there,
    /// so it carries its full height itself.
    static let cornerZoneSize = CGSize(width: 210, height: 96)
    /// Transparent margin kept around the zone so the glow can bleed out
    /// without being clipped by the window. Must exceed the widest glow
    /// pass's reach (half its stroke plus roughly twice its blur radius),
    /// otherwise the halo ends on a hard window edge.
    static let glowPadding: CGFloat = 76
    /// The settings pill that hangs off the anchor on hover.
    static let gearSize = CGSize(width: 128, height: 34)
    static let zoneCornerRadius: CGFloat = 22
    static let gearCornerRadius: CGFloat = 16

    static func notchWidth(for screen: NSScreen) -> CGFloat {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            return screen.frame.width - left.width - right.width
        }
        return fallbackNotchWidth
    }

    /// Height of the dead strip at the top of the screen: the notch itself,
    /// or the menu bar on screens without one.
    static func topInset(for screen: NSScreen) -> CGFloat {
        screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 24
    }

    /// How far content must sit from the anchored edge. Only the notch hides
    /// pixels; a corner zone draws over the menu bar or the Dock, so its
    /// content can use the whole slab.
    static func contentTopInset(for anchor: DropZoneAnchor, on screen: NSScreen) -> CGFloat {
        anchor == .notch ? topInset(for: screen) : 0
    }

    static func zoneSize(for anchor: DropZoneAnchor, on screen: NSScreen) -> CGSize {
        guard anchor == .notch else { return cornerZoneSize }
        return CGSize(
            width: notchWidth(for: screen) + 160,
            height: topInset(for: screen) + zoneBodyHeight
        )
    }

    /// Window frame for the drop zone: the visible zone plus `glowPadding` of
    /// transparent bleed on every side that is not flush with a screen edge.
    static func windowFrame(for anchor: DropZoneAnchor, on screen: NSScreen) -> NSRect {
        let zone = anchoredRect(size: zoneSize(for: anchor, on: screen), anchor: anchor, screen: screen)
        return bleeding(zone, for: anchor)
    }

    /// Window frame for the settings pill. Under the notch it hangs from the
    /// notch's bottom edge — content drawn inside the notch is invisible. In a
    /// corner it clears the menu bar or the Dock instead, so a hover never
    /// drops it on top of a menu or Dock icon the user was aiming for.
    static func gearFrame(for anchor: DropZoneAnchor, on screen: NSScreen) -> NSRect {
        anchoredRect(
            size: gearSize,
            anchor: anchor,
            screen: screen,
            edgeOffset: edgeClearance(for: anchor, on: screen)
        )
    }

    /// Hovering here reveals the settings pill: the notch strip (widened so
    /// the pointer doesn't have to thread the exact notch width), or a small
    /// patch in the anchored corner.
    static func hoverRegion(for anchor: DropZoneAnchor, on screen: NSScreen) -> NSRect {
        if anchor == .notch {
            return anchoredRect(
                size: CGSize(width: notchWidth(for: screen) + 80, height: topInset(for: screen)),
                anchor: anchor,
                screen: screen
            )
        }
        return anchoredRect(
            size: CGSize(width: gearSize.width, height: 56),
            anchor: anchor,
            screen: screen,
            edgeOffset: edgeClearance(for: anchor, on: screen)
        )
    }

    /// Once the pill is out, it stays out while the pointer is anywhere in the
    /// hover region or on the pill itself — so it can be moved onto the pill
    /// and clicked.
    static func gearKeepRegion(for anchor: DropZoneAnchor, on screen: NSScreen) -> NSRect {
        hoverRegion(for: anchor, on: screen)
            .union(gearFrame(for: anchor, on: screen).insetBy(dx: -16, dy: -8))
    }

    /// Region in which an approaching file drag makes the drop zone appear.
    /// Larger than the visible zone so the zone opens before the cursor
    /// reaches it.
    static func triggerRegion(for anchor: DropZoneAnchor, on screen: NSScreen) -> NSRect {
        let size: CGSize
        if anchor == .notch {
            size = CGSize(width: max(zoneSize(for: anchor, on: screen).width + 220, 540), height: 150)
        } else {
            size = CGSize(width: cornerZoneSize.width + 90, height: cornerZoneSize.height + 90)
        }
        return anchoredRect(size: size, anchor: anchor, screen: screen)
    }

    // MARK: - SwiftUI layout

    /// Transparent bleed inside the window, as insets the slab is padded by.
    /// Mirrors what `bleeding(_:for:)` added to the window frame.
    static func slabPadding(for anchor: DropZoneAnchor) -> EdgeInsets {
        EdgeInsets(
            top: anchor.isTop ? 0 : glowPadding,
            leading: anchor.horizontal == .leading ? 0 : glowPadding,
            bottom: anchor.isTop ? glowPadding : 0,
            trailing: anchor.horizontal == .trailing ? 0 : glowPadding
        )
    }

    static func slabAlignment(for anchor: DropZoneAnchor) -> Alignment {
        switch (anchor.isTop, anchor.horizontal) {
        case (true, .center): return .top
        case (true, .leading): return .topLeading
        case (true, .trailing): return .topTrailing
        case (false, .center): return .bottom
        case (false, .leading): return .bottomLeading
        case (false, .trailing): return .bottomTrailing
        }
    }

    /// Rounds only the corners that face into the screen: the ones sitting on
    /// a screen edge stay square, so the slab reads as an extension of the
    /// bezel rather than a floating card.
    static func cornerRadii(for anchor: DropZoneAnchor, radius: CGFloat) -> RectangleCornerRadii {
        switch anchor {
        case .notch:
            return RectangleCornerRadii(bottomLeading: radius, bottomTrailing: radius)
        case .topLeft:
            return RectangleCornerRadii(bottomTrailing: radius)
        case .topRight:
            return RectangleCornerRadii(bottomLeading: radius)
        case .bottomLeft:
            return RectangleCornerRadii(topTrailing: radius)
        case .bottomRight:
            return RectangleCornerRadii(topLeading: radius)
        }
    }

    /// Edge the zone slides in from, and the anchor scaling grows from.
    static func entryEdge(for anchor: DropZoneAnchor) -> Edge {
        anchor.isTop ? .top : .bottom
    }

    static func scaleAnchor(for anchor: DropZoneAnchor) -> UnitPoint {
        anchor.isTop ? .top : .bottom
    }

    // MARK: - Anchoring

    /// `size` pinned to the screen edges the anchor touches, pushed
    /// `edgeOffset` inward from the horizontal edge.
    private static func anchoredRect(
        size: CGSize,
        anchor: DropZoneAnchor,
        screen: NSScreen,
        edgeOffset: CGFloat = 0
    ) -> NSRect {
        let frame = screen.frame
        let x: CGFloat
        switch anchor.horizontal {
        case .center: x = frame.midX - size.width / 2
        case .leading: x = frame.minX
        case .trailing: x = frame.maxX - size.width
        }
        let y = anchor.isTop
            ? frame.maxY - size.height - edgeOffset
            : frame.minY + edgeOffset
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Grows `rect` by `glowPadding` on the sides that are not flush with a
    /// screen edge. Nothing is added on a flush side: the glow would spill
    /// off-screen there anyway.
    private static func bleeding(_ rect: NSRect, for anchor: DropZoneAnchor) -> NSRect {
        var frame = rect
        if anchor.isTop {
            frame.origin.y -= glowPadding
        }
        frame.size.height += glowPadding

        switch anchor.horizontal {
        case .center:
            frame.origin.x -= glowPadding
            frame.size.width += glowPadding * 2
        case .leading:
            frame.size.width += glowPadding
        case .trailing:
            frame.origin.x -= glowPadding
            frame.size.width += glowPadding
        }
        return frame
    }

    /// Vertical offset keeping a hover affordance out of the system furniture
    /// on the anchored edge: the menu bar at the top, the Dock at the bottom
    /// (zero when it is hidden or on a side).
    private static func edgeClearance(for anchor: DropZoneAnchor, on screen: NSScreen) -> CGFloat {
        anchor.isTop
            ? topInset(for: screen)
            : screen.visibleFrame.minY - screen.frame.minY
    }
}
