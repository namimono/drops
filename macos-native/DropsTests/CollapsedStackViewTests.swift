import AppKit
import XCTest
@testable import Drops

@MainActor
final class CollapsedStackViewTests: XCTestCase {
    func testCollapsedPresentationShowsStackHidesScrollList() {
        let shelf = Shelf(source: .menu, lifecycle: .persistent, presentation: .collapsed)
        let drafts = (0..<4).map {
            ShelfItemDraft.file(
                url: URL(fileURLWithPath: "/tmp/stack-\($0).txt"),
                isDirectory: false
            )
        }
        _ = shelf.insertItems(drafts)

        let controller = ShelfContentViewController()
        _ = controller.view
        controller.apply(shelf: shelf, displayMode: .list)

        let stack = controller.view.subviews.first { $0 is CollapsedStackView }
        let scroll = controller.view.subviews.first { $0 is NSScrollView }
        XCTAssertNotNil(stack)
        XCTAssertEqual(stack?.isHidden, false)
        XCTAssertEqual(scroll?.isHidden, true)
    }

    func testExpandedPresentationHidesStackShowsScroll() {
        let shelf = Shelf(source: .menu, lifecycle: .persistent, presentation: .expanded)
        _ = shelf.insertItems([
            .file(url: URL(fileURLWithPath: "/tmp/expanded.txt"), isDirectory: false)
        ])

        let controller = ShelfContentViewController()
        _ = controller.view
        controller.apply(shelf: shelf, displayMode: .grid)

        let stack = controller.view.subviews.first { $0 is CollapsedStackView }
        let scroll = controller.view.subviews.first { $0 is NSScrollView }
        XCTAssertEqual(stack?.isHidden, true)
        XCTAssertEqual(scroll?.isHidden, false)
    }
}
