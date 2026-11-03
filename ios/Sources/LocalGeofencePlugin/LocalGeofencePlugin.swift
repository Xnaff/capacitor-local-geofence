import Capacitor
import CoreLocation
import Foundation
import UserNotifications

/**
 * Capacitor bridge for `LocalGeofence`. See https://capacitorjs.com/docs/plugins/ios
 */
@objc(LocalGeofencePlugin)
public class LocalGeofencePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LocalGeofencePlugin"
    public let jsName = "LocalGeofence"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addRegion", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeRegion", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getRegions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getEvents", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearEvents", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = LocalGeofence.shared

    override public func load() {
        implementation.onTransition = { [weak self] event in
            self?.notifyListeners("transition", data: event)
        }
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        permissionStatus { call.resolve($0) }
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        let requested = call.getArray("permissions", String.self) ?? ["location", "notifications"]
        if let unknown = requested.first(where: { !["location", "backgroundLocation", "notifications"].contains($0) }) {
            return call.reject("Unknown permission: \(unknown)")
        }
        DispatchQueue.main.async {
            self.request(requested) { self.permissionStatus { call.resolve($0) } }
        }
    }

    private func request(_ remaining: [String], done: @escaping () -> Void) {
        guard let next = remaining.first else { return done() }
        let rest = Array(remaining.dropFirst())
        let continueWithRest = { DispatchQueue.main.async { self.request(rest, done: done) } }
        switch next {
        case "location":
            implementation.requestWhenInUse(continueWithRest)
        case "backgroundLocation":
            implementation.requestAlways(continueWithRest)
        case "notifications":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in continueWithRest() }
        default:
            continueWithRest()
        }
    }

    @objc func addRegion(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), !id.isEmpty else { return call.reject("id is required") }
        guard let latitude = call.getDouble("latitude"), (-90...90).contains(latitude) else {
            return call.reject("latitude must be between -90 and 90")
        }
        guard let longitude = call.getDouble("longitude"), (-180...180).contains(longitude) else {
            return call.reject("longitude must be between -180 and 180")
        }
        guard let radius = call.getDouble("radius"), radius > 0 else { return call.reject("radius must be greater than 0") }

        var region: [String: Any] = [
            "id": id,
            "latitude": latitude,
            "longitude": longitude,
            "radius": radius,
            "notifyOnEnter": call.getBool("notifyOnEnter") ?? true,
            "notifyOnExit": call.getBool("notifyOnExit") ?? true
        ]
        if let enter = call.getObject("enterNotification") { region["enterNotification"] = notification(enter) }
        if let exit = call.getObject("exitNotification") { region["exitNotification"] = notification(exit) }
        if let icon = call.getString("androidSmallIcon") { region["androidSmallIcon"] = icon }

        DispatchQueue.main.async {
            let status = self.implementation.authorizationStatus
            guard status == .authorizedAlways || status == .authorizedWhenInUse else {
                return call.reject("Location permission not granted", "PERMISSION_DENIED")
            }
            // Region monitoring needs precise location; with approximate location iOS delivers no events.
            guard self.implementation.hasFullAccuracy else {
                return call.reject("Precise location is turned off", "PERMISSION_DENIED")
            }
            do {
                try self.implementation.startMonitoring(region) { error in
                    if let error = error { call.reject(error.localizedDescription, "REGISTER_FAILED") } else { call.resolve() }
                }
            } catch {
                call.reject(error.localizedDescription, "REGISTER_FAILED")
            }
        }
    }

    @objc func removeRegion(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else { return call.reject("id is required") }
        DispatchQueue.main.async {
            do {
                try self.implementation.stopMonitoring(id)
                call.resolve()
            } catch {
                call.reject(error.localizedDescription, "UNREGISTER_FAILED")
            }
        }
    }

    @objc func getRegions(_ call: CAPPluginCall) {
        call.resolve(["regions": implementation.store.regions()])
    }

    @objc func getEvents(_ call: CAPPluginCall) {
        call.resolve(["events": implementation.store.events()])
    }

    @objc func clearEvents(_ call: CAPPluginCall) {
        // A present but malformed ids value must never fall through to "delete all".
        var ids: Set<String>?
        if call.options["ids"] != nil {
            guard let list = call.getArray("ids", String.self) else { return call.reject("ids must be an array of strings") }
            ids = Set(list)
        }
        implementation.store.clearEvents(ids)
        call.resolve()
    }

    private func notification(_ source: JSObject) -> [String: Any] {
        return ["title": source["title"] as? String ?? "", "body": source["body"] as? String ?? ""]
    }

    private func permissionStatus(_ done: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            let status = self.implementation.authorizationStatus
            let location: String
            let background: String
            switch status {
            case _ where !self.implementation.hasFullAccuracy && status != .notDetermined:
                // Approximate location cannot geofence; report it as not granted (same as Android coarse-only).
                location = "denied"
                background = "denied"
            case .authorizedAlways:
                location = "granted"
                background = "granted"
            case .authorizedWhenInUse:
                location = "granted"
                // iOS does not reveal whether the upgrade prompt is still available.
                background = "prompt"
            case .notDetermined:
                location = "prompt"
                background = "prompt"
            default:
                location = "denied"
                background = "denied"
            }
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let notifications: String
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: notifications = "granted"
                case .denied: notifications = "denied"
                default: notifications = "prompt"
                }
                done(["location": location, "backgroundLocation": background, "notifications": notifications])
            }
        }
    }
}
