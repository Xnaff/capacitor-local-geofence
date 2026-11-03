package de.xnaff.capacitor.localgeofence

import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class GeofenceStoreTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun event(id: String, transition: String) =
        JSONObject().put("id", id).put("regionId", "work").put("transition", transition).put("timestamp", 1L)

    @Test
    fun recordedEventIsReadableThroughFreshStore() {
        // The receiver and the plugin each create their own store instance.
        assertTrue(GeofenceStore(context).record("work", "exit", event("e1", "exit")))
        assertEquals(listOf("e1"), GeofenceStore(context).events().map { it.getString("id") })
    }

    @Test
    fun repeatedTransitionIsDroppedUntilBaselineIsForgotten() {
        val store = GeofenceStore(context)
        assertTrue(store.record("work", "exit", event("e1", "exit")))
        assertFalse(store.record("work", "exit", event("e2", "exit")))
        store.forgetTransitions()
        assertTrue(store.record("work", "exit", event("e3", "exit")))
        assertEquals(listOf("e1", "e3"), store.events().map { it.getString("id") })
    }

    @Test
    fun restorePutsBackRegionAndBaseline() {
        val store = GeofenceStore(context)
        val previous = JSONObject().put("id", "work").put("radius", 100.0)
        store.saveRegion(previous)
        store.record("work", "enter", null)
        store.saveRegion(JSONObject().put("id", "work").put("radius", 300.0))
        assertNull(store.lastTransition("work"))
        store.restore("work", previous, "enter")
        assertEquals(100.0, store.region("work")!!.getDouble("radius"), 0.0)
        assertEquals("enter", store.lastTransition("work"))
    }

    @Test
    fun clearEventsRemovesOnlyGivenIds() {
        val store = GeofenceStore(context)
        store.record("work", "enter", event("a", "enter"))
        store.record("work", "exit", event("b", "exit"))
        store.clearEvents(setOf("a"))
        assertEquals(listOf("b"), store.events().map { it.getString("id") })
    }
}
