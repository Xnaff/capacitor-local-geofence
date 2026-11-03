package de.xnaff.capacitor.localgeofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.LocationManager

/**
 * Re-adds regions after a reboot, an app update or location being turned back on; all three clear
 * Play services geofences. PROVIDERS_CHANGED is exempt from the Android 8 implicit-broadcast limits.
 */
class GeofenceBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in RESTORE_ACTIONS) {
            // Positions may have changed unobserved while geofences were gone.
            GeofenceStore(context).forgetTransitions()
            GeofenceRestoreWorker.enqueue(context)
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
