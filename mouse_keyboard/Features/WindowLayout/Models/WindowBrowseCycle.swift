import CoreGraphics

/// A fixed snapshot for one application's PageUp browsing session.
/// Original frames are immutable, so wrapping around never records a maximized frame.
nonisolated struct WindowBrowseCycle {
    let originalFrames: [CGRect]
    private(set) var lastIndex: Int?
    private(set) var pendingRestore: Set<Int> = []

    func nextIndex(available: Set<Int>) -> Int? {
        guard !originalFrames.isEmpty else { return nil }
        let start = lastIndex.map { ($0 + 1) % originalFrames.count } ?? 0
        for offset in originalFrames.indices {
            let index = (start + offset) % originalFrames.count
            if available.contains(index) { return index }
        }
        return nil
    }

    mutating func beginChange(at index: Int) {
        precondition(originalFrames.indices.contains(index))
        pendingRestore.insert(index)
    }

    mutating func didRestore(at index: Int) {
        pendingRestore.remove(index)
    }

    mutating func didMaximize(at index: Int) {
        precondition(originalFrames.indices.contains(index))
        pendingRestore.insert(index)
        lastIndex = index
    }
}
