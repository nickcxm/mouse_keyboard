import SwiftUI

struct WindowDisplayMoveOverlayView: View {
    let appName: String
    let targets: [WindowDisplayMoveTarget]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isPresented = false

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build) · 20261127-1142)"
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(L10n.tr("display_move.title", appName))
                    .font(.title2.bold())
                    .lineLimit(1)

                Text(L10n.tr("display_move.hint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(targets) { target in
                        WindowDisplayMoveScreenView(target: target)
                            .frame(width: 160)
                    }
                }
                // Selection rings extend 8 pt beyond the display silhouettes.
                // Keep them inside the scroll viewport, including its top edge.
                .padding(12)
            }

            HStack(spacing: 24) {
                Label(L10n.tr("tile.shortcut_arrange"), systemImage: "rectangle.split.2x2")
                Label(L10n.tr("tile.shortcut_restore"), systemImage: "arrow.uturn.backward")
            }
            .font(.callout.bold())
            .foregroundStyle(.primary)
            Text(L10n.tr("tile.global_maximize_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(versionLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
            }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.52), .white.opacity(0.08), .black.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(isPresented || reduceMotion ? 1 : 0.965)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 1)) {
                isPresented = true
            }
        }
    }
}
