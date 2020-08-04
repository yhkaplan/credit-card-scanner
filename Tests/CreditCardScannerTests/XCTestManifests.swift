import XCTest

#if !canImport(ObjectiveC)
    public func allTests() -> [XCTestCaseEntry] {
        [
            testCase(credit_card_scannerTests.allTests),
        ]
    }
#endif
