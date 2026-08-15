package com.sesdata.inteliex_softphone

import android.content.Context

/**
 * ABTO full-screen intent ile MainActivity açıldığında çağrı bilgisini
 * SharedPreferences'a yazar. Flutter cold-start sırasında onIncomingCall
 * event'ini kaçırırsa bu store'dan okuyup ActiveCall'u sentezler.
 */
object PendingCallStore {
    private const val PREFS_NAME = "inteliex_pending_call"
    private const val KEY_CALL_ID = "callId"
    private const val KEY_REMOTE = "remoteContact"
    private const val KEY_IS_VIDEO = "isVideo"
    private const val KEY_TIMESTAMP = "ts"

    // Aynı çağrı bilgisini birden fazla okumamak için en fazla 60s saklarız.
    private const val MAX_AGE_MS = 60_000L

    fun savePending(
        context: Context,
        callId: Int,
        remoteContact: String,
        isVideo: Boolean,
    ) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_CALL_ID, callId)
            .putString(KEY_REMOTE, remoteContact)
            .putBoolean(KEY_IS_VIDEO, isVideo)
            .putLong(KEY_TIMESTAMP, System.currentTimeMillis())
            .apply()
    }

    fun consumePending(context: Context): Map<String, Any?>? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val callId = prefs.getInt(KEY_CALL_ID, -1)
        if (callId == -1) return null
        val ts = prefs.getLong(KEY_TIMESTAMP, 0L)
        // SharedPreferences.Editor.apply() bellek içindeki değerleri hemen
        // temizler. Bu yüzden alanları clear() çağrısından önce kopyalamalıyız;
        // aksi halde cold-start'ta çağrı kimliği bulunurken arayan kişi ve
        // video bilgisi boş dönüyordu.
        val remoteContact = prefs.getString(KEY_REMOTE, "") ?: ""
        val isVideo = prefs.getBoolean(KEY_IS_VIDEO, false)
        val now = System.currentTimeMillis()
        prefs.edit().clear().apply()
        if (now - ts > MAX_AGE_MS) return null
        return mapOf(
            "callId" to callId,
            "remoteContact" to remoteContact,
            "isVideo" to isVideo,
        )
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().clear().apply()
    }
}
