package org.abtollc.voip.abto_voip_sdk

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.RemoteException

import org.abtollc.api.SipUri
import org.abtollc.sdk.AbtoPhone
import org.abtollc.utils.Compatibility

class AbtoCallEventsReceiver(context: Context, isMainProcess: Boolean) : BroadcastReceiver() {
    constructor() : this(
        AbtoFlutterNotificationApplication.getApp().applicationContext,
        AbtoFlutterNotificationApplication.getApp().isMainProcess()
    )

    private val handler: Handler = Handler(Looper.getMainLooper())
    private val isMainProcess: Boolean
    private val isSplitMode: Boolean

    override fun onReceive(context: Context, intent: Intent) {
        val bundle = intent.extras ?: return
        val app = AbtoFlutterNotificationApplication.getApp()

        if (bundle.getBoolean(AbtoPhone.IS_INCOMING, false)) {
            if (!isSplitMode) {
                if (!buildIncomingCallIntent(context, bundle)) {
                    buildIncomingCallNotification(context, bundle)
                }
                return
            }

            // Incoming call
            if (isMainProcess) {
                buildIncomingCallIntent(context, bundle)
            } else {
                val phone = app.abtoPhone
                if (!phone.isActive) {
                    phone.initializeForeground(null)
                }
                buildIncomingCallNotification(context, bundle)
            }
        } else if (bundle.getBoolean(KEY_PICK_UP_AUDIO, false) ||
            bundle.getBoolean(KEY_PICK_UP_VIDEO, false)) {
            if (isSplitMode && isMainProcess) {
                return
            }
            val phone = app.abtoPhone

            if (!phone.isActive) {
                handler.postDelayed({
                    onReceive(context, intent)
                }, EVENT_RESEND_DELAY)
                return
            }

            val callId = bundle.getInt(AbtoPhone.CALL_ID, AbtoPhone.INVALID_CALL_ID)
            if (callId == AbtoPhone.INVALID_CALL_ID) {
                return
            }
            cancelIncCallNotification(context, callId)
            try {
                val answerVideoCall = bundle.getBoolean(KEY_PICK_UP_VIDEO, false)
                phone.answerCall(callId, 200, answerVideoCall)
            } catch (e: RemoteException) {
                e.printStackTrace()
            }
        } else if (bundle.getBoolean(KEY_REJECT_CALL, false)) {
            if (isSplitMode && isMainProcess) {
                return
            }
            val phone = app.abtoPhone

            if (!phone.isActive) {
                handler.postDelayed({
                    onReceive(context, intent)
                    //                        context.sendBroadcast(intent);
                }, EVENT_RESEND_DELAY)
                return
            }

            // Reject call
            val callId = bundle.getInt(AbtoPhone.CALL_ID)
            cancelIncCallNotification(context, callId)
            try {
                phone.rejectCall(callId)
            } catch (e: RemoteException) {
                e.printStackTrace()
            }
        } else if (bundle.containsKey(AbtoPhone.CODE)) {
            if (isSplitMode && isMainProcess) {
                return
            }

            // Cancel call
            val callId = bundle.getInt(AbtoPhone.CALL_ID)
            cancelIncCallNotification(context, callId)
        }
    }

    init {
        val userMetadata = getAppMetadata(context)

        this.isSplitMode = getBundleBoolean(
            userMetadata,
            "AbtoVoipCallSplitService",
            getBundleBoolean(userMetadata, "AbtoVoipCallSlitService", false)
        )

        this.isMainProcess = isMainProcess

        org.abtollc.utils.Log.e(
            this.javaClass.canonicalName,
            "AbtoCallEventsReceiver = " + (if (isMainProcess) "local" else "remote")
        )
    }

    private fun getAppMetadata(context: Context): Bundle? {
        try {
            val ai = context.packageManager
                .getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
            return ai.metaData
        } catch (e: PackageManager.NameNotFoundException) {
            // Fallback to default ScreenAV Activity
        }

        return null
    }

    private fun buildIncomingCallIntent(context: Context, bundle: Bundle): Boolean {
        val userMetadata = getAppMetadata(context)
        val intentClass = getBundleString(
            userMetadata,
            "AbtoVoipCallActivity",
            context.packageName + ".MainActivity"
        )

        val intent = Intent(AbtoPhone.ACTION_ABTO_CALL_EVENT).apply {
            setClassName(context, intentClass)
            putExtras(bundle)
        }

        if (!AbtoFlutterNotificationApplication.getApp().isAppInBackground()) {
            // Start activity
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)

            return true
        }

