import XCTest
@testable import LocalGeofencePlugin

class LocalGeofenceTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    func testFillsTimePlaceholder() {
        // 2026-11-03T17:42:00Z
        let text = GeofenceLogic.fillTemplate("Work ended at {time}?", timestamp: 1_793_727_720_000, locale: Locale(identifier: "de_DE"), timeZone: utc)
        XCTAssertEqual(text, "Work ended at 17:42?")
    }

    func testLeavesTemplateWithoutPlaceholder() {
        XCTAssertEqual(GeofenceLogic.fillTemplate("Hello", timestamp: 0, locale: Locale(identifier: "de_DE"), timeZone: utc), "Hello")
    }

    func testSkipsRepeatedTransition() {
        XCTAssertTrue(GeofenceLogic.isNewTransition(last: nil, transition: "enter"))
        XCTAssertTrue(GeofenceLogic.isNewTransition(last: "enter", transition: "exit"))
        XCTAssertFalse(GeofenceLogic.isNewTransition(last: "exit", transition: "exit"))
    }

    func testKeepsNewestEvents() {
        XCTAssertEqual(GeofenceLogic.keepNewest([1, 2, 3, 4], max: 2), [3, 4])
        XCTAssertEqual(GeofenceLogic.keepNewest([1], max: 2), [1])
    }

    func testFilteredDirectionStillUpdatesLastTransition() {
        let store = GeofenceStore()
        store.removeRegion("exit-only")
        XCTAssertTrue(store.markTransition("exit-only", transition: "exit"))
        // An enter the region does not record must still be remembered ...
        XCTAssertTrue(store.markTransition("exit-only", transition: "enter"))
        // ... so the next exit counts as new.
        XCTAssertTrue(store.markTransition("exit-only", transition: "exit"))
        XCTAssertFalse(store.markTransition("exit-only", transition: "exit"))
        store.removeRegion("exit-only")
    }
}
