import SwiftUI

struct WindowDisplayMoveScreenView: View {
    let target: WindowDisplayMoveTarget
    var thumbnailHeight: CGFloat = 108

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if target.isBuiltIn {
                    BuiltInDisplaySilhouetteView(
                        displayNumber: target.id,
                        isCurrent: target.containsCurrentWindow
                    )
                } else {
                    ExternalDisplaySilhouetteView(
                        displayNumber: target.id,
                        aspectRatio: target.aspectRatio,
                        isCurrent: target.containsCurrentWindow
                    )
                }
            }
            .frame(width: min(160, thumbnailHeight * 1.6), height: thumbnailHeight)

            Text(target.name)
                .font(.callout.bold())
                .lineLimit(1)

            if target.containsCurrentWindow {
                Text(L10n.tr("display_move.current"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(" ")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("display_move.display_accessibility", target.id, target.name))
    }
}
