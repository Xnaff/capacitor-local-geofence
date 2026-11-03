package de.xnaff.capacitor.localgeofence

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.getcapacitor.Logger
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.Task
import org.json.JSONObject

/** Registers stored regions with the Play services geofencing client. */
object GeofenceRegistrar {

    private const val REQUEST_CODE = 0x6E0F

    fun hasLocationPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    fun register(context: Context, region: JSONObject): Task<Void> {
        val geofence = Geofence.Builder()
            .setRequestId(region.getString("id"))
            .setCircularRegion(region.getDouble("latitude"), region.getDouble("longitude"), region.getDouble("radius").toFloat())
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()
        // No initial trigger: adding a region while inside it must not record an arrival.
        val request = GeofencingRequest.Builder().setInitialTrigger(0).addGeofence(geofence).build()
        return LocationServices.getGeofencingClient(context).addGeofences(request, pendingIntent(context))
    }

    fun unregister(context: Context, id: String): Task<Void> =
        LocationServices.getGeofencingClient(context).removeGeofences(listOf(id))

    /** Play services drops all geofences on reboot, app update and location toggles; re-add them. */
    fun restoreAll(context: Context): List<Task<Void>> {
        if (!hasLocationPermission(context)) return emptyList()
        return GeofenceStore(context).regions().mapNotNull { region ->
            try {
                register(context, region).addOnFailureListener { error ->
                    Logger.error("LocalGeofence", "Could not restore region ${region.optString("id")}", error)
                }
            } catch (error: Exception) {
                Logger.error("LocalGeofence", "Could not restore region ${region.optString("id")}", error)
                null
            }
        }
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java).setPackage(context.packageName)
        // Geofencing fills the intent with event extras, so it must be mutable on Android 12+.
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) flags = flags or PendingIntent.FLAG_MUTABLE
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
    }
}
