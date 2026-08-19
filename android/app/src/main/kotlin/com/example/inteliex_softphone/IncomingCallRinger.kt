package com.sesdata.inteliex_softphone

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.util.Log

/**
 * Gelen çağrı zil sesi.
 *
 * ABTO SDK'nın çağrı bildirim kanalı (`abto_phone_call`) uygulama tarafında
 * bilerek sessiz oluşturuluyor (bkz. [NotificationChannels]) ve Android 8+'da
 * bir kanalın sesi oluşturulduktan sonra kod ile değiştirilemiyor. Bu yüzden
 * zil sesini uygulamanın kendisi çalar: davranış SDK/kanal ayarından bağımsız
 * olur, cevaplama/kapatma anında da kesin biçimde susturulabilir.
 *
 * Cihaz sessiz veya titreşim modundaysa çalınmaz (titreşim bildirim kanalından
 * gelir).
 */
object IncomingCallRinger {
    private const val TAG = "IncomingCallRinger"

    private var player: MediaPlayer? = null

    @Synchronized
    fun start(context: Context) {
        stop()
        try {
            val audioManager =
                context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null &&
                audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL
            ) {
                // Sessiz / titreşim modu: kullanıcının tercihine dokunma.
                return
            }

            val uri: Uri = RingtoneManager
                .getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: return

            player = MediaPlayer().apply {
                setDataSource(context, uri)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                isLooping = true
                setOnErrorListener { _, what, extra ->
                    Log.w(TAG, "Zil sesi hatasi: what=$what extra=$extra")
                    stop()
                    true
                }
                prepare()
                start()
            }
        } catch (error: Exception) {
            Log.w(TAG, "Zil sesi baslatilamadi", error)
            stop()
        }
    }

    @Synchronized
    fun stop() {
        val current = player ?: return
        player = null
        try {
            if (current.isPlaying) current.stop()
        } catch (_: Exception) {
        }
        try {
            current.release()
        } catch (_: Exception) {
        }
    }
}
