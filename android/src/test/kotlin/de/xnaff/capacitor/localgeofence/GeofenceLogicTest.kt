package de.xnaff.capacitor.localgeofence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale
import java.util.TimeZone

class GeofenceLogicTest {

    private val utc = TimeZone.getTimeZone("UTC")

    @Test
    fun fillsTimePlaceholder() {
        // 2026-11-03T17:42:00Z
        val text = GeofenceLogic.fillTemplate("Work ended at {time}?", 1793727720000, Locale.GERMANY, utc)
        assertEquals("Work ended at 17:42?", text)
    }

    @Test
    fun leavesTemplateWithoutPlaceholder() {
        assertEquals("Hello", GeofenceLogic.fillTemplate("Hello", 0, Locale.GERMANY, utc))
    }

    @Test
    fun skipsRepeatedTransition() {
        assertTrue(GeofenceLogic.isNewTransition(null, "enter"))
        assertTrue(GeofenceLogic.isNewTransition("enter", "exit"))
        assertFalse(GeofenceLogic.isNewTransition("exit", "exit"))
    }

    @Test
    fun keepsNewestEvents() {
        assertEquals(listOf(3, 4), GeofenceLogic.keepNewest(listOf(1, 2, 3, 4), 2))
        assertEquals(listOf(1), GeofenceLogic.keepNewest(listOf(1), 2))
    }
}
