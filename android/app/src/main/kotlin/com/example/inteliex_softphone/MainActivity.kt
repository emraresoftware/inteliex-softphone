package com.sesdata.inteliex_softphone

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.content.pm.PackageManager
import android.app.ActivityManager
import android.app.NotificationManager
import android.provider.Settings
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.abtollc.voip.abto_voip_sdk.AbtoCallEventsReceiver
import org.abtollc.voip.abto_voip_sdk.turnScreenOffAndKeyguardOn
import org.abtollc.voip.abto_voip_sdk.turnScreenOnAndKeyguardOff
import androidx.core.app.NotificationManagerCompat

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingSetupPermissionResult: MethodChannel.Result? = null
    private var incomingCallWakeLock: PowerManager.WakeLock? = null
    private var proximityWakeLock: PowerManager.WakeLock? = null

    /// tel:/sip: intent'i ile gelen numara; Flutter tarafi hazir olunca
    /// `consumePendingDialNumber` ile bir kez okunur.
    private var pendingDialNumber: String? = null

    companion object {
        private const val REQUEST_SETUP_PERMISSIONS = 2100
        private const val REQUEST_MICROPHONE_PERMISSION = 2102
    }

    private val callEventReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val bundle = intent.extras ?: return
            when {
                // Kullanıcı bildirimdeki "Cevapla"ya bastı → uygulamayı ön plana getir
                bundle.getBoolean(AbtoCallEventsReceiver.KEY_PICK_UP_AUDIO, false) ||
                bundle.getBoolean(AbtoCallEventsReceiver.KEY_PICK_UP_VIDEO, false) -> {
                    try {
                        val launchIntent = packageManager
                            .getLaunchIntentForPackage(packageName)
                            ?.apply {
                                addFlags(
                                    Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
                                )
                            }
                        if (launchIntent != null) startActivity(launchIntent)
                    } catch (_: Exception) {}
                }
                // Çağrı bitti → ekranı kapat ve kilidi geri al
                bundle.containsKey(AbtoCallEventsReceiver.CALL_EVENT_CODE) -> {
                    turnScreenOffAndKeyguardOn()
                }
            }
        }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ABTO kendi notification channel'ını yaratmadan önce PUBLIC visibility ile
        // yarat ki "Cevapla / Reddet" butonları kilit ekranında görünsün.
        NotificationChannels.ensureAll(applicationContext)

        // ABTO çağrı olayı alıcısını kaydet
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerReceiver(
                callEventReceiver,
                IntentFilter(AbtoCallEventsReceiver.ACTION_ABTO_CALL_EVENT),
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            registerReceiver(callEventReceiver, IntentFilter(AbtoCallEventsReceiver.ACTION_ABTO_CALL_EVENT))
        }

        intent?.let { handleAbtoCallIntent(it) }
        intent?.let { handleDialIntent(it) }
    }

    /// Telefonun "bununla ara" secenegi / tel: baglantisi ile gelen numarayi
    /// yakalar. Cagriyi baslatmaz; numara tuslama ekraninda hazir gelir.
    private fun handleDialIntent(intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_VIEW &&
            action != Intent.ACTION_DIAL &&
            action != Intent.ACTION_CALL
        ) {
            return
        }
        val data = intent.data ?: return
        val scheme = data.scheme?.lowercase() ?: return
        if (scheme != "tel" && scheme != "sip" && scheme != "sips") return
        val raw = data.schemeSpecificPart ?: return
        val number = Uri.decode(raw).substringBefore('@').trim()
        if (number.isEmpty()) return
        pendingDialNumber = number
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(callEventReceiver) } catch (_: Exception) {}
        incomingCallWakeLock?.let {
            if (it.isHeld) it.release()
        }
        incomingCallWakeLock = null
        proximityWakeLock?.let {
            if (it.isHeld) it.release()
        }
        proximityWakeLock = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAbtoCallIntent(intent)
        handleDialIntent(intent)
    }

    private fun handleAbtoCallIntent(intent: Intent) {
        // Notification full-screen intent / "Cevapla" / "Reddet" buradan gelir.
        // Flutter cold-start sırasında onIncomingCall event'ini kaçırırsa
        // Dart side bu store'dan çağrıyı sentezleyebilsin diye önce intent'in
        // call info'sunu SharedPreferences'a yazıyoruz.
        val bundle = intent.extras
        var pendingCall: Triple<Int, String, Boolean>? = null
        if (bundle != null) {
            val callId = bundle.getInt("org.abtollc.sdk.callId", -1).takeIf { it != -1 }
                ?: bundle.getInt("callId", -1)
            val pickUpVideo = bundle.getBoolean(AbtoCallEventsReceiver.KEY_PICK_UP_VIDEO, false)
            // ABTO'nun full-screen intent'i SDK/cihaz sürümüne göre IS_INCOMING
            // alanını taşımayabiliyor. MainActivity'ye geçerli callId ile gelen
            // intent zaten ABTO çağrı akışına aittir; aksi halde uygulama uyanıp
            // yalnızca tuşlama ekranında kalır.
            if (callId != -1) {
                val remoteContact = bundle.getString("org.abtollc.sdk.remoteContact")
                    ?: bundle.getString("remoteContact")
                    ?: ""
                val isVideo = bundle.getBoolean("org.abtollc.sdk.hasVideo", false) || pickUpVideo
                pendingCall = Triple(callId, remoteContact, isVideo)
            }
        }

        val processed = AbtoCallEventsReceiver.processIncomingCall(this, intent)
        // processIncomingCall true ise bu kesin bir ABTO çağrı intent'idir.
        // Marker anahtarının SDK sürümünde farklı adlandırılması durumunda da
        // çağrıyı kaybetmemek için burada son bir güvenli fallback uygula.
        if (pendingCall == null && processed && bundle != null) {
            val callId = bundle.getInt("org.abtollc.sdk.callId", -1).takeIf { it != -1 }
                ?: bundle.getInt("callId", -1)
            if (callId != -1) {
                pendingCall = Triple(
                    callId,
                    bundle.getString("org.abtollc.sdk.remoteContact")
                        ?: bundle.getString("remoteContact")
                        ?: "",
                    bundle.getBoolean("org.abtollc.sdk.hasVideo", false),
                )
            }
        }
        pendingCall?.let { (callId, remoteContact, isVideo) ->
            PendingCallStore.savePending(this, callId, remoteContact, isVideo)
        }

        if (processed) {
            turnScreenOnAndKeyguardOff()
            acquireIncomingCallWakeLock()
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireIncomingCallWakeLock() {
        try {
            val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return
            incomingCallWakeLock?.let { if (it.isHeld) it.release() }
            incomingCallWakeLock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "inteliex:incoming_call",
            ).also { it.acquire(15_000L) } // 15 saniye — cevapla/reddet için yeterli
        } catch (_: Exception) {}
    }

    @Suppress("DEPRECATION")
    private fun setProximityLock(active: Boolean) {
        try {
            val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return
            if (active) {
                if (proximityWakeLock == null) {
                    proximityWakeLock = pm.newWakeLock(
                        PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                        "inteliex:proximity",
                    )
                }
                val wl = proximityWakeLock ?: return
                if (!wl.isHeld) wl.acquire()
            } else {
                proximityWakeLock?.let { if (it.isHeld) it.release() }
            }
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // VoIP köprüsü — tüm yöntemler artık doğrudan ABTO/platform tarafından
        // yönetiliyor; bu kanal sadece Flutter tarafının çökmemesi için burada.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "inteliex_softphone/voip",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize",
                "syncRegistration",
                "reportIncomingCall",
                "reportOutgoingCall",
                "reportCallConnected",
                "reportCallEnded",
                "dispose" -> result.success(null)
                else -> result.notImplemented()
            }
        }

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
                // 2026-08-19: gelen çağrıda telefon çalmıyordu — ABTO bildirim
                // kanalı sessiz oluşturuluyor ve kanal sesi sonradan
                // değiştirilemiyor. Zil sesini uygulama kendisi çalar.
                "startRingtone" -> {
                    IncomingCallRinger.start(applicationContext)
                    result.success(true)
                }
                "stopRingtone" -> {
                    IncomingCallRinger.stop()
                    result.success(true)
                }
                // tel:/sip: intent'i ile gelen numara (bir kez okunur).
                "consumePendingDialNumber" -> {
                    val number = pendingDialNumber
                    pendingDialNumber = null
                    result.success(number)
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
                "consumePushDiagnostics" -> {
                    result.success(PushDiagnosticsStore.consume(applicationContext))
                }
                "getPushEnvironment" -> {
                    val notificationPermission =
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                    val notificationsEnabled =
                        NotificationManagerCompat.from(this).areNotificationsEnabled()
                    val notificationManager =
                        getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                    val callChannelImportance = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        notificationManager
                            .getNotificationChannel(NotificationChannels.ABTO_CALL_CHANNEL_ID)
                            ?.importance ?: NotificationManager.IMPORTANCE_UNSPECIFIED
                    } else {
                        NotificationManager.IMPORTANCE_HIGH
                    }
                    val fallbackChannelImportance = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        notificationManager
                            .getNotificationChannel("inteliex_push_fallback")
                            ?.importance ?: NotificationManager.IMPORTANCE_UNSPECIFIED
                    } else {
                        NotificationManager.IMPORTANCE_HIGH
                    }
                    val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                    val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                    result.success(
                        mapOf(
                            "notificationPermission" to notificationPermission,
                            "notificationsEnabled" to notificationsEnabled,
                            "callChannelImportance" to callChannelImportance,
                            "fallbackChannelImportance" to fallbackChannelImportance,
                            "batteryOptimizationIgnored" to
                                powerManager.isIgnoringBatteryOptimizations(packageName),
                            "backgroundRestricted" to
                                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                                    activityManager.isBackgroundRestricted),
                            "tokenPresent" to
                                !PushTokenStore.getToken(applicationContext).isNullOrBlank(),
                        ),
                    )
                }
                "getDeviceProfile" -> {
                    val isEmulator = Build.FINGERPRINT.startsWith("generic") ||
                        Build.FINGERPRINT.contains("emulator", ignoreCase = true) ||
                        Build.MODEL.contains("Emulator", ignoreCase = true) ||
                        Build.MODEL.contains("sdk", ignoreCase = true) ||
                        Build.PRODUCT.contains("sdk", ignoreCase = true)
                    result.success(if (isEmulator) "emulator" else "physical")
                }
                "getStableDeviceId" -> {
                    val androidId = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ANDROID_ID,
                    )
                    result.success(androidId ?: "")
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER ?: "")
                }
                "setProximityLock" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    setProximityLock(active)
                    result.success(null)
                }
                "consumePendingNotifAccept" -> {
                    result.success(false)
                }
                "consumePendingIncomingCall" -> {
                    result.success(PendingCallStore.consumePending(applicationContext))
                }
                "isNotificationPermissionGranted" -> {
                    val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "isMicrophonePermissionGranted" -> {
                    val granted = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "areRequiredPermissionsGranted" -> {
                    result.success(areAllRequiredPermissionsGranted())
                }
                "ensureRequiredPermissions" -> {
                    if (areAllRequiredPermissionsGranted()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    val missing = missingRequiredPermissions()
                    if (missing.isEmpty()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    pendingSetupPermissionResult = result
                    requestPermissions(missing, REQUEST_SETUP_PERMISSIONS)
                }
                "requestMicrophonePermission" -> {
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        try {
                            pendingPermissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_MICROPHONE_PERMISSION)
                        } catch (_: Exception) {
                            pendingPermissionResult = null
                            result.success(false)
                        }
                    }
                }
                "openNotificationSettings" -> {
                    try {
                        val intent = Intent().apply {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                action = android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS
                                putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                            } else {
                                action = android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                                data = Uri.parse("package:$packageName")
                            }
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(POWER_SERVICE) as? PowerManager
                    result.success(pm?.isIgnoringBatteryOptimizations(packageName) == true)
                }
                "openBatteryOptimizationSettings" -> {
                    result.success(openBatteryOptimizationSettings())
                }
                "openAppPermissionSettings" -> {
                    result.success(openAppPermissionSettings())
                }
                "openOemAutostartSettings" -> {
                    result.success(openOemAutostartSettings())
                }
                "canRequestPackageInstalls" -> {
                    val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(canInstall)
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "getApkPackageInfo" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("invalid-argument", "filePath is null", null)
                        return@setMethodCallHandler
                    }
                    result.success(readApkPackageInfo(filePath))
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val installed = installApk(filePath)
                        result.success(installed)
                    } else {
                        result.error("invalid-argument", "filePath is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQUEST_SETUP_PERMISSIONS -> {
                pendingSetupPermissionResult?.success(areAllRequiredPermissionsGranted())
                pendingSetupPermissionResult = null
            }
            REQUEST_MICROPHONE_PERMISSION -> {
                val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                pendingPermissionResult?.success(granted)
                pendingPermissionResult = null
            }
        }
    }

    private fun requiredRuntimePermissions(): Array<String> {
        val permissions = mutableListOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.CAMERA,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.USE_SIP,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        }
        return permissions.toTypedArray()
    }

    private fun missingRequiredPermissions(): Array<String> {
        return requiredRuntimePermissions().filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }.toTypedArray()
    }

    private fun areAllRequiredPermissionsGranted(): Boolean {
        return missingRequiredPermissions().isEmpty()
    }

    // OnePlus/Oppo HANS pil optimizasyonunu devre disi birakma istegi
    private fun openBatteryOptimizationSettings(): Boolean {
        return try {
            startActivity(
                Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            true
        } catch (_: Exception) { false }
    }

    private fun openAppPermissionSettings(): Boolean {
        return try {
            startActivity(
                Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            true
        } catch (_: Exception) { false }
    }

    private fun openOemAutostartSettings(): Boolean {
        val intents = arrayOf(
            // Xiaomi / MIUI
            Intent().setComponent(android.content.ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")),
            // Oppo / OnePlus (newer ColorOS/OxygenOS)
            Intent().setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")),
            Intent().setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")),
            Intent().setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.FakeActivity")),
            // Oppo / OnePlus (older ColorOS)
            Intent().setComponent(android.content.ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")),
            // Huawei
            Intent().setComponent(android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")),
            Intent().setComponent(android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"))
        )

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (e: Exception) {
                // Try next intent
            }
        }

        // Fallback: Open standard application details settings
        return openAppPermissionSettings()
    }

    private fun readApkPackageInfo(filePath: String): Map<String, Any?>? {
        return try {
            val file = java.io.File(filePath)
            if (!file.exists()) return null

            val archiveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageArchiveInfo(
                    filePath,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageArchiveInfo(filePath, 0)
            } ?: return null

            archiveInfo.applicationInfo?.let { appInfo ->
                appInfo.sourceDir = filePath
                appInfo.publicSourceDir = filePath
            }

            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                archiveInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                archiveInfo.versionCode.toLong()
            }

            mapOf(
                "packageName" to archiveInfo.packageName,
                "versionCode" to versionCode,
                "versionName" to archiveInfo.versionName,
            )
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun installApk(filePath: String): Boolean {
        return try {
            val file = java.io.File(filePath)
            if (!file.exists()) return false

            val context = applicationContext
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(
                    androidx.core.content.FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.fileprovider",
                        file
                    ),
                    "application/vnd.android.package-archive"
                )
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