        return false
    }

    @SuppressLint("NewApi")
    private fun buildIncomingCallNotification(context: Context, bundle: Bundle) {
        val userMetadata = getAppMetadata(context)
        val intentClass = getBundleString(
            userMetadata,
            "AbtoVoipCallActivity",
            context.packageName + ".MainActivity"
        )

        val intent = Intent(AbtoPhone.ACTION_ABTO_CALL_EVENT).apply {
            setClassName(context, intentClass)
            putExtras(bundle)
        }

        var appIcon = 0
        var appName: String? = null
        try {
            val app = AbtoFlutterNotificationApplication.getApp()
            val info = app.applicationContext.applicationInfo
            if (info != null) {
                appName = if (info.labelRes != 0) {
                    context.getString(info.labelRes)
                } else {
                    info.nonLocalizedLabel?.takeIf { it.isNotEmpty() }?.toString() ?: info.name
                }
                appIcon = info.icon
            }
        } catch (e: java.lang.Exception) {
//                e.printStackTrace();
        }

        if (appName == null) {
            appName = "ABTO VoIP SDK"
        }

        val isVideoCall =
            bundle.getBoolean(AbtoPhone.HAS_VIDEO, false) && getBundleBoolean(
                userMetadata,
                "AbtoVoipCallSupportVideo",
                true
            )
        val callId = bundle.getInt(AbtoPhone.CALL_ID)

        // Create channel
        if (Compatibility.isCompatible(26) && channelCall == null) {
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager?

            channelCall = NotificationChannel(
                CHANEL_CALL_ID,
                "$appName Call",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = appName
                notificationManager?.createNotificationChannel(this)
            }
        }

        val title: String = if (isVideoCall) {
            getBundleString(
                userMetadata,
                "AbtoVoipCallIncomingVideoTitle",
                "Incoming video call"
            )
        } else {
            getBundleString(userMetadata, "AbtoVoipCallIncomingAudioTitle", "Incoming call")
        }

        val remoteContact = getBundleString(bundle, AbtoPhone.REMOTE_CONTACT, "")
        val userDescription = SipUri.getDisplayedSimpleContact(remoteContact)

        val content = getBundleString(
            userMetadata,
            if (isVideoCall) "AbtoVoipCallIncomingVideoContent" else "AbtoVoipCallIncomingAudioContent",
            "\${INCOMING_DESCRIPTION}"
        ).replace("\\$\\{INCOMING_URI\\}".toRegex(), remoteContact)
            .replace("\\$\\{INCOMING_DESCRIPTION\\}".toRegex(), userDescription)

        // Intent for launch ScreenAV
        val notificationPendingIntent = PendingIntent.getActivity(
            context,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Compatibility.isCompatible(23)) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        // Intent for pickup audio call — Activity hedefli: MainActivity onNewIntent
        // hem çağrıyı cevaplayacak hem de app'i ön plana getirecek.
        // (getBroadcast kullanırsak app öldüyse broadcast handler activity başlatamıyor.)
        val pickUpAudioIntent = Intent().apply {
            setClassName(context, intentClass)
            putExtra(AbtoPhone.CALL_ID, callId)
            putExtra(KEY_PICK_UP_AUDIO, true)
            // processIncomingCall() bu marker'ı bekliyor; aksi halde answerCall'a girmiyor.
            putExtra(AbtoPhone.ABTO_SERVICE_MARKER, true)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
        }
        val pickUpAudioPendingIntent: PendingIntent = PendingIntent.getActivity(
            context,
            2,
            pickUpAudioIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Compatibility.isCompatible(23)) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        // Intent for reject call
        val rejectCallIntent = Intent(AbtoPhone.ACTION_ABTO_CALL_EVENT).apply {
            setPackage(context.packageName)
            putExtra(AbtoPhone.CALL_ID, callId)
            putExtra(KEY_REJECT_CALL, true)
        }

        val pendingRejectCall = PendingIntent.getBroadcast(
            context,
            4,
            rejectCallIntent,
            PendingIntent.FLAG_CANCEL_CURRENT or (if (Compatibility.isCompatible(23)) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val builder = if (Compatibility.isCompatible(26)) {
            Notification.Builder(context, CHANEL_CALL_ID)
        } else {
            Notification.Builder(context)
        }

        if (Compatibility.isCompatible(21)) {
            val notificationColor =
                getBundleInt(userMetadata, "AbtoVoipCallIncomingColor", -0xff0100)
            builder.setColor(notificationColor)
                .setCategory(Notification.CATEGORY_CALL)
                // Kilit ekranında "Cevapla / Reddet" aksiyon butonlarının görünmesi için.
                .setVisibility(Notification.VISIBILITY_PUBLIC)
        }

        val notificationIcon = getBundleInt(userMetadata, "AbtoVoipCallIncomingIcon", appIcon)
        builder.setSmallIcon(notificationIcon)

        builder.setContentTitle(title)
            .setContentText(content)
            .setContentIntent(notificationPendingIntent)
            .setFullScreenIntent(notificationPendingIntent, true)
            .setOngoing(true)
            .apply {
                if (Compatibility.isCompatible(26)) {
                    // TODO: check if this is needed
                } else {
                    setDefaults(Notification.DEFAULT_ALL)
                }
            }

        val notification: Notification

        if (Compatibility.isCompatible(16)) {
            // Style for popup notification
            val bigText = Notification.BigTextStyle().apply {
                bigText(content)
                setBigContentTitle(title)
            }

            val hangupText =
                getBundleString(userMetadata, "AbtoVoipCallIncomingHangupText", "Reddet")
            val hangupIcon = getBundleInt(userMetadata, "AbtoVoipCallIncomingHangupIcon", 0)

            val acceptAudioText =
                getBundleString(userMetadata, "AbtoVoipCallIncomingAcceptAudioText", "Cevapla")
            val acceptAudioIcon =
                getBundleInt(userMetadata, "AbtoVoipCallIncomingAcceptAudioIcon", 0)

            builder.setStyle(bigText)

            if (Compatibility.isCompatible(26)) {
                val hangupAction = Notification.Action.Builder(
                    Icon.createWithResource(context, hangupIcon),
                    hangupText, pendingRejectCall).build()
                builder.addAction(hangupAction)

                val acceptAudioAction = Notification.Action.Builder(
                    Icon.createWithResource(context, acceptAudioIcon),
                    acceptAudioText, pickUpAudioPendingIntent).build()
                builder.addAction(acceptAudioAction)
            } else {
                builder.setPriority(Notification.PRIORITY_MAX)
                    .addAction(hangupIcon, hangupText, pendingRejectCall)
                    .addAction(acceptAudioIcon, acceptAudioText, pickUpAudioPendingIntent)
            }

            if (isVideoCall) {
                val acceptVideoText =
                    getBundleString(userMetadata, "AbtoVoipCallIncomingAcceptVideoText", "Cevapla")
                val acceptVideoIcon =
                    getBundleInt(userMetadata, "AbtoVoipCallIncomingAcceptVideoIcon", 0)

                // Intent for pickup video call
                val pickUpVideoIntent = Intent(AbtoPhone.ACTION_ABTO_CALL_EVENT).apply {
                    setPackage(context.packageName)
                    putExtra(AbtoPhone.CALL_ID, callId)
                    putExtra(KEY_PICK_UP_VIDEO, true)
                }

                val pickUpVideoPendingIntent = PendingIntent.getBroadcast(
                    context,
                    3,
                    pickUpVideoIntent,
                    PendingIntent.FLAG_CANCEL_CURRENT or (if (Compatibility.isCompatible(23)) PendingIntent.FLAG_IMMUTABLE else 0)
                )

                if (Compatibility.isCompatible(26)) {
                    val acceptVideoAction = Notification.Action.Builder(
                        Icon.createWithResource(context, acceptVideoIcon),
                        acceptVideoText, pickUpVideoPendingIntent).build()
                    builder.addAction(acceptVideoAction)
                } else {
                    builder.addAction(acceptVideoIcon, acceptVideoText, pickUpVideoPendingIntent)
                }
            }

            notification = builder.build()
        } else {
            notification = builder.notification
        }

        // Create notification
        val mNotificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        mNotificationManager?.notify(NOTIFICATION_INCOMING_CALL_ID + callId, notification)
    }

    private fun getBundleString(bundle: Bundle?, key: String, defaultValue: String): String {
        return bundle?.getString(key, defaultValue) ?: defaultValue
    }

    private fun getBundleInt(bundle: Bundle?, key: String, defaultValue: Int): Int {
        return bundle?.getInt(key, defaultValue) ?: defaultValue
    }

    private fun getBundleBoolean(bundle: Bundle?, key: String, defaultValue: Boolean): Boolean {
        return bundle?.getBoolean(key, defaultValue) ?: defaultValue
    }

    companion object {
        private const val EVENT_RESEND_DELAY: Long = 50

        const val CHANEL_CALL_ID: String = "abto_phone_call"
        const val KEY_PICK_UP_AUDIO: String = "KEY_PICK_UP_AUDIO"
        const val KEY_PICK_UP_VIDEO: String = "KEY_PICK_UP_VIDEO"
        const val KEY_REJECT_CALL: String = "KEY_REJECT_CALL"

        const val ACTION_ABTO_CALL_EVENT = AbtoPhone.ACTION_ABTO_CALL_EVENT
        const val CALL_EVENT_CODE = AbtoPhone.CODE

        private var channelCall: NotificationChannel? = null
        private const val NOTIFICATION_INCOMING_CALL_ID: Int = 1000

        fun cancelIncCallNotification(context: Context, callId: Int) {
            val mNotificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager?
            mNotificationManager?.cancel(NOTIFICATION_INCOMING_CALL_ID + callId)
        }

        fun processIncomingCall(context: Context, intent: Intent): Boolean {
            val args = intent.extras ?: return false
            val isServiceRequest = args.getBoolean(AbtoPhone.ABTO_SERVICE_MARKER, false)
            val callId = args.getInt(AbtoPhone.CALL_ID, AbtoPhone.INVALID_CALL_ID)

            if (!isServiceRequest || (callId == AbtoPhone.INVALID_CALL_ID)) {
                // TODO: check what should be done in this case
                return false
            }

            cancelIncCallNotification(context, callId)

            val abtoPhone = AbtoFlutterNotificationApplication.getApp().getAbtoPhone()

            val answerAudioCall = args.getBoolean(KEY_PICK_UP_AUDIO, false)
            val answerVidieoCall = args.getBoolean(KEY_PICK_UP_VIDEO, false)

            if (answerAudioCall || answerVidieoCall) {
                abtoPhone.answerCall(callId, 200, answerVidieoCall)
                return true
            }

            return true
        }
    }
}
