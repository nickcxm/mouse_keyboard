import SwiftUI

struct BuiltInDisplaySilhouetteView: View {
    let displayNumber: Int
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.black.opacity(0.82))
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.32), .black.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(4)

                Text(displayNumber, format: .number)
                    .font(.largeTitle.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
            .aspectRatio(1.6, contentMode: .fit)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(.black)
                    .frame(width: 24, height: 3)
                    .padding(.top, 2)
            }

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.78), .gray.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 8)
                .padding(.horizontal, -9)
                .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
        }
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.9), lineWidth: 2)
                    .padding(-7)
            }
        }
    }
}
