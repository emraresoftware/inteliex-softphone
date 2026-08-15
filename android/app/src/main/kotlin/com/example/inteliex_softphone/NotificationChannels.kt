package com.sesdata.inteliex_softphone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * ABTO SDK'nın gelen çağrı bildirimi için kullandığı channel'ı **ABTO'dan önce**
 * doğru lockscreen ayarlarıyla oluşturur. `createNotificationChannel` mevcut
 * channel'ı override etmediği için ABTO sonradan kendi (eksik ayarlı) channel'ını
 * yaratmaya çalıştığında bizim ayarımız korunur.
 */
object NotificationChannels {
    // ABTO SDK içindeki AbtoCallEventsReceiver.CHANEL_CALL_ID ile birebir aynı olmalı.
    const val ABTO_CALL_CHANNEL_ID = "abto_phone_call"

    // Titreşim deseni: bekleme(0), titreşim(500), duraklama(300), titreşim(500) ...
    private val CALL_VIBRATION_PATTERN = longArrayOf(0, 500, 300, 500, 300, 500, 300, 500)

    fun ensureAll(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return

        if (manager.getNotificationChannel(ABTO_CALL_CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                ABTO_CALL_CHANNEL_ID,
                "Gelen Çağrı",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Gelen sesli çağrı bildirimleri"
                // Kilit ekranında içeriği ve aksiyonları (Cevapla / Reddet) göster.
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableLights(true)
                setShowBadge(true)
                setBypassDnd(true)
                // ABTO SDK kendi ringtone'unu yönetiyor; channel'a sound eklersek
                // kilitli ekranda çift zil çalar — ses kanalı kapalı tutulur.
                setSound(null, null)
                // Titreşim: bazı ROM'larda (MIUI, One UI) ABTO'nun doğrudan Vibrator
                // çağrısı kısıtlanıyor; bildirim kanalı üzerinden titreşim güvenilir.
                enableVibration(true)
                vibrationPattern = CALL_VIBRATION_PATTERN
            }
            manager.createNotificationChannel(channel)
        }
    }
}
