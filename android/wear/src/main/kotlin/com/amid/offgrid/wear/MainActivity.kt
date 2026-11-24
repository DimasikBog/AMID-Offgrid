package com.amid.offgrid.wear

import android.app.Activity
import android.os.Bundle
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject

/** Small standalone watch UI: no Flutter engine, model, location or network. */
class MainActivity : Activity() {
    private val settings by lazy { getSharedPreferences("amid-pocket", MODE_PRIVATE) }
    private val pack by lazy {
        JSONObject(assets.open("cards.json").bufferedReader(Charsets.UTF_8).use { it.readText() })
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun page(title: String): LinearLayout {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val edge = if (resources.configuration.isScreenRound) 28 else 16
            setPadding(dp(edge), dp(22), dp(edge), dp(30))
            setBackgroundColor(Color.BLACK)
        }
        column.addView(TextView(this).apply {
            text = title; textSize = 20f; setTextColor(Color.rgb(181, 230, 200))
            setTypeface(null, Typeface.BOLD); gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(12))
        })
        setContentView(ScrollView(this).apply { addView(column) })
        return column
    }
    override fun onCreate(state: Bundle?) { super.onCreate(state); home() }
    private fun home() {
        val column = page("AMID Pocket")
        column.addView(TextView(this).apply {
            text = "Мій список · позначаю сам"; textSize = 14f; setTextColor(Color.WHITE)
        })
        val checklist = pack.getJSONArray("checklist")
        for (i in 0 until checklist.length()) {
            val item = checklist.getJSONObject(i); val id = item.getString("id")
            column.addView(CheckBox(this).apply {
                text = item.getString("title"); textSize = 14f; minHeight = dp(48)
                setTextColor(Color.WHITE); isChecked = settings.getBoolean(id, false)
                setOnCheckedChangeListener { _, checked -> settings.edit().putBoolean(id, checked).apply() }
            })
        }
        val cards = pack.getJSONArray("cards")
        for (i in 0 until cards.length()) {
            val card = cards.getJSONObject(i)
            column.addView(Button(this).apply {
                text = card.getString("title"); textSize = 14f; isAllCaps = false
                minHeight = dp(48)
                setOnClickListener { showCard(card) }
            })
        }
    }
    private fun showCard(card: JSONObject) {
        val column = page(card.getString("title"))
        column.addView(TextView(this).apply {
            text = card.getString("body"); textSize = 16f
            setTextColor(Color.WHITE); setLineSpacing(dp(3).toFloat(), 1f)
        })
        column.addView(Button(this).apply {
            text = "До списку"; isAllCaps = false; minHeight = dp(48)
            setOnClickListener { home() }
        })
    }
}
