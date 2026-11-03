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

    func startMonitoring(_ region: [String: Any]) throws {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            throw GeofenceError("Region monitoring is not available on this device")
        }
        guard let id = region["id"] as? String,
              let latitude = region["latitude"] as? Double,
              let longitude = region["longitude"] as? Double,
              let radius = region["radius"] as? Double else {
            throw GeofenceError("Invalid region")
        }
        let circular = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: min(radius, manager.maximumRegionMonitoringDistance),
            identifier: id
        )
        // Both directions are always monitored so the last transition stays known; handle() filters.
        circular.notifyOnEntry = true
        circular.notifyOnExit = true
        store.saveRegion(region)
        manager.startMonitoring(for: circular)
    }

    func stopMonitoring(_ id: String) {
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

    /// iOS shows the "always" upgrade prompt only once; later requests return without a callback.
    func requestAlways(_ done: @escaping () -> Void) {
        let status = manager.authorizationStatus
        guard status == .notDetermined || (status == .authorizedWhenInUse && !store.alwaysAsked) else { return done() }
        store.alwaysAsked = true
        waitForAuthorization(done)
        manager.requestAlwaysAuthorization()
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
        CAPLog.print("⚡️  LocalGeofence: " + "Monitoring failed for \(region?.identifier ?? "unknown region"): \(error.localizedDescription)")
    }

    private func handle(_ region: CLRegion, transition: String) {
        guard let stored = store.region(region.identifier) else { return }
        guard store.markTransition(region.identifier, transition: transition) else { return }
        guard stored[transition == "enter" ? "notifyOnEnter" : "notifyOnExit"] as? Bool ?? true else { return }

        let timestamp = Date().timeIntervalSince1970 * 1000
        let event: [String: Any] = [
            "id": UUID().uuidString,
            "regionId": region.identifier,
            "transition": transition,
            "timestamp": timestamp
        ]
        store.addEvent(event)
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

