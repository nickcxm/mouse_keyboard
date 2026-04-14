import AppKit
import Combine
import SwiftUI

final class AppSwitcherOverlayController {
    enum MoveDirection {
        case up
        case down
        case left
        case right
    }

    private struct AppItem {
        let id: Int
        let app: NSRunningApplication

        var idText: String {
            String(id)
        }
    }

    fileprivate struct AppCellViewData: Identifiable {
        let id: Int
        let name: String
        let icon: NSImage?
    }

    fileprivate final class ViewModel: ObservableObject {
        @Published var items: [AppCellViewData] = []
        @Published var selectedIndex: Int = 0
        @Published var typedIdentifier: String = ""
        @Published var hintText: String = L10n.tr("app_switcher.hint")
    }

    private enum Config {
        static let columns = 6
        static let windowSize = NSSize(width: 900, height: 560)
        static let fadeDuration: TimeInterval = 0.2
        static let cornerRadius: CGFloat = 12
        static let contentPadding: CGFloat = 20
    }

    private var window: NSWindow?
    private let viewModel = ViewModel()

    private var items: [AppItem] = []
    private var selectedIndex = 0
    private var typedIdentifier = ""

    var isVisible: Bool {
        window?.isVisible == true
    }

    var currentInputIdentifier: String {
        typedIdentifier
    }

    var hasInputIdentifier: Bool {
        !typedIdentifier.isEmpty
    }

    @discardableResult
    func show() -> Bool {
        reloadRunningApps()
        guard !items.isEmpty else {
            hide()
            return false
        }

        typedIdentifier = ""
        selectedIndex = min(max(selectedIndex, 0), items.count - 1)

        let overlay = makeWindowIfNeeded()
        syncViewModel(animated: false)

        let frame = targetFrame()
        overlay.setFrame(frame, display: false)
        overlay.alphaValue = 0
        overlay.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.fadeDuration
            overlay.animator().alphaValue = 1
        }

        return true
    }

    func hide() {
        guard let window else {
            return
        }

        typedIdentifier = ""
        syncViewModel(animated: false)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Config.fadeDuration
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    func moveSelection(_ direction: MoveDirection) {
        guard !items.isEmpty else {
            return
        }

        typedIdentifier = ""

        let columns = Config.columns
        let row = selectedIndex / columns
        let col = selectedIndex % columns

        switch direction {
        case .left:
            if col > 0 {
                selectedIndex -= 1
            }
        case .right:
            let candidate = selectedIndex + 1
            if candidate < items.count, candidate / columns == row {
                selectedIndex = candidate
            }
        case .up:
            guard row > 0 else {
                break
            }
            let target = (row - 1) * columns + col
            selectedIndex = min(target, items.count - 1)
        case .down:
            let nextRowStart = (row + 1) * columns
            guard nextRowStart < items.count else {
                break
            }
            let target = nextRowStart + col
            selectedIndex = min(target, items.count - 1)
        }

        syncViewModel(animated: true)
    }

    @discardableResult
    func appendDigit(_ digit: Int) -> Bool {
        guard (0...9).contains(digit) else {
            return false
        }

        typedIdentifier.append(String(digit))
        if typedIdentifier.count > maxIdentifierDigits() {
            typedIdentifier = String(typedIdentifier.suffix(maxIdentifierDigits()))
        }

        let matches = matchingIndices(for: typedIdentifier)
        if let first = matches.first {
            selectedIndex = first
        }

        syncViewModel(animated: true)

        guard matches.count == 1 else {
            return false
        }

        let activated = activateItem(at: matches[0])
        if activated {
            typedIdentifier = ""
            syncViewModel(animated: false)
        }
        return activated
    }

    func removeLastDigit() {
        guard !typedIdentifier.isEmpty else {
            return
        }

        typedIdentifier.removeLast()
        if let first = matchingIndices(for: typedIdentifier).first {
            selectedIndex = first
        }
        syncViewModel(animated: true)
    }

    func activateSelection() -> Bool {
        guard let targetIndex = resolvedSelectionIndex() else {
            return false
        }

        let activated = activateItem(at: targetIndex)
        if activated {
            typedIdentifier = ""
            syncViewModel(animated: false)
        }
        return activated
    }

    private func activateItem(at index: Int) -> Bool {
        guard items.indices.contains(index) else {
            return false
        }
        selectedIndex = index
        return items[index].app.activate()
    }

    private func resolvedSelectionIndex() -> Int? {
        if !typedIdentifier.isEmpty {
            let matches = matchingIndices(for: typedIdentifier)
            if matches.count == 1 {
                return matches[0]
            }

            if let exact = items.firstIndex(where: { $0.idText == typedIdentifier }) {
                return exact
            }

            return nil
        }

        guard items.indices.contains(selectedIndex) else {
            return nil
        }
        return selectedIndex
    }

    private func matchingIndices(for identifier: String) -> [Int] {
        guard !identifier.isEmpty else {
            return []
        }

        return items.indices.filter { items[$0].idText.hasPrefix(identifier) }
    }

    private func maxIdentifierDigits() -> Int {
        let maxID = items.last?.id ?? 0
        return max(1, String(maxID).count)
    }

    private func syncViewModel(animated: Bool) {
        let updateBlock = {
            self.viewModel.items = self.items.map {
                AppCellViewData(
                    id: $0.id,
                    name: $0.app.localizedName ?? "-",
                    icon: $0.app.icon
                )
            }
            self.viewModel.selectedIndex = self.selectedIndex
            self.viewModel.typedIdentifier = self.typedIdentifier
            self.viewModel.hintText = self.typedIdentifier.isEmpty
                ? L10n.tr("app_switcher.hint")
                : String(format: L10n.tr("app_switcher.input"), self.typedIdentifier)
        }

        if animated {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                updateBlock()
            }
        } else {
            updateBlock()
        }
    }

    private func reloadRunningApps() {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular && !app.isTerminated
            }
            .sorted { lhs, rhs in
                let left = lhs.localizedName ?? ""
                let right = rhs.localizedName ?? ""
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }

        items = runningApps.enumerated().map { index, app in
            AppItem(id: index + 1, app: app)
        }

        if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
        }
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window {
            return window
        }

        let overlay = NSWindow(
            contentRect: NSRect(origin: .zero, size: Config.windowSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = true
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.ignoresMouseEvents = true

        let swiftUIView = AppSwitcherOverlayView(viewModel: viewModel)
        let host = NSHostingView(rootView: swiftUIView)
        host.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView(frame: NSRect(origin: .zero, size: Config.windowSize))
        root.wantsLayer = true
        root.layer?.cornerRadius = Config.cornerRadius
        root.layer?.masksToBounds = true
        root.addSubview(host)

        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            host.topAnchor.constraint(equalTo: root.topAnchor),
            host.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        overlay.contentView = root
        window = overlay
        return overlay
    }

    private func targetFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: Config.windowSize)
        }

        return NSRect(
            x: screen.frame.midX - Config.windowSize.width / 2,
            y: screen.frame.midY - Config.windowSize.height / 2,
            width: Config.windowSize.width,
            height: Config.windowSize.height
        )
    }
}

