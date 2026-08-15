package org.abtollc.voip.abto_voip_sdk_example

import android.annotation.SuppressLint
import io.flutter.embedding.android.FlutterActivity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle

import org.abtollc.voip.abto_voip_sdk.AbtoCallEventsReceiver
import org.abtollc.voip.abto_voip_sdk.turnScreenOffAndKeyguardOn
import org.abtollc.voip.abto_voip_sdk.turnScreenOnAndKeyguardOff

class MainActivity: FlutterActivity() {

    private val callEventReceiver = object : BroadcastReceiver() {
        override fun onReceive(contxt: Context, intent: Intent) {
            val bundle = intent.extras ?: return

            // process call end event
            if (bundle.containsKey(AbtoCallEventsReceiver.CALL_EVENT_CODE)) {
                // call ended
                turnScreenOffAndKeyguardOn()
            }
        }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerReceiver(
                callEventReceiver,
                IntentFilter(AbtoCallEventsReceiver.ACTION_ABTO_CALL_EVENT),
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            registerReceiver(callEventReceiver, IntentFilter(AbtoCallEventsReceiver.ACTION_ABTO_CALL_EVENT))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // process ABTO SDK Activity start
        if (AbtoCallEventsReceiver.processIncomingCall(this, intent)) {
            turnScreenOnAndKeyguardOff()
        }
    }
}
