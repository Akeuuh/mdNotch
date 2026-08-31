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
                dropZone(hovering: hovering)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.phase)
    }

    private func dropZone(hovering: Bool) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 18
            )
            .fill(Color.black.opacity(0.94))

            VStack(spacing: 4) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 22, weight: .medium))
                Text("Drop to convert")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hovering ? Color.white : Color.white.opacity(0.75))
            .padding(.top, 24)
        }
        .scaleEffect(hovering ? 1.03 : 1.0, anchor: .top)
    }
}
