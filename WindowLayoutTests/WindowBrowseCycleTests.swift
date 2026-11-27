import XCTest

final class WindowBrowseCycleTests: XCTestCase {
    private let originals = (0..<5).map {
        CGRect(x: $0 * 200, y: 40, width: 190, height: 400)
    }

    func test_fiveWindows_cycleInSnapshotOrderAndWrap() throws {
        var cycle = WindowBrowseCycle(originalFrames: originals)
        let available = Set(originals.indices)
        var visited: [Int] = []
        for _ in 0..<7 {
            for index in cycle.pendingRestore { cycle.didRestore(at: index) }
            let next = try XCTUnwrap(cycle.nextIndex(available: available))
            cycle.beginChange(at: next)
            cycle.didMaximize(at: next)
            visited.append(next)
            XCTAssertEqual(cycle.pendingRestore, [next])
        }
        XCTAssertEqual(visited, [0, 1, 2, 3, 4, 0, 1])
        XCTAssertEqual(cycle.originalFrames, originals)
    }

    func test_unavailableWindows_skippedWithoutReordering() {
        var cycle = WindowBrowseCycle(originalFrames: originals)
        cycle.didMaximize(at: 1)
        XCTAssertEqual(cycle.nextIndex(available: [0, 3, 4]), 3)
        cycle.didMaximize(at: 4)
        XCTAssertEqual(cycle.nextIndex(available: [0, 3]), 0)
    }

    func test_failedMaximize_keepsRestorationWithoutAdvancingCursor() {
        var cycle = WindowBrowseCycle(originalFrames: originals)
        cycle.didMaximize(at: 0)
        cycle.didRestore(at: 0)
        cycle.beginChange(at: 1)
        XCTAssertEqual(cycle.lastIndex, 0)
        XCTAssertEqual(cycle.pendingRestore, [1])
        XCTAssertEqual(cycle.originalFrames[1], originals[1])
        cycle.didRestore(at: 1)
        XCTAssertTrue(cycle.pendingRestore.isEmpty)
        XCTAssertEqual(cycle.nextIndex(available: Set(originals.indices)), 1)
    }

    func test_pageDown_restoresOnlyModifiedWindow() {
        var cycle = WindowBrowseCycle(originalFrames: originals)
        cycle.didMaximize(at: 3)
        let restoration = cycle.pendingRestore.map { cycle.originalFrames[$0] }
        XCTAssertEqual(restoration, [originals[3]])
        cycle.didRestore(at: 3)
        XCTAssertTrue(cycle.pendingRestore.isEmpty)
    }

    func test_noEligibleWindows_returnsNoTarget() {
        let cycle = WindowBrowseCycle(originalFrames: originals)
        XCTAssertNil(cycle.nextIndex(available: []))
        XCTAssertNil(WindowBrowseCycle(originalFrames: []).nextIndex(available: [0]))
    }

    func test_singleWindow_wrapsWithoutLosingOriginalSize() {
        var cycle = WindowBrowseCycle(originalFrames: [originals[0]])
        cycle.didMaximize(at: 0)
        XCTAssertEqual(cycle.nextIndex(available: [0]), 0)
        XCTAssertEqual(cycle.originalFrames, [originals[0]])
    }
}
