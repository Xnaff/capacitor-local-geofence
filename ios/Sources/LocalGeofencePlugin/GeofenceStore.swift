import Foundation

/// Regions, recorded events and the last transition per region, persisted in UserDefaults.
/// Delegate callbacks (main thread) and plugin calls (bridge queue) share one lock, because each
/// write is a read-modify-write.
final class GeofenceStore {
    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private let regionsKey = "de.xnaff.capacitor.localgeofence.regions"
    private let eventsKey = "de.xnaff.capacitor.localgeofence.events"
    private let lastKey = "de.xnaff.capacitor.localgeofence.last"
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
        var last = lastMap()
        last.removeValue(forKey: id)
        defaults.set(last, forKey: lastKey)
    }

    func removeRegion(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        var map = regionMap()
        map.removeValue(forKey: id)
        defaults.set(map, forKey: regionsKey)
        var last = lastMap()
        last.removeValue(forKey: id)
        defaults.set(last, forKey: lastKey)
    }

    /// Remembers `transition` and, together with it, appends `event`. Returns false for a repeated
    /// transition. Called with a nil event for directions the region does not record, so a later
    /// opposite event is not lost.
    func record(_ regionId: String, transition: String, event: [String: Any]?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var last = lastMap()
        guard GeofenceLogic.isNewTransition(last: last[regionId], transition: transition) else { return false }
        last[regionId] = transition
        defaults.set(last, forKey: lastKey)
        if let event = event {
            defaults.set(GeofenceLogic.keepNewest(events() + [event]), forKey: eventsKey)
        }
        return true
    }

    func events() -> [[String: Any]] {
        return defaults.array(forKey: eventsKey) as? [[String: Any]] ?? []
    }

    func clearEvents(_ ids: Set<String>?) {
        lock.lock()
        defer { lock.unlock() }
        let kept = ids.map { ids in events().filter { !ids.contains($0["id"] as? String ?? "") } } ?? []
        defaults.set(kept, forKey: eventsKey)
    }

    var alwaysAsked: Bool {
        get { defaults.bool(forKey: alwaysAskedKey) }
        set { defaults.set(newValue, forKey: alwaysAskedKey) }
    }

    private func regionMap() -> [String: [String: Any]] {
        return defaults.dictionary(forKey: regionsKey) as? [String: [String: Any]] ?? [:]
    }

    private func lastMap() -> [String: String] {
        return defaults.dictionary(forKey: lastKey) as? [String: String] ?? [:]
    }
}
