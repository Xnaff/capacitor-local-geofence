package de.xnaff.capacitor.localgeofence

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.getcapacitor.Logger
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofenceStatusCodes
import com.google.android.gms.location.GeofencingEvent
import org.json.JSONObject
import java.util.UUID

/** Receives transitions from Play services, also when the app process was not running. */
class GeofenceBroadcastReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) {
            // GEOFENCE_NOT_AVAILABLE: location was turned off; regions stay stored and are restored on next app start.
            Logger.error("LocalGeofence", "Geofence error: ${GeofenceStatusCodes.getStatusCodeString(event.errorCode)}", null)
            return
        }
        val transition = when (event.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "enter"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "exit"
            else -> return
        }
        val timestamp = event.triggeringLocation?.time ?: System.currentTimeMillis()
        val store = GeofenceStore(context)

        for (geofence in event.triggeringGeofences.orEmpty()) {
            val region = store.region(geofence.requestId) ?: continue
            if (!region.optBoolean(if (transition == "enter") "notifyOnEnter" else "notifyOnExit", true)) continue
            if (!GeofenceLogic.isNewTransition(store.lastTransition(geofence.requestId), transition)) continue

            val record = JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("regionId", geofence.requestId)
                .put("transition", transition)
                .put("timestamp", timestamp)
            store.addEvent(record)
            region.optJSONObject(if (transition == "enter") "enterNotification" else "exitNotification")?.let {
                showNotification(context, region, it, timestamp)
            }
            LocalGeofencePlugin.emitTransition(record)
        }
    }

    @SuppressLint("MissingPermission")
    private fun showNotification(context: Context, region: JSONObject, notification: JSONObject, timestamp: Long) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Location events", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val built = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIcon(context, region.optString("androidSmallIcon")))
            .setContentTitle(GeofenceLogic.fillTemplate(notification.optString("title"), timestamp))
            .setContentText(GeofenceLogic.fillTemplate(notification.optString("body"), timestamp))
            .setWhen(timestamp)
            .setShowWhen(true)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        NotificationManagerCompat.from(context).notify(region.getString("id").hashCode(), built)
    }

    private fun smallIcon(context: Context, name: String): Int {
        if (name.isNotEmpty()) {
            val id = context.resources.getIdentifier(name, "drawable", context.packageName)
            if (id != 0) return id
        }
        return context.applicationInfo.icon
    }

    companion object {
        const val CHANNEL_ID = "local_geofence"
    }
}
