package com.example.inteliex_softphone

import androidx.core.app.NotificationCompat
import com.siprix.voip_sdk.CallNotifService

class InteliexCallNotifService : CallNotifService() {
    override fun displayIncomingCallNotification(
        callId: Int,
        accId: Int,
        withVideo: Boolean,
        hdrFrom: String?,
        hdrTo: String?,
    ) {
        val bundle = buildCallBundle(callId, accId, withVideo, hdrFrom, hdrTo)

        val acceptIntent = getIntentActivity(kActionIncomingCallAccept, bundle)

        // Notification body tap also triggers accept flow.
        val contentIntent = acceptIntent

        val builder = NotificationCompat.Builder(this, kCallIncomingChannelId)
            .setSmallIcon(appResources.iconId)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .setFullScreenIntent(contentIntent, true)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setStyle(
                NotificationCompat.CallStyle.forIncomingCall(
                    buildPerson(hdrFrom),
                    getIntentService(kActionIncomingCallReject, bundle),
                    acceptIntent,
                ),
            )

        notifMgr.notify(callId, builder.build())
    }
}
