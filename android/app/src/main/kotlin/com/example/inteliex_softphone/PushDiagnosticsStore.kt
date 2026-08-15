package com.sesdata.inteliex_softphone

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** FCM callback'i Flutter kapalıyken çalışabildiği için olayları native tarafta kuyruklar. */
object PushDiagnosticsStore {
    private const val PREFS_NAME = "inteliex_push_diagnostics"
    private const val KEY_EVENTS = "events"
    private const val MAX_EVENTS = 50

    @Synchronized
    fun record(context: Context, event: JSONObject) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val current = try {
            JSONArray(prefs.getString(KEY_EVENTS, "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        event.put("recordedAt", System.currentTimeMillis())
        val next = JSONArray()
        val start = maxOf(0, current.length() - MAX_EVENTS + 1)
        for (index in start until current.length()) next.put(current.get(index))
        next.put(event)
        prefs.edit().putString(KEY_EVENTS, next.toString()).apply()
    }

    @Synchronized
    fun consume(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_EVENTS, "[]") ?: "[]"
        prefs.edit().remove(KEY_EVENTS).apply()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { index ->
                val value = array.optJSONObject(index) ?: return@mapNotNull null
                value.keys().asSequence().associateWith { key ->
                    when (val item = value.opt(key)) {
                        JSONObject.NULL -> null
                        is JSONArray ->
                            (0 until item.length()).map { child -> item.optString(child) }
                        is JSONObject -> item.toString()
                        else -> item
                    }
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
