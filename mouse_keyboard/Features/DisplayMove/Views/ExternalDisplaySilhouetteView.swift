import SwiftUI

struct ExternalDisplaySilhouetteView: View {
    let displayNumber: Int
    let aspectRatio: CGFloat
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.black.opacity(0.86))
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.28), .black.opacity(0.7)],
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
            .aspectRatio(aspectRatio, contentMode: .fit)

            RoundedRectangle(cornerRadius: 2)
                .fill(.gray.gradient)
                .frame(width: 8, height: 16)

            Capsule()
                .fill(.gray.gradient)
                .frame(width: 54, height: 7)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
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
