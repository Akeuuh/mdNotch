import SwiftUI

/// The one spring every phase change of the zone plays with, plus how long the
/// controller has to leave the panel alone for it to finish.
enum NotchAnimation {
    static let phase: Animation = .spring(response: 0.36, dampingFraction: 0.74)
    /// Comfortably past the spring's visible travel. Moving the panel's frame
    /// before this teleports whatever is still animating inside it.
    static let settle: TimeInterval = 0.45
}

/// Thin visual layer over `NotchState`. No business logic here.
struct NotchView: View {
    @ObservedObject var state: NotchState

    private var gearShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: NotchGeometry.cornerRadii(for: state.anchor, radius: NotchGeometry.gearCornerRadius)
        )
    }

    /// Edge every phase animates in from: the one the zone is anchored to.
    private var entryEdge: Edge {
        NotchGeometry.entryEdge(for: state.anchor)
    }

    /// Sign of the drop shadow: it falls away from the anchored edge.
    private var shadowDrop: CGFloat {
        state.anchor.isTop ? 1 : -1
    }

    private var isHovering: Bool {
        state.phase == .dropTarget(hovering: true)
    }

    private var isConverting: Bool {
        state.phase == .converting
    }

    var body: some View {
        ZStack(alignment: NotchGeometry.slabAlignment(for: state.anchor)) {
            // Always mounted. Inserting it on demand would pop it in at full
            // size; kept in the tree, its frame interpolates and the zone
            // grows out of the notch's own footprint.
            zone

            if state.phase == .settingsHover {
                gearPill
                    .transition(.opacity.combined(with: .move(edge: entryEdge)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: NotchGeometry.slabAlignment(for: state.anchor))
        .animation(NotchAnimation.phase, value: state.phase)
        // Geometry here is computed in screen coordinates, so the leading
        // side must stay the left one whatever the system language.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// The black slab hanging off the anchored edge, sized to whatever the
    /// current phase asks for. The shape stays a concrete type on both
    /// branches: erasing it to `AnyShape` would drop its `animatableData` and
    /// the corners would snap instead of opening with the rest.
    @ViewBuilder
    private var zone: some View {
        let size = state.isExtended ? state.expandedSize : state.collapsedSize

        Group {
            if state.anchor == .notch {
                slab(
                    NotchFlareShape(
                        // Collapsed, no flare and the cutout's own corners:
                        // the shape is the hardware's and nothing else.
                        flare: state.isExtended ? NotchGeometry.physicalNotchCornerRadius : 0,
                        bottom: state.isExtended
                            ? NotchGeometry.zoneCornerRadius
                            : NotchGeometry.physicalNotchCornerRadius
                    )
                )
            } else {
                slab(UnevenRoundedRectangle(cornerRadii: NotchGeometry.zoneCornerRadii(for: state.anchor)))
            }
        }
        .scaleEffect(isHovering ? 1.015 : 1, anchor: NotchGeometry.scaleAnchor(for: state.anchor))
        .frame(width: size.width, height: size.height)
    }

    private func slab<S: Shape>(_ shape: S) -> some View {
        ZStack {
            // Behind the slab, so it reads as light spilling out from
            // under the notch rather than a border drawn on top.
            if isConverting {
                IntelligenceGlow(shape: shape)
            }

            shape
                .fill(.black)
                .overlay(
                    // Collapsed, the slab covers the cutout exactly: a rim on
                    // it would outline the hardware notch permanently.
                    shape.stroke(.white.opacity(state.isExtended ? 0.09 : 0), lineWidth: 0.5)
                )
                // Same reason for the shadow, which would otherwise spill onto
                // the menu bar at rest. The glow it sits on would muddy it too.
                .shadow(
                    color: isConverting || !state.isExtended ? .clear : .black.opacity(0.35),
                    radius: 14,
                    y: shadowDrop * 8
                )

            phaseContent
                .padding(.top, state.topInset)
                // Blown up to the slab before clipping: `clipShape` works in
                // the bounds of what it is attached to, so on the bare content
                // it would cut the label to the shape's own inset body.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // While the zone is still near the notch's size there is no
                // room for the content: it must not spill over the menu bar
                // on the way out.
                .clipShape(shape)
                .opacity(state.isExtended ? 1 : 0)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .idle, .settingsHover:
            Color.clear

        case .dropTarget(let hovering):
            VStack(spacing: 7) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text("Drop to convert")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white.opacity(hovering ? 1 : 0.72))
            .transition(.opacity)

        case .converting:
            VStack(spacing: 9) {
                ConversionScan()
                ShimmerLabel("Converting\u{2026}")
            }
            .transition(.opacity)

        case .success(let message):
            VStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white, Color.green)
                Text(message)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
            .transition(.opacity)

        case .failure(let message):
            VStack(spacing: 7) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white, Color.red)
                Text(message)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
            }
            .transition(.opacity)
        }
    }

    /// Settings affordance: a small slab hanging off the anchored edge.
    private var gearPill: some View {
        ZStack {
            gearShape
                .fill(.black.opacity(0.92))
                .overlay(
                    gearShape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 10, y: shadowDrop * 5)

            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Settings")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// The one palette every animated surface of the zone borrows from, so the
/// rim light and whatever runs inside it read as a single source of light.
private enum IntelligenceSpectrum {
    static let blue = Color(red: 0.35, green: 0.55, blue: 1.00)
    static let violet = Color(red: 0.68, green: 0.42, blue: 1.00)
    static let pink = Color(red: 1.00, green: 0.44, blue: 0.74)
    static let amber = Color(red: 1.00, green: 0.66, blue: 0.38)

    /// Closed loop: the last stop repeats the first so the angular sweep has
    /// no seam.
    static let loop: [Color] = [blue, violet, pink, amber, blue]

    /// One accent per document line, so a line keeps its colour across a pass.
    static let accents: [Color] = [blue, violet, pink, amber, violet]
}

/// The beat every animation of the converting phase is derived from. A single
/// period keeps the rim light, the scan and the label on one rhythm — three
/// unrelated tempos read as noise however good each one is on its own.
private enum IntelligencePace {
    static let cycle: TimeInterval = 2.2

    /// Position within the current period, in 0...1, read off the wall clock.
    /// Deriving from the clock rather than from an animated `@State` keeps
    /// this immune to the phase transition's transaction, which would
    /// otherwise override a `repeatForever` and play it exactly once.
    static func progress(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
    }
}

/// Smooth 0...1 ramp with zero slope at both ends. Used wherever a linear
/// `min(max(…))` would show a corner as an element starts or stops moving.
private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// The conversion itself, drawn: a page of plain text lines with a bar of the
/// rim light's spectrum sweeping down it. Every line the bar has passed is
/// markdown — indented behind an accent marker and lit up. Continuous rather
/// than stepped, so there is nothing to read as a stutter.
private struct ConversionScan: View {
    /// Portrait, near enough to paper proportions to read as a page at this
    /// size without being tall enough to crowd the label under it.
    private static let pageWidth: CGFloat = 36
    private static let pageHeight: CGFloat = 46
    private static let pageCornerRadius: CGFloat = 4.5

    /// Line widths as a fraction of the text column, uneven enough to read as
    /// prose rather than as a progress bar. The short ones land where a
    /// paragraph would end.
    private static let lineWidths: [CGFloat] = [1.0, 0.72, 0.9, 0.55, 0.86, 0.64]
    private static let lineHeight: CGFloat = 2
    private static let lineGap: CGFloat = 3.2
    /// Paper margin. The text column never touches the frame.
    private static let marginX: CGFloat = 6.5
    /// How far a converted line slides right to make room for its marker.
    private static let indent: CGFloat = 4
    private static let markerWidth: CGFloat = 3
    /// Vertical distance over which a line changes state. Wider than the gap
    /// between lines, so neighbours overlap and the change travels as a wave.
    private static let transition: CGFloat = 7
    /// Fraction of the period spent travelling. The rest is the pause with the
    /// bar off the page, during which the lines return to plain text.
    private static let travelShare: Double = 0.86

    private static var textHeight: CGFloat {
        CGFloat(lineWidths.count) * lineHeight + CGFloat(lineWidths.count - 1) * lineGap
    }

    private static var marginY: CGFloat {
        (pageHeight - textHeight) / 2
    }

    private var pageShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.pageCornerRadius, style: .continuous)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let progress = IntelligencePace.progress(at: context.date)
            let travel = min(progress / Self.travelShare, 1)
            // Runs 0 -> 1 over the tail of the period, unwinding every line at
            // once while the bar is already past the bottom of the page.
            let rewind = progress <= Self.travelShare
                ? 0
                : smoothstep(0, 1, CGFloat((progress - Self.travelShare) / (1 - Self.travelShare)))
            // Starts above the page and ends below it, so the first and last
            // lines are fully converted before the bar is out of sight.
            let scanY = -Self.transition + CGFloat(travel) * (Self.pageHeight + Self.transition * 2)

            ZStack {
                ZStack {
                    text(scanY: scanY, rewind: rewind)
                    scanBar(scanY: scanY, rewind: rewind)
                }
                // Everything happens inside the sheet: light spilling past the
                // frame would read as a glitch rather than as a page.
                .clipShape(pageShape)

                pageShape.strokeBorder(.white.opacity(0.28), lineWidth: 1)
            }
            .frame(width: Self.pageWidth, height: Self.pageHeight)
        }
        .frame(width: Self.pageWidth, height: Self.pageHeight)
    }

    private func text(scanY: CGFloat, rewind: CGFloat) -> some View {
        Canvas { context, size in
            let column = size.width - Self.marginX * 2

            for (index, fraction) in Self.lineWidths.enumerated() {
                let top = Self.marginY + CGFloat(index) * (Self.lineHeight + Self.lineGap)
                let middle = top + Self.lineHeight / 2
                let converted = smoothstep(
                    middle - Self.transition / 2,
                    middle + Self.transition / 2,
                    scanY
                ) * (1 - rewind)

                let indent = Self.indent * converted
                let bar = CGRect(
                    x: Self.marginX + indent,
                    y: top,
                    width: (column - indent) * fraction,
                    height: Self.lineHeight
                )
                context.fill(
                    Path(roundedRect: bar, cornerRadius: Self.lineHeight / 2),
                    // Plain text sits back in the slab; markdown reads lit.
                    with: .color(.white.opacity(0.2 + 0.7 * Double(converted)))
                )

                guard converted > 0 else { continue }
                let marker = CGRect(
                    x: Self.marginX,
                    y: top,
                    width: Self.markerWidth,
                    height: Self.lineHeight
                )
                context.fill(
                    Path(roundedRect: marker, cornerRadius: Self.lineHeight / 2),
                    with: .color(
                        IntelligenceSpectrum.accents[index % IntelligenceSpectrum.accents.count]
                            .opacity(Double(converted))
                    )
                )
            }
        }
    }

    /// The bar of light doing the work: a tight line over a wide soft halo,
    /// the same two-pass build as the rim light around the slab.
    private func scanBar(scanY: CGFloat, rewind: CGFloat) -> some View {
        let gradient = LinearGradient(
            colors: [.clear] + IntelligenceSpectrum.loop.dropLast() + [.clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        let alpha = Double(1 - rewind)

        return ZStack {
            gradient
                .frame(width: Self.pageWidth, height: 9)
                .blur(radius: 6)
                .opacity(alpha * 0.6)
            gradient
                .frame(width: Self.pageWidth, height: 1.2)
                .blur(radius: 1.2)
                .opacity(alpha)
        }
        .position(x: Self.pageWidth / 2, y: scanY)
    }
}

/// A label lit by a band of the rim light's own spectrum sweeping across it.
/// The text under the band stays dim, so the sweep is the only thing moving.
private struct ShimmerLabel: View {
    private let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    private var label: some View {
        Text(key)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
    }

    var body: some View {
        label
            .foregroundStyle(.white.opacity(0.4))
            .overlay {
                GeometryReader { proxy in
                    TimelineView(.animation) { context in
                        let width = proxy.size.width
                        let progress = CGFloat(IntelligencePace.progress(at: context.date))

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: IntelligenceSpectrum.violet, location: 0.3),
                                .init(color: .white, location: 0.5),
                                .init(color: IntelligenceSpectrum.pink, location: 0.7),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.9)
                        // Starts fully off the leading side and ends fully off
                        // the trailing one, so the wrap is never visible.
                        .offset(x: (progress * 2 - 1) * width * 1.5)
                    }
                }
                .mask(label)
            }
    }
}

