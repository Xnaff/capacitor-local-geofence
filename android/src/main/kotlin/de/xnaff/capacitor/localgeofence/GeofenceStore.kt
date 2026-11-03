package de.xnaff.capacitor.localgeofence

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Regions, recorded events and the last transition per region, persisted in SharedPreferences.
 * The receiver (main thread) and plugin calls (plugin thread) share one lock, because each write is a
 * read-modify-write of a JSON blob.
 */
class GeofenceStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun regions(): List<JSONObject> {
        val map = JSONObject(prefs.getString(KEY_REGIONS, "{}")!!)
        return map.keys().asSequence().map { map.getJSONObject(it) }.toList()
    }

    fun region(id: String): JSONObject? = JSONObject(prefs.getString(KEY_REGIONS, "{}")!!).optJSONObject(id)

    fun saveRegion(region: JSONObject): Boolean = synchronized(LOCK) {
        val map = JSONObject(prefs.getString(KEY_REGIONS, "{}")!!)
        map.put(region.getString("id"), region)
        prefs.edit().putString(KEY_REGIONS, map.toString()).commit()
    }

    fun removeRegion(id: String): Boolean = synchronized(LOCK) {
        val map = JSONObject(prefs.getString(KEY_REGIONS, "{}")!!)
        map.remove(id)
        prefs.edit().putString(KEY_REGIONS, map.toString()).remove(KEY_LAST_PREFIX + id).commit()
    }

    fun events(): List<JSONObject> {
        val array = JSONArray(prefs.getString(KEY_EVENTS, "[]")!!)
        return (0 until array.length()).map { array.getJSONObject(it) }
    }

    /**
     * Remembers [transition] for the region and returns true when it differs from the previous one.
     * Also called for directions the region does not record, so a later opposite event is not lost.
     */
    fun markTransition(regionId: String, transition: String): Boolean = synchronized(LOCK) {
        if (!GeofenceLogic.isNewTransition(prefs.getString(KEY_LAST_PREFIX + regionId, null), transition)) return false
        prefs.edit().putString(KEY_LAST_PREFIX + regionId, transition).commit()
    }

    /** Appends the event; commit() so a receiver process that dies right after keeps it. */
    fun addEvent(event: JSONObject): Boolean = synchronized(LOCK) {
        val events = GeofenceLogic.keepNewest(events() + event)
        prefs.edit().putString(KEY_EVENTS, JSONArray(events).toString()).commit()
    }

    fun clearEvents(ids: Set<String>?): Boolean = synchronized(LOCK) {
        val kept = if (ids == null) emptyList() else events().filterNot { ids.contains(it.getString("id")) }
        prefs.edit().putString(KEY_EVENTS, JSONArray(kept).toString()).commit()
    }

    companion object {
        private val LOCK = Any()
        private const val PREFS_NAME = "de.xnaff.capacitor.localgeofence"
        private const val KEY_REGIONS = "regions"
        private const val KEY_EVENTS = "events"
        private const val KEY_LAST_PREFIX = "last_"
    }
}