private struct AppSwitcherOverlayView: View {
    @ObservedObject var viewModel: AppSwitcherOverlayController.ViewModel
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(minimum: 110, maximum: 160), spacing: 12), count: 6)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.black.opacity(0.80) : Color.white.opacity(0.86))
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.12), lineWidth: 1)
                )

            VStack(spacing: 14) {
                Text(L10n.tr("app_switcher.title"))
                    .font(.system(size: 34, weight: .semibold, design: .default))
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.appleNearBlack)
                    .kerning(-0.37)
                    .lineLimit(1)

                Text(viewModel.hintText)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.80) : Color.black.opacity(0.65))
                    .kerning(-0.22)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            AppSwitcherCellView(item: item, selected: index == viewModel.selectedIndex, colorScheme: colorScheme)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .padding(.horizontal, 2)
            }
            .padding(22)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 30, x: 3, y: 5)
    }
}

private struct AppSwitcherCellView: View {
    let item: AppSwitcherOverlayController.AppCellViewData
    let selected: Bool
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 5) {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 30, height: 30)
            }

            Text("\(item.id)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? Color.appleBlue : (colorScheme == .dark ? Color.white.opacity(0.70) : Color.black.opacity(0.65)))
                .kerning(-0.12)

            Text(item.name)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.appleNearBlack)
                .kerning(-0.12)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.appleBlue.opacity(0.20) : (colorScheme == .dark ? Color.darkSurface1 : Color.white))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? Color.appleBlue : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.12)), lineWidth: selected ? 1.2 : 1)
        )
        .scaleEffect(selected ? 1.02 : 1.0)
        .shadow(color: selected ? Color.black.opacity(0.22) : .clear, radius: 12, x: 3, y: 5)
        .animation(.easeOut(duration: 0.18), value: selected)
    }
}

private extension Color {
    static let appleBlue = Color(red: 0 / 255, green: 113 / 255, blue: 227 / 255)
    static let darkSurface1 = Color(red: 39 / 255, green: 39 / 255, blue: 41 / 255)
    static let appleNearBlack = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
}
