import CoreGraphics

nonisolated enum WindowTileGeometry {
    static func maximizedFrames(count: Int, in bounds: CGRect) -> [CGRect] {
        guard count > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        return Array(repeating: bounds, count: count)
    }

    static func preferredRows(count: Int) -> Int {
        if count <= 3 { return 1 }
        if count <= 6 { return 2 }
        return Int(ceil(sqrt(Double(count))))
    }
    static func frames(count: Int, in bounds: CGRect, rows requestedRows: Int? = nil) -> [CGRect] {
        guard count > 0, bounds.width > 32, bounds.height > 32 else { return [] }
        if count == 1 { return [bounds] }
        let gap: CGFloat = 8
        // The tiler passes preferredRows explicitly; reserve its first attempt for
        // a large focused window on the left and two stacked windows on the right.
        if count == 3, requestedRows == nil || requestedRows == preferredRows(count: count) {
            let columnWidth = (bounds.width - gap * 3) / 2
            let fullHeight = bounds.height - gap * 2
            let halfHeight = (fullHeight - gap) / 2
            let leftX = bounds.minX + gap
            let rightX = leftX + columnWidth + gap
            let topY = bounds.minY + gap
            return [
                CGRect(x: leftX, y: topY, width: columnWidth, height: fullHeight),
                CGRect(x: rightX, y: topY, width: columnWidth, height: halfHeight),
                CGRect(x: rightX, y: topY + halfHeight + gap, width: columnWidth, height: halfHeight)
            ]
        }
        return gridFrames(count: count, in: bounds, rows: requestedRows)
    }

    static func gridFrames(count: Int, in bounds: CGRect, rows requestedRows: Int? = nil) -> [CGRect] {
        guard count > 0, bounds.width > 32, bounds.height > 32 else { return [] }
        if count == 1 { return [bounds] }
        let gap: CGFloat = 8
        let portrait = bounds.height > bounds.width
        let width = portrait ? bounds.height : bounds.width
        let height = portrait ? bounds.width : bounds.height
        let rows = min(count, max(1, requestedRows ?? preferredRows(count: count)))
        let rowHeight = (height - gap * CGFloat(rows + 1)) / CGFloat(rows)
        guard rowHeight > 0 else { return [] }
        var result: [CGRect] = []
        for row in 0..<rows {
            // Fewer cells first: the focused window gets the larger first cell.
            let columns = count / rows + (row >= rows - count % rows ? 1 : 0)
            let cellWidth = (width - gap * CGFloat(columns + 1)) / CGFloat(columns)
            guard cellWidth > 0 else { return [] }
            for column in 0..<columns {
                let x = gap + CGFloat(column) * (cellWidth + gap)
                let y = gap + CGFloat(row) * (rowHeight + gap)
                result.append(CGRect(
                    x: bounds.minX + (portrait ? y : x),
                    y: bounds.minY + (portrait ? x : y),
                    width: portrait ? rowHeight : cellWidth,
                    height: portrait ? cellWidth : rowHeight
                ))
            }
        }
        return result
    }

    static func layoutCandidates(count: Int, in bounds: CGRect) -> [[CGRect]] {
        guard count > 0 else { return [] }
        let defaultRows = preferredRows(count: count)
        var candidates: [[CGRect]] = []
        let primary = frames(count: count, in: bounds, rows: defaultRows)
        if primary.count == count { candidates.append(primary) }
        if count == 3 {
            let oneRow = gridFrames(count: 3, in: bounds, rows: 1)
            if oneRow.count == count { candidates.append(oneRow) }
        }
        for rows in 1...count where rows != defaultRows {
            let fallback = gridFrames(count: count, in: bounds, rows: rows)
            if fallback.count == count { candidates.append(fallback) }
        }
        return candidates
    }

    static func matches(_ actual: CGRect, _ expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) <= 3 && abs(actual.minY - expected.minY) <= 3
            && abs(actual.width - expected.width) <= 3 && abs(actual.height - expected.height) <= 3
    }

    /// Allows windows that snap to smaller dimensions (e.g. character-grid terminals)
    /// or clamp slightly within `bounds` as long as they stay near their assigned tile
    /// without exceeding its size or overlapping neighboring windows.
    static func fits(_ actual: CGRect, in expected: CGRect, bounds: CGRect? = nil) -> Bool {
        guard actual.width > 0, actual.height > 0,
              actual.width <= expected.width + 3,
              actual.height <= expected.height + 3,
              actual.width >= expected.width - 24,
              actual.height >= expected.height - 24,
              abs(actual.minX - expected.minX) <= 24,
              abs(actual.minY - expected.minY) <= 24 else {
            return false
        }
        if let bounds {
            return actual.minX >= bounds.minX - 3 && actual.minY >= bounds.minY - 3
                && actual.maxX <= bounds.maxX + 3 && actual.maxY <= bounds.maxY + 3
        }
        return true
    }

    static func allFit(_ actuals: [CGRect], expected: [CGRect], in bounds: CGRect) -> Bool {
        guard actuals.count == expected.count else { return false }
        for (actual, exp) in zip(actuals, expected) {
            if !fits(actual, in: exp, bounds: bounds) { return false }
        }
        for i in actuals.indices {
            for j in (i + 1)..<actuals.count {
                let overlap = actuals[i].intersection(actuals[j])
                if !overlap.isNull && overlap.width > 3 && overlap.height > 3 {
                    return false
                }
            }
        }
        return true
    }
}
