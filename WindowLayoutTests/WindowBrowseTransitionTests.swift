import XCTest

final class WindowBrowseTransitionTests: XCTestCase {
    func test_transitionEndpoints_preserveExactWindowGeometry() {
        let start = CGRect(x: -1500, y: 40, width: 800, height: 500)
        let end = CGRect(x: 0, y: 30, width: 1920, height: 1050)
        XCTAssertEqual(WindowBrowseTransition.frame(from: start, to: end, progress: 0), start)
        XCTAssertEqual(WindowBrowseTransition.frame(from: start, to: end, progress: 1), end)
        XCTAssertEqual(WindowBrowseTransition.frame(from: start, to: end, progress: 5), end)
        XCTAssertEqual(WindowBrowseTransition.frame(from: start, to: end, progress: -1), start)
    }

    func test_maximizeTransition_progressesWithoutOvershoot() {
        let start = CGRect(x: 300, y: 250, width: 600, height: 400)
        let end = CGRect(x: -1920, y: -50, width: 1920, height: 1080)
        var previous = start
        for step in 1...100 {
            let frame = WindowBrowseTransition.frame(from: start, to: end, progress: Double(step) / 100)
            XCTAssertLessThanOrEqual(frame.minX, previous.minX)
            XCTAssertGreaterThanOrEqual(frame.minX, end.minX)
            XCTAssertGreaterThanOrEqual(frame.width, previous.width)
            XCTAssertLessThanOrEqual(frame.width, end.width)
            previous = frame
        }
    }

    func test_restoreTransition_finishesAtOriginalTiledSize() {
        let original = CGRect(x: 8, y: 8, width: 948, height: 1064)
        let maximized = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let midpoint = WindowBrowseTransition.frame(from: maximized, to: original, progress: 0.5)
        XCTAssertGreaterThan(midpoint.width, original.width)
        XCTAssertLessThan(midpoint.width, maximized.width)
        XCTAssertEqual(WindowBrowseTransition.frame(from: maximized, to: original, progress: 1), original)
    }
}
