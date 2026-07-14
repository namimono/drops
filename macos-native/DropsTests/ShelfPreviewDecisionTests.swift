import XCTest
@testable import Drops

final class ShelfPreviewDecisionTests: XCTestCase {
    func testMixedSelectionPrefersLocalQuickLook() {
        let file = ShelfItem(
            identityKey: "/tmp/a.txt",
            displayName: "a.txt",
            kind: .text,
            fileURL: URL(fileURLWithPath: "/tmp/a.txt")
        )
        let link = ShelfItem(
            identityKey: "https://example.com",
            displayName: "https://example.com",
            kind: .link,
            linkURL: URL(string: "https://example.com")!
        )

        let decision = ShelfPreviewDecision.decide(for: [link, file])
        guard case .quickLookLocalFiles(let urls) = decision else {
            return XCTFail("Expected local Quick Look, got \(decision)")
        }
        XCTAssertEqual(urls, [URL(fileURLWithPath: "/tmp/a.txt")])
    }

    func testLinkOnlySelectionOpensFirstLink() {
        let first = ShelfItem(
            identityKey: "https://a.example",
            displayName: "https://a.example",
            kind: .link,
            linkURL: URL(string: "https://a.example")!
        )
        let second = ShelfItem(
            identityKey: "https://b.example",
            displayName: "https://b.example",
            kind: .link,
            linkURL: URL(string: "https://b.example")!
        )

        let decision = ShelfPreviewDecision.decide(for: [first, second])
        guard case .openFirstLink(let url) = decision else {
            return XCTFail("Expected open first link, got \(decision)")
        }
        XCTAssertEqual(url.absoluteString, "https://a.example")
    }

    func testEmptySelectionIsNone() {
        XCTAssertEqual(ShelfPreviewDecision.decide(for: []), .none)
    }
}
