import SwiftUI

/// Thin visual layer over `NotchState`. No business logic here.
struct NotchView: View {
    @ObservedObject var state: NotchState

    private var zoneShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: NotchGeometry.cornerRadii(for: state.anchor, radius: NotchGeometry.zoneCornerRadius)
        )
    }

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

    var body: some View {
        ZStack(alignment: NotchGeometry.slabAlignment(for: state.anchor)) {
            switch state.phase {
            case .idle:
                Color.clear

            case .settingsHover:
                gearPill
                    .transition(.opacity.combined(with: .move(edge: entryEdge)))

            case .dropTarget(let hovering):
                zone(hovering: hovering) {
                    VStack(spacing: 7) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text("Drop to convert")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(hovering ? 1 : 0.72))
                }
                .transition(.move(edge: entryEdge).combined(with: .opacity))

            case .converting:
                zone(glowing: true) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                .transition(.move(edge: entryEdge).combined(with: .opacity))

            case .success(let message):
                zone {
                    VStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white, Color.green)
                        Text(message)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .transition(.move(edge: entryEdge).combined(with: .opacity))

            case .failure(let message):
                zone {
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
                }
                .transition(.move(edge: entryEdge).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: NotchGeometry.slabAlignment(for: state.anchor))
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.phase)
        // Geometry here is computed in screen coordinates, so the leading
        // side must stay the left one whatever the system language.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// The black slab hanging off the anchored edge. `content` is centered in
    /// the visible part; anything behind the notch is never seen.
    private func zone<Content: View>(
        hovering: Bool = false,
        glowing: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            // Behind the slab, so it reads as light spilling out from
            // under the notch rather than a border drawn on top.
            if glowing {
                IntelligenceGlow(shape: zoneShape)
            }

            zoneShape
                .fill(.black)
                .overlay(
                    zoneShape.strokeBorder(.white.opacity(0.09), lineWidth: 0.5)
                )
                // The drop shadow would muddy the glow it sits on.
                .shadow(color: glowing ? .clear : .black.opacity(0.35), radius: 14, y: shadowDrop * 8)

            content()
                .padding(.top, state.topInset)
        }
        .scaleEffect(hovering ? 1.015 : 1, anchor: NotchGeometry.scaleAnchor(for: state.anchor))
        .padding(NotchGeometry.slabPadding(for: state.anchor))
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

/// Apple-Intelligence-flavoured rim light: a slowly rotating angular
/// gradient, once as a soft bloom and once as a tight rim, breathing gently.
private struct IntelligenceGlow: View {
    let shape: UnevenRoundedRectangle

    @State private var angle: Double = 0
    @State private var breathing = false

    private static let spectrum: [Color] = [
        Color(red: 0.35, green: 0.55, blue: 1.00),
        Color(red: 0.68, green: 0.42, blue: 1.00),
        Color(red: 1.00, green: 0.44, blue: 0.74),
        Color(red: 1.00, green: 0.66, blue: 0.38),
        Color(red: 0.35, green: 0.55, blue: 1.00),
    ]

    var body: some View {
        let gradient = AngularGradient(
            colors: Self.spectrum,
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
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                angle = 360
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}
