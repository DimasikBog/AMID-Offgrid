package com.amid.offgrid.wear

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiScrollable
import androidx.test.uiautomator.UiSelector
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class PocketUiTest {
    @Test fun checklistSurvivesActivityRestartAndAllCardsOpen() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val device = UiDevice.getInstance(instrumentation)
        val pack = JSONObject(context.assets.open("cards.json").bufferedReader().use { it.readText() })
        val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        device.waitForIdle()
        val first = pack.getJSONArray("checklist").getJSONObject(0).getString("title")
        fun reveal(text: String) {
            assertTrue("Cannot reveal $text", UiScrollable(UiSelector().scrollable(true)).scrollIntoView(UiSelector().text(text)))
        }
        reveal(first)
        val check = device.findObject(UiSelector().className("android.widget.CheckBox").text(first))
        val before = check.isChecked
        check.click()
        device.waitForIdle()
        assertEquals(!before, check.isChecked)
        val output = File(context.getExternalFilesDir(null), "emulator-evidence").apply { mkdirs() }
        assertTrue("Checklist screenshot failed", device.takeScreenshot(File(output, "01-checklist.png")))
        context.startActivity(intent)
        device.waitForIdle()
        reveal(first)
        assertEquals("Checklist did not persist", !before, device.findObject(UiSelector().text(first)).isChecked)
        val cards = pack.getJSONArray("cards")
        assertEquals(6, cards.length())
        for (i in 0 until cards.length()) {
            val card = cards.getJSONObject(i)
            reveal(card.getString("title"))
            device.findObject(UiSelector().className("android.widget.Button").text(card.getString("title"))).click()
            device.waitForIdle()
            assertTrue("Card body missing", device.findObject(UiSelector().text(card.getString("body"))).exists())
            assertTrue("Card screenshot failed", device.takeScreenshot(File(output, "card-$i.png")))
            reveal("До списку")
            device.findObject(UiSelector().text("До списку")).click()
            device.waitForIdle()
        }
        assertEquals(6, pack.getJSONArray("checklist").length())
        // The Gradle device runner uninstalls its test app after completion.
        // Preserve only synthetic test captures outside that app's data directory.
        device.executeShellCommand("cp -R ${output.absolutePath} /data/local/tmp/amid-pocket-evidence")
        val captures = device.executeShellCommand("ls /data/local/tmp/amid-pocket-evidence")
        assertTrue("Captures were not retained", captures.contains("01-checklist.png") && captures.contains("card-5.png"))
        println("AMID_WEAR_EMULATOR_PASS: six cards, checklist, activity restart")
    }
}
