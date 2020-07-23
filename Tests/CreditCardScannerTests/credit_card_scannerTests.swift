import XCTest
@testable import credit_card_scanner

final class credit_card_scannerTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(credit_card_scanner().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
