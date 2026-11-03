package de.xnaff.capacitor.localgeofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.tasks.Tasks

/** Re-adds regions after a reboot or app update, both of which clear Play services geofences. */
class GeofenceBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            // Keep the process alive until Play services confirmed every registration.
            val pending = goAsync()
            Tasks.whenAllComplete(GeofenceRegistrar.restoreAll(context)).addOnCompleteListener { pending.finish() }
        }
    }
}
