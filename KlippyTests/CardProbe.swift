import XCTest
@testable import Klippy

/// Card schemes the classifier must recognise.
///
/// Verve is here because it was missing: every international scheme was covered
/// and the Nigerian one, the card most likely to be in the pocket of the person
/// who wrote this app, was filed as "Numbers". Excluding Payment Cards in
/// Settings would not have kept a Verve number out of the history either.
///
/// Every number below is Luhn valid, because the rule checks Luhn before it
/// checks anything else and a test number that fails it proves nothing.
final class PaymentCardSchemeTests: XCTestCase {

    private let classifier = ContentClassifier()

    private func assertCard(_ value: String, _ label: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(classifier.classify(value), .paymentCard,
                       "\(label) should be a payment card", file: file, line: line)
    }

    func testInternationalSchemes() {
        assertCard("4242424242424242", "Visa")
        assertCard("5555555555554444", "Mastercard")
        assertCard("2223003122003222", "Mastercard 2-series")
        assertCard("378282246310005", "Amex")
        assertCard("6011111111111117", "Discover")
    }

    func testVerve() {
        assertCard("5060990000000008", "Verve 506099, 16 digits")
        assertCard("5061980000000000001", "Verve 506198, 19 digits")
        assertCard("5078650000000008", "Verve 507865, 16 digits")
        assertCard("650002000000000000", "Verve 650002, 18 digits")
    }

    /// However it was copied off a screen or out of a form.
    func testTheUsualFormats() {
        assertCard("4242 4242 4242 4242", "spaced")
        assertCard("4242-4242-4242-4242", "dashed")
        assertCard("4242424242424242\n", "with a trailing newline")
    }

    /// A number that merely looks card shaped must not be one.
    func testNotEveryLongNumberIsACard() {
        XCTAssertNotEqual(classifier.classify("1234567812345678"), .paymentCard,
                          "fails Luhn and has no known prefix")
        XCTAssertNotEqual(classifier.classify("4242424242424243"), .paymentCard,
                          "right prefix, fails Luhn")
    }
}

/// What a fresh install actually does.
///
/// A category chip only appears once that category exists in the history, so on
/// a clean machine the panel starts with nothing but "All" and has to grow as
/// you copy. Copying a number has to make "Numbers" appear, or the app looks
/// broken to every new user while looking perfect on a library that already
/// contains everything.
final class FreshInstallTests: XCTestCase {

    func testCopyingANumberWouldRevealTheNumbersChip() {
        let classifier = ContentClassifier()
        XCTAssertEqual(classifier.classify("48591"), .number)
    }

    func testCopyingAVerveCardWouldRevealThePaymentCardsChip() {
        let classifier = ContentClassifier()
        XCTAssertEqual(classifier.classify("5060990000000008"), .paymentCard)
    }

    /// The chips are driven by this set, and an empty one means only "All".
    func testTheChipSetStartsEmptyAndGrows() {
        var present: Set<ContentCategory> = []
        XCTAssertTrue(present.isEmpty, "a clean install shows only All")

        let classifier = ContentClassifier()
        present.insert(classifier.classify("48591"))
        present.insert(classifier.classify("5060990000000008"))
        present.insert(classifier.classify("https://klippy.app"))

        XCTAssertTrue(present.contains(.number))
        XCTAssertTrue(present.contains(.paymentCard))
        XCTAssertTrue(present.contains(.url))
    }
}
