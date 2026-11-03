import Foundation

/// Regions, recorded events and the last transition per region, persisted in UserDefaults.
/// Delegate callbacks (main thread) and plugin calls (bridge queue) share one lock, because each
/// write is a read-modify-write.
final class GeofenceStore {
    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private let regionsKey = "de.xnaff.capacitor.localgeofence.regions"
    /// Events and last transitions live in one value so a single write updates both.
    private let stateKey = "de.xnaff.capacitor.localgeofence.state"
    private let alwaysAskedKey = "de.xnaff.capacitor.localgeofence.alwaysAsked"

    func regions() -> [[String: Any]] {
        return Array(regionMap().values)
    }

    func region(_ id: String) -> [String: Any]? {
        return regionMap()[id]
    }

    func saveRegion(_ region: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        guard let id = region["id"] as? String else { return }
        var map = regionMap()
        map[id] = region
        defaults.set(map, forKey: regionsKey)
        // New geometry: the previous position relative to the old region says nothing about this one.
        var current = state()
        current.last.removeValue(forKey: id)
        save(current)
    }

    func removeRegion(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = regionMap()
        map.removeValue(forKey: id)
        defaults.set(map, forKey: regionsKey)
        var current = state()
        current.last.removeValue(forKey: id)
        save(current)
    }

    /// Remembers `transition` and, together with it, appends `event`. Returns false for a repeated
    /// transition. Called with a nil event for directions the region does not record, so a later
    /// opposite event is not lost.
    func record(_ regionId: String, transition: String, event: [String: Any]?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var current = state()
        guard GeofenceLogic.isNewTransition(last: current.last[regionId], transition: transition) else { return false }
        current.last[regionId] = transition
        if let event = event {
            current.events = GeofenceLogic.keepNewest(current.events + [event])
        }
        save(current)
        return true
    }

    func events() -> [[String: Any]] {
        return state().events
    }

    func clearEvents(_ ids: Set<String>?) {
        lock.lock()
        defer { lock.unlock() }
        var current = state()
        current.events = ids.map { ids in current.events.filter { !ids.contains($0["id"] as? String ?? "") } } ?? []
        save(current)
    }

    var alwaysAsked: Bool {
        get { defaults.bool(forKey: alwaysAskedKey) }
        set { defaults.set(newValue, forKey: alwaysAskedKey) }
    }

    private func regionMap() -> [String: [String: Any]] {
        return defaults.dictionary(forKey: regionsKey) as? [String: [String: Any]] ?? [:]
    }

    private func state() -> (events: [[String: Any]], last: [String: String]) {
        let value = defaults.dictionary(forKey: stateKey) ?? [:]
        return (value["events"] as? [[String: Any]] ?? [], value["last"] as? [String: String] ?? [:])
    }

    private func save(_ state: (events: [[String: Any]], last: [String: String])) {
        defaults.set(["events": state.events, "last": state.last], forKey: stateKey)
    }
}
