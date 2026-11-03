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
    }

    // MARK: Regions

    var authorizationStatus: CLAuthorizationStatus {
        return manager.authorizationStatus
    }

    var hasFullAccuracy: Bool {
        return manager.accuracyAuthorization == .fullAccuracy
    }

    /// Pending addRegion completions per region id, finished by didStartMonitoringFor / monitoringDidFailFor.
    private var pendingStarts: [String: (Error?) -> Void] = [:]

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
        let circular = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: id
        )
        // Both directions are always monitored so the last transition stays known; handle() filters.
        circular.notifyOnEntry = true
        circular.notifyOnExit = true
        pendingStarts[id] = done
        store.saveRegion(region)
        manager.startMonitoring(for: circular)
    }

    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        pendingStarts.removeValue(forKey: region.identifier)?(nil)
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

    /// iOS shows the "always" upgrade prompt only once and ignores the request after "Allow Once";
    /// both return without any callback, so a request that shows no prompt resolves after a short delay.
    func requestAlways(_ done: @escaping () -> Void) {
        let status = manager.authorizationStatus
        guard status == .notDetermined || (status == .authorizedWhenInUse && !store.alwaysAsked) else { return done() }
        var promptShown = false
        let resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { _ in promptShown = true }
        waitForAuthorization { [weak self] in
            NotificationCenter.default.removeObserver(resignObserver)
            // Only an observed decision ends retries; an interruption (call, app switch) leaves it askable.
            if let self = self, self.manager.authorizationStatus != status { self.store.alwaysAsked = true }
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
            guard let done = pendingStarts.removeValue(forKey: id) else { continue }
            // iOS already dropped any previous region with this id, so nothing is monitored under it now.
            store.removeRegion(id)
            done(error)
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

