import Capacitor
import CoreLocation
import Foundation
import UIKit
import UserNotifications

/// Owns the region-monitoring location manager. iOS relaunches a terminated app in the background
/// for region events and delivers them to the first location manager whose delegate is set, which
/// happens when Capacitor loads the plugin. Apps may also call `LocalGeofence.shared` early in
/// `application(_:didFinishLaunchingWithOptions:)`.
@objc public final class LocalGeofence: NSObject, CLLocationManagerDelegate {
    @objc public static let shared = LocalGeofence()

    let store = GeofenceStore()
    var onTransition: (([String: Any]) -> Void)?

    private let manager = CLLocationManager()
    private var authorizationWaiters: [() -> Void] = []
    private var activeObserver: NSObjectProtocol?

    override private init() {
        super.init()
        manager.delegate = self
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reconcile() }
        DispatchQueue.main.async { self.reconcile() }
    }

    /// Re-monitors stored regions iOS is not monitoring (e.g. after a failed rollback).
    func reconcile() {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else { return }
        let monitored = Set(manager.monitoredRegions.map { $0.identifier })
        for region in store.regions() {
            guard let id = region["id"] as? String, !monitored.contains(id), pendingStarts[id] == nil,
                  let latitude = region["latitude"] as? Double,
                  let longitude = region["longitude"] as? Double,
                  let radius = region["radius"] as? Double else { continue }
            pendingStarts[id] = PendingStart(previous: region, previousLast: store.lastTransition(id), isRollback: true, done: { _ in })
            manager.startMonitoring(for: circularRegion(id: id, latitude: latitude, longitude: longitude, radius: radius))
        }
    }

    // MARK: Regions

    var authorizationStatus: CLAuthorizationStatus {
        return manager.authorizationStatus
    }

    var hasFullAccuracy: Bool {
        return manager.accuracyAuthorization == .fullAccuracy
    }

    /// Pending addRegion completions per region id, finished by didStartMonitoringFor / monitoringDidFailFor.
    private struct PendingStart {
        let previous: [String: Any]?
        let previousLast: String?
        /// True for the re-registration of `previous` after a failed replacement.
        let isRollback: Bool
        let done: (Error?) -> Void
    }

    private var pendingStarts: [String: PendingStart] = [:]

    func startMonitoring(_ region: [String: Any], done: @escaping (Error?) -> Void) throws {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            throw GeofenceError("Region monitoring is not available on this device")
        }
        guard let id = region["id"] as? String,
              let latitude = region["latitude"] as? Double,
              let longitude = region["longitude"] as? Double,
              let radius = region["radius"] as? Double else {
            throw GeofenceError("Invalid region")
        }
        guard radius <= manager.maximumRegionMonitoringDistance else {
            throw GeofenceError("radius must not exceed \(manager.maximumRegionMonitoringDistance) m on this device")
        }
        // Core Location cannot cancel a start, so its callback would answer a newer call for the same id.
        guard pendingStarts[id] == nil else {
            throw GeofenceError("addRegion for \(id) is still pending")
        }
        pendingStarts[id] = PendingStart(previous: store.region(id), previousLast: store.lastTransition(id), isRollback: false, done: done)
        store.saveRegion(region)
        manager.startMonitoring(for: circularRegion(id: id, latitude: latitude, longitude: longitude, radius: radius))
    }

    private func circularRegion(id: String, latitude: Double, longitude: Double, radius: Double) -> CLCircularRegion {
        let circular = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: id
        )
        // Both directions are always monitored so the last transition stays known; handle() filters.
        circular.notifyOnEntry = true
        circular.notifyOnExit = true
        return circular
    }

    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        pendingStarts.removeValue(forKey: region.identifier)?.done(nil)
    }

    func stopMonitoring(_ id: String) throws {
        guard pendingStarts[id] == nil else {
            throw GeofenceError("addRegion for \(id) is still pending")
        }
        for region in manager.monitoredRegions where region.identifier == id {
            manager.stopMonitoring(for: region)
        }
        store.removeRegion(id)
    }

    // MARK: Authorization

    func requestWhenInUse(_ done: @escaping () -> Void) {
        guard manager.authorizationStatus == .notDetermined else { return done() }
        waitForAuthorization(done)
        manager.requestWhenInUseAuthorization()
    }

    /// iOS itself limits the "always" upgrade prompt and ignores the request after "Allow Once" or a
    /// previous answer, without any callback; a request that shows no prompt resolves after a short delay.
    func requestAlways(_ done: @escaping () -> Void) {
        let status = manager.authorizationStatus
        guard status == .notDetermined || status == .authorizedWhenInUse else { return done() }
        var promptShown = false
        let resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { _ in promptShown = true }
        waitForAuthorization {
            NotificationCenter.default.removeObserver(resignObserver)
            done()
        }
        manager.requestAlwaysAuthorization()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if !promptShown { self?.flushAuthorizationWaiters() }
        }
    }

    /// Resolves on the authorization callback, or when the app becomes active again after the
    /// prompt, because keeping the current choice does not fire a callback.
    private func waitForAuthorization(_ done: @escaping () -> Void) {
        authorizationWaiters.append(done)
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.flushAuthorizationWaiters() }
        }
    }

    private func flushAuthorizationWaiters() {
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        if let observer = activeObserver {
            NotificationCenter.default.removeObserver(observer)
            activeObserver = nil
        }
        waiters.forEach { $0() }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined {
            flushAuthorizationWaiters()
        }
    }

    // MARK: Transitions

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handle(region, transition: "enter")
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        handle(region, transition: "exit")
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // A failure without a region is service-wide; it answers every pending start.
        let ids = region.map { [$0.identifier] } ?? Array(pendingStarts.keys)
        for id in ids {
            guard let pending = pendingStarts.removeValue(forKey: id) else { continue }
            if pending.isRollback {
                // The previous configuration stays stored; reconcile() retries it on the next activation.
                pending.done(error)
                continue
            }
            // iOS already dropped any previous region with this id; monitor the previous one again.
            store.restore(id, region: pending.previous, last: pending.previousLast)
            if let previous = pending.previous,
               let latitude = previous["latitude"] as? Double,
               let longitude = previous["longitude"] as? Double,
               let radius = previous["radius"] as? Double {
                // Keep the id reserved until the rollback's own callback, so it cannot answer a newer call.
                pendingStarts[id] = PendingStart(previous: previous, previousLast: pending.previousLast, isRollback: true, done: { _ in })
                manager.startMonitoring(for: circularRegion(id: id, latitude: latitude, longitude: longitude, radius: radius))
            }
            pending.done(error)
        }
        CAPLog.print("⚡️  LocalGeofence: " + "Monitoring failed for \(region?.identifier ?? "unknown region"): \(error.localizedDescription)")
    }

    private func handle(_ region: CLRegion, transition: String) {
        guard let stored = store.region(region.identifier) else { return }
        let recorded = stored[transition == "enter" ? "notifyOnEnter" : "notifyOnExit"] as? Bool ?? true
        let timestamp = Date().timeIntervalSince1970 * 1000
        let event: [String: Any] = [
            "id": UUID().uuidString,
            "regionId": region.identifier,
            "transition": transition,
            "timestamp": timestamp
        ]
        guard store.record(region.identifier, transition: transition, event: recorded ? event : nil), recorded else { return }
        if let notification = stored[transition == "enter" ? "enterNotification" : "exitNotification"] as? [String: Any] {
            showNotification(regionId: region.identifier, notification: notification, timestamp: timestamp)
        }
        onTransition?(event)
    }

    private func showNotification(regionId: String, notification: [String: Any], timestamp: Double) {
        let content = UNMutableNotificationContent()
        content.title = GeofenceLogic.fillTemplate(notification["title"] as? String ?? "", timestamp: timestamp)
        content.body = GeofenceLogic.fillTemplate(notification["body"] as? String ?? "", timestamp: timestamp)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "local-geofence-\(regionId)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

struct GeofenceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

