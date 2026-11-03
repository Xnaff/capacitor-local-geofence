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
        XCTAssertTrue(store.record("exit-only", transition: "exit", event: nil))
        // An enter the region does not record must still be remembered ...
        XCTAssertTrue(store.record("exit-only", transition: "enter", event: nil))
        // ... so the next exit counts as new.
        XCTAssertTrue(store.record("exit-only", transition: "exit", event: nil))
        XCTAssertFalse(store.record("exit-only", transition: "exit", event: nil))
        store.removeRegion("exit-only")
    }

    func testRecordStoresEventWithTransitionAndReplacementResetsIt() {
        let store = GeofenceStore()
        store.clearEvents(nil)
        let event: [String: Any] = ["id": "e1", "regionId": "office", "transition": "exit", "timestamp": 1.0]
        XCTAssertTrue(store.record("office", transition: "exit", event: event))
        XCTAssertEqual(store.events().compactMap { $0["id"] as? String }, ["e1"])
        // Replacing the region forgets the old position, so the same direction counts again.
        store.saveRegion(["id": "office"])
        XCTAssertTrue(store.record("office", transition: "exit", event: nil))
        store.removeRegion("office")
        store.clearEvents(nil)
        XCTAssertTrue(store.events().isEmpty)
    }
}
