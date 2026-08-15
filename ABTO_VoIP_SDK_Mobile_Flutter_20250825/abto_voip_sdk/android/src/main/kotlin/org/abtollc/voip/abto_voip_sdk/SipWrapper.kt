package org.abtollc.voip.abto_voip_sdk

import android.content.Context
import android.content.Intent
import android.os.Environment
import android.os.RemoteException
import android.util.Log
import android.view.SurfaceView
import android.widget.Toast

import org.abtollc.api.SipMessage
import org.abtollc.sdk.AbtoApplication
import org.abtollc.sdk.AbtoApplicationInterface
import org.abtollc.sdk.AbtoPhone
import org.abtollc.sdk.AbtoPhoneCfg
import org.abtollc.sdk.OnCallDisconnectedListener

import org.abtollc.sdk.OnCallHeldListener.HoldState
import org.abtollc.sdk.OnCallTransferListener
import org.abtollc.sdk.OnIncomingCallListener
import org.abtollc.sdk.OnInitializeListener
import org.abtollc.sdk.OnRegistrationListener
import org.abtollc.utils.codec.Codec

import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Random

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal operator fun <T> List<T>.component6(): T = get(5)
internal operator fun <T> List<T>.component7(): T = get(6)

private object MSG {

  // Events
  val EVENT_INIT_LICENSE = "initLicense"
  val EVENT_REGISTER = "register"
  val EVENT_UNREGISTER = "unregister"

  val EVENT_START_AUDIO_CALL = "startAudioCall"
  val EVENT_START_VIDEO_CALL = "startVideoCall"
  val EVENT_END_CALL = "endCall"
  val EVENT_PICK_UP_CALL = "pickUpCall"
  val EVENT_HANG_UP_CALL = "hangUpCall"
  val EVENT_REJECT_CALL = "rejectCall"

  val EVENT_ENABLE_SPEAKER = "enableSpeaker"
  val EVENT_HOLD = "hold"
  val EVENT_MUTE = "mute"
  val EVENT_START_RECORD = "startRecord"
  val EVENT_STOP_RECORD = "stopRecord"
  val EVENT_TRANSFER = "transfer"

  val EVENT_SEND_TEXT = "sendText"

  val EVENT_LIB_VERSION = "libVersion"
  val EVENT_GET_CONFIGS = "getConfigs"
  val EVENT_SET_CONFIGS = "setConfigs"
  val EVENT_SET_LOG_LEVEL = "setLogLevel"
  val EVENT_SET_SENDING_RTP_AUDIO = "setSendingRtpAudio"
  val EVENT_SET_SENDING_RTP_VIDEO = "setSendingRtpVideo"

  val EVENT_SEND_DTMF = "sendDtmf"
  val EVENT_MUTE_LOCAL_VIDEO = "muteLocalVideo"

  // Results
  val RESULT_REGISTERED = "registered"
  val RESULT_UNREGISTERED = "unregistered"
  val RESULT_REG_FAILED = "registration_failed"

  val RESULT_CALL_CONNECTED = "call_connected"
  val RESULT_CALL_DISCONNECTED = "call_disconnected"

  val RESULT_ON_HOLD_STATE = "on_hold_state"
  val RESULT_ACTIVE = "active"
  val RESULT_LOCAL_HOLD = "local_hold"
  val RESULT_REMOTE_HOLD = "remote_hold"

  val RESULT_INCOMING_CALL = "incoming_call"

  val RESULT_MSG_RECEIVED = "message_received"
  val RESULT_MSG_STATUS = "message_status"

  val RESULT_DTMF_RECEIVED = "dtmf_received"
}

/** SipWrapper */
class SipWrapper : MethodChannel.MethodCallHandler {
  private var channel: MethodChannel? = null
  private var phone: AbtoPhone? = null

  private var isCallConnected: Boolean = false
  private var isIncomingCall: Boolean = false
  private var callId: Int = -1
  private var recordFilePath: String? = null
  private var context: Context? = null
  private var outVideo: SurfaceView? = null
  private var incVideo: SurfaceView? = null
  // `cfg.addAccount()` her çağrıda yeni bir native hesap oluşturur. Flutter
  // yeniden kayıt istediğinde aynı hesabı tekrar eklemek, currentAccountId'nin
  // sürekli değişmesine ve çağrıların yanlış native hesapla başlamasına neden
  // olur. Aynı yapılandırmayı bir kez ekleyip sonraki denemelerde yalnızca
  // register() çağırıyoruz.
  private var activeAccountFingerprint: String? = null

