package de.xnaff.capacitor.localgeofence

import java.text.DateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Platform-free rules, kept apart so they run in plain JVM unit tests. */
object GeofenceLogic {
    const val MAX_EVENTS = 500

    /** Replaces `{time}` with the short local time of [timestamp]. */
    fun fillTemplate(
        template: String,
        timestamp: Long,
        locale: Locale = Locale.getDefault(),
        zone: TimeZone = TimeZone.getDefault(),
    ): String {
        if (!template.contains("{time}")) return template
        val format = DateFormat.getTimeInstance(DateFormat.SHORT, locale).apply { timeZone = zone }
        return template.replace("{time}", format.format(Date(timestamp)))
    }

    /** Play services may deliver the same transition twice; only a change is a new event. */
    fun isNewTransition(last: String?, transition: String): Boolean = last != transition

    /** Keeps the newest [max] items of an oldest-first list. */
    fun <T> keepNewest(items: List<T>, max: Int = MAX_EVENTS): List<T> =
        if (items.size <= max) items else items.subList(items.size - max, items.size)
}
