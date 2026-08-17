package com.sesdata.inteliex_softphone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.net.wifi.WifiManager
import androidx.core.app.NotificationCompat

class SipForegroundService : Service() {
    private var cpuWakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                releaseNetworkLocks()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> startInForeground(
                title = intent?.getStringExtra(EXTRA_TITLE) ?: defaultTitle(),
                text = intent?.getStringExtra(EXTRA_TEXT) ?: defaultText(),
            )
        }
        return START_STICKY
    }

    private fun startInForeground(title: String, text: String) {
        acquireNetworkLocks()
        ensureChannel()
        val tapIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = tapIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_inteliex)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireNetworkLocks() {
        try {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            if (cpuWakeLock == null) {
                cpuWakeLock = powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "inteliex:sip_cpu",
                ).apply { setReferenceCounted(false) }
            }
            cpuWakeLock?.let { if (!it.isHeld) it.acquire() }

            val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            if (wifiLock == null) {
                wifiLock = wifiManager.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    "inteliex:sip_wifi",
                ).apply { setReferenceCounted(false) }
            }
            wifiLock?.let { if (!it.isHeld) it.acquire() }
        } catch (_: Exception) {}
    }

    private fun releaseNetworkLocks() {
        try { cpuWakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        try { wifiLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        cpuWakeLock = null
        wifiLock = null
    }

    override fun onDestroy() {
        releaseNetworkLocks()
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SIP bağlantısı",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "SIP hesabı kayıtlı ve gelen çağrıları dinliyor"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun defaultTitle(): String = "Softphone etkin"
    private fun defaultText(): String = "SIP hesabı arka planda kayıtlı"

    companion object {
        private const val CHANNEL_ID = "sip_foreground"
        private const val NOTIFICATION_ID = 4311
        private const val ACTION_START = "com.sesdata.inteliex_softphone.ACTION_START"
        private const val ACTION_STOP = "com.sesdata.inteliex_softphone.ACTION_STOP"
        private const val EXTRA_TITLE = "extra_title"
        private const val EXTRA_TEXT = "extra_text"

        fun start(context: Context, title: String?, text: String?) {
            val intent = Intent(context, SipForegroundService::class.java).apply {
                action = ACTION_START
                if (title != null) putExtra(EXTRA_TITLE, title)
                if (text != null) putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, SipForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.stopService(intent)
        }
    }
}
