import SwiftUI

/// Thin visual layer over `NotchState`. No business logic here.
struct NotchView: View {
    @ObservedObject var state: NotchState

    var body: some View {
        ZStack(alignment: .top) {
            switch state.phase {
            case .idle:
                Color.clear
            case .dropTarget(let hovering):
                zone(glowing: false) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 22, weight: .medium))
                        Text("Drop to convert")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(hovering ? Color.white : Color.white.opacity(0.75))
                }
                .scaleEffect(hovering ? 1.03 : 1.0, anchor: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
            case .converting:
                zone(glowing: true) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            case .success:
                zone(glowing: false) {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.green)
                        Text("Copied")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            case .settingsHover:
                VStack {
                    ZStack {
                        UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                            .fill(Color.black.opacity(0.94))
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .frame(width: 120, height: 38)
                    Spacer(minLength: 0)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            case .failure(let message):
                zone(glowing: false) {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.phase)
    }

    /// Black rounded-bottom zone shared by every visible phase.
    /// `glowing` adds the pulsing glow used while converting.
    private func zone<Content: View>(glowing: Bool, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 18
            )
            .fill(Color.black.opacity(0.94))
            .modifier(GlowEffect(active: glowing))

            content()
                .padding(.top, 24)
        }
    }
}

/// Pulsing glow around the zone while a conversion runs.
private struct GlowEffect: ViewModifier {
    let active: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: active ? Color.cyan.opacity(pulse ? 0.9 : 0.4) : .clear,
                radius: active ? (pulse ? 16 : 8) : 0
            )
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
