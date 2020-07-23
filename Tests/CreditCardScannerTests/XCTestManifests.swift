import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(credit_card_scannerTests.allTests),
    ]
}
#endif