  fun setup(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    phone = (context as AbtoApplicationInterface).abtoPhone
    initAbtoPhone()

    channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME).apply {
      setMethodCallHandler(this@SipWrapper)
    }
  }

  fun clear() {
    channel?.setMethodCallHandler(null)
    channel = null
    context = null
    phone = null
    activeAccountFingerprint = null
  }

  private fun initAbtoPhone() {
    val context = context ?: return
    val phone = phone ?: return

    val cfg = phone.config

    val sipPortValue = Random().nextInt(64535) + 1000
    cfg.sipPort = sipPortValue

    for (c in Codec.values()) {
      when (c) {
        Codec.PCMU -> cfg.setCodecPriority(c, 250.toShort())
        Codec.PCMA -> cfg.setCodecPriority(c, 249.toShort())
        Codec.G729 -> cfg.setCodecPriority(c, 248.toShort())
        Codec.GSM -> cfg.setCodecPriority(c, 247.toShort())
        Codec.H264 -> cfg.setCodecPriority(c, 220.toShort())
        Codec.VP8 -> cfg.setCodecPriority(c, 210.toShort())
        Codec.G723 -> cfg.setCodecPriority(c, 200.toShort())
        else -> cfg.setCodecPriority(c, 0.toShort())
      }
    }

    cfg.setSignallingTransport(AbtoPhoneCfg.SignalingTransportType.UDP)

    AbtoPhoneCfg.setLogLevel(7, true)

    cfg.hangupTimeout = HANGUP_TIMEOUT
    cfg.registerTimeout = REGISTER_TIMEOUT

    cfg.isSTUNEnabled = false
    cfg.stunServer = ""
    cfg.isICEEnabled = false
    
    cfg.isTLSVerifyServer = false

    if (!PermissionUtil.checkPermissions(context, *PermissionUtil.permissions)) {
      context.startActivity(
        Intent(context, GetPermissionsActivity::class.java)
          .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      )
    }

    phone.setInitializeListener { state: OnInitializeListener.InitializeState, s: String ->
      Log.d("DEBUG_SIP_WRAPPER", "setInitializeListener: $state, $s")
    }

    phone.setRegistrationStateListener(object : OnRegistrationListener {
      override fun onRegistered(accId: Long) {
        Log.d("DEBUG_SIP_WRAPPER", "onRegistered")
        channel?.invokeMethod(MSG.RESULT_REGISTERED, null)
      }

      override fun onUnRegistered(p0: Long) {
        Log.d("DEBUG_SIP_WRAPPER", "onUnRegistered")
        channel?.invokeMethod(MSG.RESULT_UNREGISTERED, null)
      }

      override fun onRegistrationFailed(accId: Long, statusCode: Int, statusMsg: String) {
        if (statusCode == 100) return
        // ABTO bazi surumlerde basarili kayittan sonra accId=-1 ile sahte hata uretir.
        if (accId < 0) return
        Log.d(
          "DEBUG_SIP_WRAPPER",
          "onRegistrationFailed: ${accId}, ${statusCode}, ${statusMsg}"
        )
        channel?.invokeMethod(
          MSG.RESULT_REG_FAILED,
          mapOf(
            "statusCode" to statusCode,
            "statusText" to statusMsg,
          ),
        )
      }
    })

    phone.setCallConnectedListener { callId: Int, contact: String? ->
      /*Log.d("DEBUG_SIP_WRAPPER", "onCallConnected outVideoLay: " + (outVideoLay != null)
      + ", inVideoLay: " + (inVideoLay != null) + ", callId: " + callId);*/
      isCallConnected = true
      this@SipWrapper.callId = callId

      //  phone.setVideoWindows(callId, outVideoLay, inVideoLay);

      //  outVideoLay.setZOrderOnTop(true);
      //  outVideoLay.setZOrderMediaOverlay(true);
      channel?.invokeMethod(MSG.RESULT_CALL_CONNECTED, contact)
    }

    phone.setCallDisconnectedListener(OnCallDisconnectedListener { callId: Int, remoteContact: String, statusCode: Int, msg: String ->
      Log.d("DEBUG_SIP_WRAPPER", "onCallDisconnected")
      if (this@SipWrapper.callId != callId) return@OnCallDisconnectedListener
      this@SipWrapper.callId = -1
      this@SipWrapper.isCallConnected = false
      phone.setVideoWindows(callId, null as SurfaceView?, null)
      channel?.invokeMethod(MSG.RESULT_CALL_DISCONNECTED, null)
    })

//    phone.setCallErrorListener(OnCallErrorListener { remoteContact: String, statusCode: Int, msg: String ->
//      Log.d("DEBUG_SIP_WRAPPER", "onCallError")
//      isCallConnected = false
//      phone.setVideoWindows(callId, null as SurfaceView?, null)
//      channel?.invokeMethod(MSG.RESULT_CALL_DISCONNECTED, null)
//    })

    phone.setOnCallHeldListener { callId: Int, holdState: HoldState ->
      val holdStateValue: String? = when (holdState) {
        HoldState.ACTIVE -> {
          MSG.RESULT_ACTIVE
        }

        HoldState.LOCAL_HOLD -> {
          MSG.RESULT_LOCAL_HOLD
        }

        HoldState.REMOTE_HOLD -> {
          MSG.RESULT_REMOTE_HOLD
        }

        else -> null
      }

      if (holdStateValue != null) {
        channel?.invokeMethod(MSG.RESULT_ON_HOLD_STATE, holdStateValue)
      }
    }

    phone.setCallTransferListener(object : OnCallTransferListener {
      override fun onCallTransferRequest(i: Int, s: String) {
      }

      override fun onCallTransferState(i: Int, statusCode: Int, s: String) {
        if (statusCode == 200) {
          try {
            phone.hangUp(callId)
            Log.d("DEBUG_SIP_WRAPPER", "hangUp")
          } catch (e: RemoteException) {
            e.printStackTrace()
          }
        }
      }
    })

    phone.setIncomingCallListener(OnIncomingCallListener { callId: Int, remoteContact: String?, l: Long ->
      if (callId == -1) {
        // ignore such events
        return@OnIncomingCallListener
      }

      this@SipWrapper.callId = callId
      val isVideoCall = phone.isVideoCall(callId)

      this@SipWrapper.isIncomingCall = true

      val list = listOf(
        remoteContact,
        isVideoCall.toString()
      )
      channel?.invokeMethod(MSG.RESULT_INCOMING_CALL, list)
    })

    phone.setInMessageListener { message: String?, remoteContact: String?, accId: String? ->
      val localContact = accId ?: ""
      val list = listOf(
        remoteContact,
        localContact,
        message
      )
      channel?.invokeMethod(MSG.RESULT_MSG_RECEIVED, list)
    }

    phone.setTextMessageStatusListener { message: SipMessage ->
      val error = message.errorContent
      val list = listOf(
        message.remoteNumber,
        error ?: "OK",
        ((message.getStatus() / 100) as Int == 2).toString()
      )
      channel?.invokeMethod(MSG.RESULT_MSG_STATUS, list)
    }

    phone.setToneReceivedListener { callId: Int, tone: Char ->
      channel?.invokeMethod(
        MSG.RESULT_DTMF_RECEIVED, tone.toString()
      )
    }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val phone = phone ?: return
    val method = call.method
    val arguments: Any = call.arguments ?: Unit

    when (method) {
      MSG.EVENT_LIB_VERSION -> {
        Log.d("DEBUG_SIP_WRAPPER", "libVersion")
        result.success(AbtoApplication.BUILD)
        return
      }

      MSG.EVENT_GET_CONFIGS -> {
        Log.d("DEBUG_SIP_WRAPPER", method)
        result.success(buildConfigsMap())
        return
      }

      MSG.EVENT_SET_CONFIGS -> {
        Log.d("DEBUG_SIP_WRAPPER", method)
        val map = arguments as Map<String, Any>
        applyConfigs(map)
        return
      }

      MSG.EVENT_INIT_LICENSE -> {
        Log.d("DEBUG_SIP_WRAPPER", "initLicense")
        val array = arguments as List<String>
        val (licUserId, licKey) = array
        val cfg = phone.config
        cfg.licenseUserId = licUserId
        cfg.licenseKey = licKey
      }

      MSG.EVENT_REGISTER -> {
        val array = arguments as List<String>
        val cfg = phone.config
        val (domain, proxy, user, pass, authId, displayName, expire) = array
        val fingerprint = listOf(
          domain,
          proxy,
          user,
          pass,
          authId,
          displayName,
          expire
        ).joinToString(separator = "\u0000")

        if (activeAccountFingerprint != fingerprint) {
          cfg.addAccount(
            domain,
            proxy,
            user,
            pass,
            authId,
            displayName,
            expire.toInt(),
            false
          )
          activeAccountFingerprint = fingerprint
        } else {
          Log.d(
            "DEBUG_SIP_WRAPPER",
            "EVENT_REGISTER: reusing current native account for $user"
          )
        }

        if (phone.isActive) {
          phone.register()
        } else {
          phone.initializeForeground(null)
        }
      }

      MSG.EVENT_UNREGISTER -> {
        try {
          phone.unregister()
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_START_AUDIO_CALL -> {
        this.isIncomingCall = false
        val number = arguments as String
        Log.d("DEBUG_SIP_WRAPPER", "EVENT_START_AUDIO_CALL: $number")
        try {
          callId = phone.startCall(number, phone.currentAccountId)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_START_VIDEO_CALL -> {
        this.isIncomingCall = false
        val number = arguments as String
        Log.d("DEBUG_SIP_WRAPPER", "EVENT_START_VIDEO_CALL: $number")
        try {
          callId = phone.startVideoCall(number, phone.currentAccountId)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_END_CALL -> {
        Log.d(
          "DEBUG_SIP_WRAPPER", "EVENT_END_CALL: " +
                  "isIncomingCall: $isIncomingCall, " +
                  "isCallConnected: $isCallConnected, " +
                  "callId: $callId"
        )
        if (isIncomingCall && !isCallConnected) {
          try {
            phone.rejectCall(callId)
            Log.d("DEBUG_SIP_WRAPPER", "rejectCall")
          } catch (e: RemoteException) {
            e.printStackTrace()
          }
        } else {
          try {
            phone.hangUp(callId)
            Log.d("DEBUG_SIP_WRAPPER", "hangUp")
          } catch (e: RemoteException) {
            e.printStackTrace()
          }
        }
      }

      MSG.EVENT_HANG_UP_CALL -> {
        try {
          val status = arguments as Int
          phone.hangUp(callId, status)
          Log.d("DEBUG_SIP_WRAPPER", "hangUp")
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_REJECT_CALL -> {
        try {
          phone.rejectCall(callId)
          Log.d("DEBUG_SIP_WRAPPER", "reject")
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_PICK_UP_CALL -> {
        val isVideo = arguments as Boolean
        Log.d("DEBUG_SIP_WRAPPER", "EVENT_PICK_UP_CALL: $isVideo")
        answerCall(callId, isVideo)
      }

      MSG.EVENT_ENABLE_SPEAKER -> {
        val enableSpeaker = arguments as Boolean
        Log.d("DEBUG_SIP_WRAPPER", "EVENT_ENABLE_SPEAKER: $enableSpeaker")
        try {
          phone.setSpeakerphoneOn(enableSpeaker)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_HOLD -> {
        Log.d("DEBUG_SIP_WRAPPER", "EVENT_HOLD")
        try {
          phone.holdRetriveCall(callId)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_MUTE -> {
        val mute = arguments as Boolean
        Log.d("DEBUG_SIP_WRAPPER", "EVENT_MUTE: $mute")
        try {
          phone.setMicrophoneMute(mute)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_START_RECORD -> {
        Log.d("DEBUG_SIP_WRAPPER", "EVENT_START_RECORD")
        recordFilePath = (Environment.getExternalStoragePublicDirectory(
          Environment.DIRECTORY_DOWNLOADS
        )
          .toString() + File.separator + "audio "
                + SimpleDateFormat("MMMM dd, yyyy HH_mm_ss", Locale.ENGLISH)
          .format(Date())
                + ".wav")
        try {
          phone.startRecording(callId, recordFilePath)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_STOP_RECORD -> {
        try {
          phone.stopRecording(callId)
          Toast.makeText(context, "Audio saved to: $recordFilePath", Toast.LENGTH_LONG).show()
          recordFilePath = null
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_TRANSFER -> {
        val number = arguments as String
        phone.callXfer(callId, number)
      }

      MSG.EVENT_SEND_TEXT -> {
        val array = arguments as List<String>
        val (number, msg) = array
        try {
          phone.sendTextMessage(phone.currentAccountId, msg, number)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_SET_LOG_LEVEL -> {
        val array = arguments as List<Int>
        val (level, toFile) = array
        AbtoPhoneCfg.setLogLevel(level, toFile == 1)
      }

      MSG.EVENT_SET_SENDING_RTP_VIDEO -> {
        val enable = arguments as Boolean
        try {
          phone.setSendingRtpVideo(callId, enable)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_SET_SENDING_RTP_AUDIO -> {
        val enable = arguments as Boolean
        try {
          Log.d("DEBUG_SIP_WRAPPER", "setSendingRtpAudio: callId=$callId enable=$enable")
          phone.setSendingRtpAudio(callId, enable)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_SEND_DTMF -> {
        val dtmf = arguments as String
        try {
          phone.sendTone(callId, dtmf[0])
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }

      MSG.EVENT_MUTE_LOCAL_VIDEO -> {
        val mute = arguments as Boolean
        try {
          phone.muteLocalVideo(callId, mute)
        } catch (e: RemoteException) {
          e.printStackTrace()
        }
      }
    }
    result.success(null)
  }

  fun answerCall(callId: Int, isVideo: Boolean) {
    try {
      phone?.answerCall(callId, 200, isVideo)
    } catch (e: RemoteException) {
      e.printStackTrace()
    }
  }

  fun setupOutVideo(surfaceView: SurfaceView?) {
    this.outVideo = surfaceView
    setupVideo()
  }

  fun setupIncVideo(surfaceView: SurfaceView?) {
    this.incVideo = surfaceView
    setupVideo()
  }

  private fun setupVideo() {
    if (outVideo != null && incVideo != null) {
      phone?.setVideoWindows(callId, outVideo, incVideo)
    } else {
      phone?.setVideoWindows(callId, null as SurfaceView?, null)
    }
  }

  private fun buildConfigsMap(): Map<String, Any> {
    val cfg = phone?.config ?: return mapOf()

    val map = mapOf<String, Any>(
      "isSTUNEnabled" to cfg.isSTUNEnabled,
      "STUNServer" to cfg.stunServer,
      "SipPort" to cfg.sipPort,
      "SignalingTransport" to cfg.signalingTransport.value,
      "ICEEnabled" to cfg.isICEEnabled,
      "KeepAliveInterval" to cfg.getKeepAliveInterval(cfg.signalingTransport),
      "InviteTimeout" to cfg.inviteTimeout,
      "HangupTimeout" to cfg.hangupTimeout,
      "RegisterTimeout" to cfg.registerTimeout,
      "isUseSRTP" to cfg.isUseSRTP,
      "isEnabledAutoSendRtpVideo" to cfg.isEnabledAutoSendRtpVideo,
      "audioCodecs" to CodecsUtils.codecsString(cfg, false),
      "videoCodecs" to CodecsUtils.codecsString(cfg, true)
    )

    return map
  }

  private fun applyConfigs(map: Map<String, Any>) {
    try {
      val cfg = phone?.config ?: return
      cfg.isSTUNEnabled = map["isSTUNEnabled"] as Boolean
      cfg.stunServer = if (cfg.isSTUNEnabled) map["STUNServer"] as String? else ""
      cfg.sipPort = map["SipPort"] as Int
      cfg.setSignallingTransport(
        AbtoPhoneCfg.SignalingTransportType.getTypeByValue(
          map["SignalingTransport"] as Int
        )
      )
      cfg.isICEEnabled = map["ICEEnabled"] as Boolean
      cfg.setKeepAliveInterval(cfg.signalingTransport, map["KeepAliveInterval"] as Int)
      cfg.inviteTimeout = map["InviteTimeout"] as Int
      cfg.hangupTimeout = map["HangupTimeout"] as Int
      cfg.registerTimeout = map["RegisterTimeout"] as Int
      cfg.isUseSRTP = map["isUseSRTP"] as Boolean
      // Audio RTP must not be controlled by the video auto-send setting.
      // The Flutter config keeps video disabled for audio-only calls, which
      // previously disabled microphone RTP every time configs were applied.
      cfg.setEnableAutoSendRtpAudio(true)
      CodecsUtils.applyCodecs(cfg, map["audioCodecs"] as String)
      CodecsUtils.applyCodecs(cfg, map["videoCodecs"] as String)
    } catch (e: java.lang.Exception) {
      e.printStackTrace()
    }
  }

  companion object {
    @Volatile private var instance: SipWrapper? = null // Volatile modifier is necessary

    fun getInstance() =
      instance ?: synchronized(this) { // synchronized to avoid concurrency problem
        instance ?: SipWrapper().also { instance = it }
      }

    private const val DEFAULT_TIMEOUT = 300
    private const val REGISTER_TIMEOUT = 15000
    private const val HANGUP_TIMEOUT = 3000

    private val CHANNEL_NAME = "com.voip.sdk.channel"
  }
}
