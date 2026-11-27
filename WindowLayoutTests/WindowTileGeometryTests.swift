import XCTest

final class WindowTileGeometryTests: XCTestCase {
    func test_maximizeAll_eachWindowFillsCurrentDisplayWithoutHistory() {
        let display = CGRect(x: -1920, y: 30, width: 1920, height: 1010)
        let frames = WindowTileGeometry.maximizedFrames(count: 5, in: display)
        XCTAssertEqual(frames.count, 5)
        XCTAssertTrue(frames.allSatisfy { $0 == display })
    }

    func test_maximizeAll_emptyWindowsOrInvalidBounds_produceNoFrames() {
        XCTAssertTrue(WindowTileGeometry.maximizedFrames(count: 0, in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        XCTAssertTrue(WindowTileGeometry.maximizedFrames(count: 5, in: .zero).isEmpty)
    }

    func test_threeWindows_focusedLeftHalfAndTwoStackedOnRight() {
        let bounds = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let expected = [
            CGRect(x: -1912, y: -292, width: 948, height: 1064),
            CGRect(x: -956, y: -292, width: 948, height: 528),
            CGRect(x: -956, y: 244, width: 948, height: 528)
        ]
        XCTAssertEqual(WindowTileGeometry.frames(count: 3, in: bounds), expected)
        XCTAssertEqual(
            WindowTileGeometry.frames(count: 3, in: bounds, rows: WindowTileGeometry.preferredRows(count: 3)),
            expected
        )
        // Minimum-size fallback remains available if the app rejects stacked windows.
        let fallback = WindowTileGeometry.frames(count: 3, in: bounds, rows: 2)
        XCTAssertEqual(fallback.count, 3)
        XCTAssertNotEqual(fallback, expected)
    }

    func test_targetDisplay_layoutUsesCurrentWindowDisplayOrigin() {
        let secondary = CGRect(x: 2560, y: -900, width: 1920, height: 1080)
        let layout = WindowTileGeometry.frames(count: 5, in: secondary)
        XCTAssertEqual(layout.count, 5)
        XCTAssertTrue(layout.allSatisfy { secondary.insetBy(dx: -0.01, dy: -0.01).contains($0) })
        XCTAssertEqual(layout[0].minX, secondary.minX + 8)
    }

    func test_fiveWindows_largerFirstRowWithoutEmptyCells() {
        let frames = WindowTileGeometry.frames(count: 5, in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(frames.count, 5)
        XCTAssertEqual(frames[0].minY, frames[1].minY)
        XCTAssertEqual(frames[2].minY, frames[4].minY)
        XCTAssertGreaterThan(frames[0].width, frames[2].width)
        XCTAssertEqual(frames[1].maxX, 1912, accuracy: 0.01)
        XCTAssertEqual(frames[4].maxX, 1912, accuracy: 0.01)
        XCTAssertEqual(frames[4].maxY, 1072, accuracy: 0.01)
    }

    func test_windowCounts_remainInsideScreenWithoutOverlap() {
        for bounds in [
            CGRect(x: -1920, y: -300, width: 1920, height: 1080),
            CGRect(x: 0, y: -1800, width: 1080, height: 1920),
            CGRect(x: 100, y: 45, width: 3440, height: 1395)
        ] {
            for count in 1...30 {
                let frames = WindowTileGeometry.frames(count: count, in: bounds)
                XCTAssertEqual(frames.count, count)
                for (index, frame) in frames.enumerated() {
                    XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(frame))
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                    for other in frames.dropFirst(index + 1) {
                        XCTAssertTrue(frame.intersection(other).isNull)
                    }
                }
            }
        }
    }

    func test_portraitScreen_transposesLandscapeLayout() {
        let landscape = WindowTileGeometry.frames(count: 5, in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let portrait = WindowTileGeometry.frames(count: 5, in: CGRect(x: 0, y: 0, width: 1080, height: 1920))
        for (left, right) in zip(landscape, portrait) {
            XCTAssertEqual(left.minX, right.minY)
            XCTAssertEqual(left.width, right.height)
        }
    }

    func test_invalidInput_returnsNoFrames() {
        XCTAssertTrue(WindowTileGeometry.frames(count: 0, in: .zero).isEmpty)
        XCTAssertTrue(WindowTileGeometry.frames(count: 2, in: .zero).isEmpty)
    }

    func test_minimumSizeRefusal_failsGeometryVerification() {
        let expected = CGRect(x: 8, y: 8, width: 600, height: 400)
        XCTAssertFalse(WindowTileGeometry.matches(CGRect(x: 8, y: 8, width: 800, height: 600), expected))
        XCTAssertTrue(WindowTileGeometry.matches(expected.offsetBy(dx: 1, dy: -1), expected))
    }

    func test_threeWindows_layoutCandidatesIncludeSideBySideFallback() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let candidates = WindowTileGeometry.layoutCandidates(count: 3, in: bounds)
        XCTAssertEqual(candidates.count, 4)
        XCTAssertEqual(candidates[0], WindowTileGeometry.frames(count: 3, in: bounds))
        XCTAssertEqual(candidates[1], WindowTileGeometry.gridFrames(count: 3, in: bounds, rows: 1))
        XCTAssertEqual(candidates[2], WindowTileGeometry.gridFrames(count: 3, in: bounds, rows: 2))
        XCTAssertEqual(candidates[3], WindowTileGeometry.gridFrames(count: 3, in: bounds, rows: 3))
    }

    func test_fits_allowsSmallerSnappedWindowWithinTile() {
        let expected = CGRect(x: 8, y: 8, width: 600, height: 400)
        XCTAssertTrue(WindowTileGeometry.fits(CGRect(x: 8, y: 8, width: 588, height: 386), in: expected))
        XCTAssertFalse(WindowTileGeometry.fits(CGRect(x: 8, y: 8, width: 620, height: 400), in: expected))
        XCTAssertFalse(WindowTileGeometry.fits(CGRect(x: 8, y: 8, width: 600, height: 420), in: expected))
    }

    func test_allFit_acceptsClampedNonOverlappingWindowsWithinBounds() {
        let bounds = CGRect(x: 0, y: 29, width: 1352, height: 812)
        let expected = [
            CGRect(x: 8, y: 37, width: 664, height: 796),
            CGRect(x: 680, y: 37, width: 664, height: 796)
        ]
        let actual = [
            CGRect(x: 8, y: 29, width: 664, height: 796),
            CGRect(x: 677, y: 29, width: 664, height: 796)
        ]
        XCTAssertTrue(WindowTileGeometry.allFit(actual, expected: expected, in: bounds))

        let halfHeight = [
            CGRect(x: 8, y: 37, width: 664, height: 796),
            CGRect(x: 680, y: 37, width: 664, height: 401)
        ]
        XCTAssertFalse(WindowTileGeometry.allFit(halfHeight, expected: expected, in: bounds))
    }
}
