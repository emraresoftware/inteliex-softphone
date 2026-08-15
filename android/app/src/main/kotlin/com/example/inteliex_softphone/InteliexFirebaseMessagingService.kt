package com.sesdata.inteliex_softphone

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONArray
import org.json.JSONObject

class InteliexFirebaseMessagingService : FirebaseMessagingService() {
    override fun onCreate() {
        super.onCreate()
        // Cold-start push senaryosunda da channel'ın PUBLIC visibility ile
        // hazır olması için burada da çağırıyoruz (ABTO'dan önce).
        NotificationChannels.ensureAll(applicationContext)
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        if (token.isBlank()) return
        PushTokenStore.saveToken(applicationContext, token)
        PushDiagnosticsStore.record(
            applicationContext,
            JSONObject().put("event", "token_refreshed").put("tokenPresent", true),
        )
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        NotificationChannels.ensureAll(applicationContext)

        // İçerik ve token gönderilmez; yalnızca teslim kanıtı ve veri anahtarları.
        PushDiagnosticsStore.record(
            applicationContext,
            JSONObject()
                .put("event", "message_received")
                .put("messageIdPresent", !message.messageId.isNullOrBlank())
                .put("sentTime", message.sentTime)
                .put("hasNotification", message.notification != null)
                .put("dataKeys", JSONArray(message.data.keys.sorted())),
        )

        val title = message.data["title"]
            ?: message.notification?.title
            ?: "Softphone etkin"
        val text = message.data["body"]
            ?: message.notification?.body
            ?: "Gelen cagri kontrol ediliyor"

        // Kapalı/arka plan senaryosunda uygulamayı canlı tut.
        SipForegroundService.start(applicationContext, title, text)

        // Data-only push'larda kullanıcıya görünür bir bildirim de üret.
        showFallbackNotification(title, text)
    }

    private fun showFallbackNotification(title: String, text: String) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                FALLBACK_CHANNEL_ID,
                "Intsoft Push",
                NotificationManager.IMPORTANCE_HIGH,
            )
            manager.createNotificationChannel(channel)
        }

        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1002,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, FALLBACK_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify(System.currentTimeMillis().toInt(), notification)
    }

    companion object {
        private const val FALLBACK_CHANNEL_ID = "inteliex_push_fallback"
    }
}
