package de.xnaff.capacitor.localgeofence

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Regions, recorded events and the last transition per region, persisted in SharedPreferences. */
class GeofenceStore(context: Context) {

    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun regions(): List<JSONObject> {
        val map = JSONObject(prefs.getString(KEY_REGIONS, "{}")!!)
        return map.keys().asSequence().map { map.getJSONObject(it) }.toList()
    }

    fun region(id: String): JSONObject? = JSONObject(prefs.getString(KEY_REGIONS, "{}")!!).optJSONObject(id)

    fun saveRegion(region: JSONObject) {
        val map = JSONObject(prefs.getString(KEY_REGIONS, "{}")!!)
        map.put(region.getString("id"), region)
        prefs.edit().putString(KEY_REGIONS, map.toString()).commit()
    }

    fun removeRegion(id: String) {
        val map = JSONObject(prefs.getString(KEY_REGIONS, "{}")!!)
        map.remove(id)
        prefs.edit().putString(KEY_REGIONS, map.toString()).remove(KEY_LAST_PREFIX + id).commit()
    }

    fun lastTransition(regionId: String): String? = prefs.getString(KEY_LAST_PREFIX + regionId, null)

    fun events(): List<JSONObject> {
        val array = JSONArray(prefs.getString(KEY_EVENTS, "[]")!!)
        return (0 until array.length()).map { array.getJSONObject(it) }
    }

    /** Appends the event and remembers its transition; commit() so a dying receiver process keeps it. */
    fun addEvent(event: JSONObject) {
        val events = GeofenceLogic.keepNewest(events() + event)
        prefs
            .edit()
            .putString(KEY_EVENTS, JSONArray(events).toString())
            .putString(KEY_LAST_PREFIX + event.getString("regionId"), event.getString("transition"))
            .commit()
    }

    fun clearEvents(ids: Set<String>?) {
        val kept = if (ids == null) emptyList() else events().filterNot { ids.contains(it.getString("id")) }
        prefs.edit().putString(KEY_EVENTS, JSONArray(kept).toString()).commit()
    }

    companion object {
        private const val PREFS_NAME = "de.xnaff.capacitor.localgeofence"
        private const val KEY_REGIONS = "regions"
        private const val KEY_EVENTS = "events"
        private const val KEY_LAST_PREFIX = "last_"
    }
}
