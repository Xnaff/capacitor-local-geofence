package de.xnaff.capacitor.localgeofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import com.google.android.gms.tasks.Tasks

/**
 * Re-adds regions after a reboot, an app update or location being turned back on; all three clear
 * Play services geofences. PROVIDERS_CHANGED is exempt from the Android 8 implicit-broadcast limits.
 */
class GeofenceBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in RESTORE_ACTIONS) {
            // Keep the process alive until Play services confirmed every registration.
            val pending = goAsync()
            Tasks.whenAllComplete(GeofenceRegistrar.restoreAll(context)).addOnCompleteListener { pending.finish() }
        }
    }

    companion object {
        private val RESTORE_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            LocationManager.PROVIDERS_CHANGED_ACTION,
        )
    }
}
