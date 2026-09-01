import SwiftUI

/// Thin visual layer over `NotchState`. No business logic here.
struct NotchView: View {
    @ObservedObject var state: NotchState

    private var zoneShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22)
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch state.phase {
            case .idle:
                Color.clear

            case .settingsHover:
                gearPill
                    .transition(.opacity.combined(with: .move(edge: .top)))

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
                .transition(.move(edge: .top).combined(with: .opacity))

            case .converting:
                zone(glowing: true) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                .transition(.move(edge: .top).combined(with: .opacity))

            case .success:
                zone {
                    VStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white, Color.green)
                        Text("Copied")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))

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
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: state.phase)
    }

    /// The black slab hanging from the notch. `content` is centered in the
    /// part below the notch; the rest sits behind it and is never seen.
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
                .shadow(color: glowing ? .clear : .black.opacity(0.35), radius: 14, y: 8)

            content()
                .padding(.top, state.topInset)
        }
        .scaleEffect(hovering ? 1.015 : 1, anchor: .top)
        .padding(.horizontal, NotchGeometry.glowPadding)
        .padding(.bottom, NotchGeometry.glowPadding)
    }

    /// Settings affordance: a small slab hanging just under the notch.
    private var gearPill: some View {
        ZStack {
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
                .fill(.black.opacity(0.92))
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

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
            // Wide soft spill.
            shape
                .stroke(gradient, lineWidth: 26)
                .blur(radius: 30)
                .opacity(breathing ? 0.55 : 0.3)
            // Bloom.
            shape
                .stroke(gradient, lineWidth: 14)
                .blur(radius: 14)
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
