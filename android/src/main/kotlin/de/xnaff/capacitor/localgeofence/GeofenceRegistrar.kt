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

/**
 * Registers stored regions with the Play services geofencing client. Every store change and its
 * client submission happen under one lock, so a restore never submits geometry older than a
 * concurrent add or remove; the client applies submissions in order.
 */
object GeofenceRegistrar {

    private val LOCK = Any()

    /** Region ids with an add/remove still waiting for Play services; guarded by LOCK. */
    private val inFlight = mutableSetOf<String>()

    private fun begin(id: String) {
        if (!inFlight.add(id)) throw IllegalStateException("An operation for $id is still pending")
    }

    private fun <T> Task<T>.finishing(id: String): Task<T> = addOnCompleteListener { synchronized(LOCK) { inFlight.remove(id) } }

    private const val REQUEST_CODE = 0x6E0F

    fun hasLocationPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Stores [region] and submits it; a failed registration restores the previous stored region.
     * One operation per id at a time (inFlight), so a rollback never restores another operation's state.
     */
    fun add(context: Context, region: JSONObject): Task<Void> = synchronized(LOCK) {
        val store = GeofenceStore(context)
        val id = region.getString("id")
        begin(id)
        val previous = store.region(id)
        val previousLast = store.lastTransition(id)
        val task = try {
            if (!store.saveRegion(region)) throw IllegalStateException("Could not persist region")
            register(context, region)
        } catch (error: Exception) {
            store.restore(id, previous, previousLast)
            inFlight.remove(id)
            throw error
        }
        task.addOnFailureListener {
            synchronized(LOCK) { store.restore(id, previous, previousLast) }
            // A restore that skipped this id meanwhile must still register the rolled-back region.
            if (previous != null) GeofenceRestoreWorker.enqueue(context)
        }.finishing(id)
    }

    /** Removes the stored region and submits the removal; a failed removal restores it. */
    fun remove(context: Context, id: String): Task<Void> = synchronized(LOCK) {
        val store = GeofenceStore(context)
        begin(id)
        val previous = store.region(id)
        val previousLast = store.lastTransition(id)
        if (!store.removeRegion(id)) {
            inFlight.remove(id)
            throw IllegalStateException("Could not persist removal")
        }
        LocationServices.getGeofencingClient(context).removeGeofences(listOf(id)).addOnFailureListener {
            synchronized(LOCK) { store.restore(id, previous, previousLast) }
            if (previous != null) GeofenceRestoreWorker.enqueue(context)
        }.finishing(id)
    }

    @SuppressLint("MissingPermission")
    private fun register(context: Context, region: JSONObject): Task<Void> {
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

    /**
     * Play services drops all geofences on reboot, app update and location toggles; re-add them.
     * Regions with a pending add/remove are skipped: that operation registers their final state.
     */
    fun restoreAll(context: Context): List<Task<Void>> = synchronized(LOCK) {
        if (!hasLocationPermission(context)) return emptyList()
        GeofenceStore(context).regions().filterNot { inFlight.contains(it.optString("id")) }.mapNotNull { region ->
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
