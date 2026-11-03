import Foundation

/// Regions, recorded events and the last transition per region, persisted in UserDefaults.
final class GeofenceStore {
    private let defaults = UserDefaults.standard
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
        guard let id = region["id"] as? String else { return }
        var map = regionMap()
        map[id] = region
        defaults.set(map, forKey: regionsKey)
    }

    func removeRegion(_ id: String) {
        var map = regionMap()
        map.removeValue(forKey: id)
        defaults.set(map, forKey: regionsKey)
        var last = lastMap()
        last.removeValue(forKey: id)
        defaults.set(last, forKey: lastKey)
    }

    func lastTransition(_ regionId: String) -> String? {
        return lastMap()[regionId]
    }

    func events() -> [[String: Any]] {
        return defaults.array(forKey: eventsKey) as? [[String: Any]] ?? []
    }

    func addEvent(_ event: [String: Any]) {
        defaults.set(GeofenceLogic.keepNewest(events() + [event]), forKey: eventsKey)
        if let regionId = event["regionId"] as? String, let transition = event["transition"] as? String {
            var last = lastMap()
            last[regionId] = transition
            defaults.set(last, forKey: lastKey)
        }
    }

    func clearEvents(_ ids: Set<String>?) {
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
