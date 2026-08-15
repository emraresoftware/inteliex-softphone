package com.example.inteliex_softphone

import android.content.Intent
import android.os.Build
import android.os.Bundle
import com.siprix.voip_sdk.CallNotifService
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingNotificationAccept = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureNotificationAcceptIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureNotificationAcceptIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "inteliex_softphone/foreground",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title")
                    val text = call.argument<String>("text")
                    SipForegroundService.start(applicationContext, title, text)
                    result.success(true)
                }
                "stop" -> {
                    SipForegroundService.stop(applicationContext)
                    result.success(true)
                }
                "getFcmToken" -> {
                    val cached = PushTokenStore.getToken(applicationContext)
                    if (!cached.isNullOrBlank()) {
                        result.success(cached)
                        return@setMethodCallHandler
                    }

                    FirebaseMessaging.getInstance().token
                        .addOnSuccessListener { token ->
                            if (!token.isNullOrBlank()) {
                                PushTokenStore.saveToken(applicationContext, token)
                            }
                            result.success(token)
                        }
                        .addOnFailureListener { error ->
                            result.error("fcm-token-error", error.message, null)
                        }
                }
                "getDeviceProfile" -> {
                    val isEmulator = Build.FINGERPRINT.startsWith("generic") ||
                        Build.FINGERPRINT.contains("emulator", ignoreCase = true) ||
                        Build.MODEL.contains("Emulator", ignoreCase = true) ||
                        Build.MODEL.contains("sdk", ignoreCase = true) ||
                        Build.PRODUCT.contains("sdk", ignoreCase = true)

                    result.success(if (isEmulator) "emulator" else "physical")
                }
                "consumePendingNotifAccept" -> {
                    val consume = pendingNotificationAccept
                    pendingNotificationAccept = false
                    result.success(consume)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun captureNotificationAcceptIntent(intent: Intent?) {
        val action = intent?.action ?: return
        if (action == CallNotifService.kActionIncomingCallAccept) {
            pendingNotificationAccept = true
        }
    }
}