/// The zone as it hangs off the notch. Its two top corners are inverted
/// fillets: the body is inset from the full width, and each side sweeps back
/// out to meet the screen edge tangentially — the way the cutout flares into
/// the bezel, rather than a rectangle butted against it. The bottom corners
/// are ordinary convex ones facing into the screen.
private struct NotchFlareShape: Shape {
    /// Radius of the inverted fillet joining the body to the screen edge.
    var flare: CGFloat
    /// Radius of the two corners facing into the screen.
    var bottom: CGFloat

    /// Control points at `k * r` put a cubic within a thousandth of a true
    /// quarter arc. Cheaper to reason about here than `addArc`, whose
    /// `clockwise` flag is measured in a flipped coordinate space.
    private static let k: CGFloat = 0.5523

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottom) }
        set {
            flare = newValue.first
            bottom = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        // Clamped so a half-open zone, mid-animation, can never fold on itself.
        let flare = max(0, min(self.flare, width / 2, height))
        let bottom = max(0, min(self.bottom, (width - flare * 2) / 2, height - flare))
        let kFlare = Self.k * flare
        let kBottom = Self.k * bottom

        var path = Path()
        // Starts on the screen edge, tangent to it, so the flare leaves the
        // edge without a crease.
        path.move(to: CGPoint(x: 0, y: 0))
        if flare > 0 {
            path.addCurve(
                to: CGPoint(x: flare, y: flare),
                control1: CGPoint(x: kFlare, y: 0),
                control2: CGPoint(x: flare, y: flare - kFlare)
            )
        }
        path.addLine(to: CGPoint(x: flare, y: height - bottom))
        if bottom > 0 {
            path.addCurve(
                to: CGPoint(x: flare + bottom, y: height),
                control1: CGPoint(x: flare, y: height - bottom + kBottom),
                control2: CGPoint(x: flare + bottom - kBottom, y: height)
            )
        }
        path.addLine(to: CGPoint(x: width - flare - bottom, y: height))
        if bottom > 0 {
            path.addCurve(
                to: CGPoint(x: width - flare, y: height - bottom),
                control1: CGPoint(x: width - flare - bottom + kBottom, y: height),
                control2: CGPoint(x: width - flare, y: height - bottom + kBottom)
            )
        }
        path.addLine(to: CGPoint(x: width - flare, y: flare))
        if flare > 0 {
            path.addCurve(
                to: CGPoint(x: width, y: 0),
                control1: CGPoint(x: width - flare, y: flare - kFlare),
                control2: CGPoint(x: width - kFlare, y: 0)
            )
        }
        // Back along the screen edge.
        path.closeSubpath()

        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

/// Apple-Intelligence-flavoured rim light: a slowly rotating angular
/// gradient, once as a soft bloom and once as a tight rim, breathing gently.
private struct IntelligenceGlow<S: Shape>: View {
    let shape: S

    @State private var angle: Double = 0
    @State private var breathing = false

    var body: some View {
        let gradient = AngularGradient(
            colors: IntelligenceSpectrum.loop,
            center: .center,
            angle: .degrees(angle)
        )

        ZStack {
            // Wide soft spill. Its reach sets NotchGeometry.glowPadding.
            shape
                .stroke(gradient, lineWidth: 20)
                .blur(radius: 26)
                .opacity(breathing ? 0.55 : 0.3)
            // Bloom.
            shape
                .stroke(gradient, lineWidth: 12)
                .blur(radius: 12)
                .opacity(breathing ? 1 : 0.7)
            // Tight rim.
            shape
                .stroke(gradient, lineWidth: 3)
                .blur(radius: 2)
        }
        .onAppear {
            // Four turns of the label sweep per rotation, one breath per
            // sweep: the rim light shares the beat of what runs inside it.
            withAnimation(.linear(duration: IntelligencePace.cycle * 4).repeatForever(autoreverses: false)) {
                angle = 360
            }
            withAnimation(.easeInOut(duration: IntelligencePace.cycle / 2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}
