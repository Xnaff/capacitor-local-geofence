package de.xnaff.capacitor.localgeofence

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import com.getcapacitor.annotation.PermissionCallback
import org.json.JSONObject

@CapacitorPlugin(
    name = "LocalGeofence",
    permissions = [
        Permission(
            alias = LocalGeofencePlugin.LOCATION,
            strings = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION],
        ),
        Permission(alias = LocalGeofencePlugin.BACKGROUND_LOCATION, strings = [Manifest.permission.ACCESS_BACKGROUND_LOCATION]),
        Permission(alias = LocalGeofencePlugin.NOTIFICATIONS, strings = [Manifest.permission.POST_NOTIFICATIONS]),
    ],
)
class LocalGeofencePlugin : Plugin() {

    private lateinit var store: GeofenceStore

    override fun load() {
        store = GeofenceStore(context)
        instance = this
        GeofenceRegistrar.restoreAll(context)
    }

    /** Re-adds regions dropped while location was off or before permission was granted. */
    override fun handleOnResume() {
        GeofenceRegistrar.restoreAll(context)
    }

    override fun handleOnDestroy() {
        if (instance === this) instance = null
    }

    @PluginMethod
    override fun checkPermissions(call: PluginCall) {
        call.resolve(permissionStatus())
    }

    @PluginMethod
    override fun requestPermissions(call: PluginCall) {
        val requested = call.getArray("permissions")?.toList<String>() ?: listOf(LOCATION, NOTIFICATIONS)
        requested.firstOrNull { it !in ALIASES }?.let { return call.reject("Unknown permission: $it") }
        // Below these SDK levels the permission does not exist and is implied.
        val aliases = requested.filter {
            when (it) {
                BACKGROUND_LOCATION -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                NOTIFICATIONS -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                else -> true
            }
        }
        if (aliases.isEmpty()) {
            call.resolve(permissionStatus())
        } else {
            requestPermissionForAliases(aliases.toTypedArray(), call, "permissionsCallback")
        }
    }

    @PermissionCallback
    private fun permissionsCallback(call: PluginCall) {
        GeofenceRegistrar.restoreAll(context)
        call.resolve(permissionStatus())
    }

    @PluginMethod
    fun addRegion(call: PluginCall) {
        val id = call.getString("id")
        val latitude = call.getDouble("latitude")
        val longitude = call.getDouble("longitude")
        val radius = call.getDouble("radius")
        if (id.isNullOrEmpty()) return call.reject("id is required")
        if (latitude == null || latitude < -90 || latitude > 90) return call.reject("latitude must be between -90 and 90")
        if (longitude == null || longitude < -180 || longitude > 180) return call.reject("longitude must be between -180 and 180")
        if (radius == null || radius <= 0 || radius > Float.MAX_VALUE) return call.reject("radius must be greater than 0")
        if (!GeofenceRegistrar.hasLocationPermission(context)) return call.reject("Location permission not granted", "PERMISSION_DENIED")

        val region = JSONObject()
            .put("id", id)
            .put("latitude", latitude)
            .put("longitude", longitude)
            .put("radius", radius)
            .put("notifyOnEnter", call.getBoolean("notifyOnEnter", true))
            .put("notifyOnExit", call.getBoolean("notifyOnExit", true))
        call.getObject("enterNotification")?.let { region.put("enterNotification", notification(it)) }
        call.getObject("exitNotification")?.let { region.put("exitNotification", notification(it)) }
        call.getString("androidSmallIcon")?.let { region.put("androidSmallIcon", it) }

        val task = try {
            GeofenceRegistrar.add(context, region)
        } catch (error: Exception) {
            return call.reject("Could not add region: ${error.message}", "REGISTER_FAILED", error)
        }
        task
            .addOnSuccessListener { call.resolve() }
            .addOnFailureListener { error -> call.reject("Could not add region: ${error.message}", "REGISTER_FAILED", error) }
    }

    @PluginMethod
    fun removeRegion(call: PluginCall) {
        val id = call.getString("id") ?: return call.reject("id is required")
        val task = try {
            GeofenceRegistrar.remove(context, id)
        } catch (error: Exception) {
            return call.reject("Could not remove region: ${error.message}", "UNREGISTER_FAILED", error)
        }
        task
            .addOnSuccessListener { call.resolve() }
            .addOnFailureListener { error -> call.reject("Could not remove region: ${error.message}", "UNREGISTER_FAILED", error) }
    }

    @PluginMethod
    fun getRegions(call: PluginCall) {
        call.resolve(JSObject().put("regions", JSArray(store.regions())))
    }

    @PluginMethod
    fun getEvents(call: PluginCall) {
        call.resolve(JSObject().put("events", JSArray(store.events())))
    }

    @PluginMethod
    fun clearEvents(call: PluginCall) {
        if (store.clearEvents(call.getArray("ids")?.toList<String>()?.toSet())) call.resolve() else call.reject("Could not persist", "STORAGE_FAILED")
    }

    private fun notification(source: JSObject): JSONObject =
        JSONObject().put("title", source.getString("title", "")).put("body", source.getString("body", ""))

    private fun permissionStatus(): JSObject {
        val location = getPermissionState(LOCATION).toString()
        val background = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) getPermissionState(BACKGROUND_LOCATION).toString() else location
        val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getPermissionState(NOTIFICATIONS).toString()
        } else if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            "granted"
        } else {
            "denied"
        }
        // Coarse-only location cannot geofence; report it as not granted.
        val fine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        return JSObject()
            .put("location", if (location == "granted" && !fine) "denied" else location)
            .put("backgroundLocation", background)
            .put("notifications", notifications)
    }

    private fun emit(event: JSONObject) {
        notifyListeners("transition", JSObject.fromJSONObject(event))
    }

    companion object {
        const val LOCATION = "location"
        const val BACKGROUND_LOCATION = "backgroundLocation"
        const val NOTIFICATIONS = "notifications"
        private val ALIASES = setOf(LOCATION, BACKGROUND_LOCATION, NOTIFICATIONS)

        @Volatile
        private var instance: LocalGeofencePlugin? = null

        /** Forwards a stored transition to JS when the plugin is loaded; otherwise getEvents() picks it up later. */
        fun emitTransition(event: JSONObject) {
            instance?.emit(event)
        }
    }
}
