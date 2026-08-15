package org.abtollc.voip.abto_voip_sdk

import android.annotation.SuppressLint
import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.app.KeyguardManager
import android.content.ContentProvider
import android.content.Context
import android.content.IntentFilter
import android.os.Build
import android.os.RemoteException
import android.view.WindowManager
import io.flutter.app.FlutterApplication
import org.abtollc.db.DBProvider
import org.abtollc.sdk.AbtoApplicationInterface
import org.abtollc.sdk.AbtoPhone
import org.abtollc.utils.AbtoAppInBackgroundHandler
import org.abtollc.utils.Compatibility

class AbtoFlutterNotificationApplication: Application(), AbtoApplicationInterface {

    private var abtoPhone: AbtoPhone? = null
    private var dbProvider: ContentProvider? = null

    private var abtoCallEventsReceiver: AbtoCallEventsReceiver? = null
    private var abtoAppInBackgroundHandler: AbtoAppInBackgroundHandler? = null

    override fun getContentProvider(): ContentProvider {
        return dbProvider!!
    }

    override fun getAbtoPhone(): AbtoPhone {
        return abtoPhone!!
    }

    override fun onCreate() {
        super.onCreate()

        abtoPhone = AbtoPhone.init(this)
        dbProvider = DBProvider(this).apply {
            onCreate()
        }

        app = this
        abtoCallEventsReceiver = AbtoCallEventsReceiver(applicationContext, isMainProcess())
        if (Compatibility.isCompatible(34)) {
            registerReceiver(
                abtoCallEventsReceiver,
                IntentFilter(AbtoPhone.ACTION_ABTO_CALL_EVENT),
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            registerReceiver(abtoCallEventsReceiver, IntentFilter(AbtoPhone.ACTION_ABTO_CALL_EVENT))
        }

        abtoAppInBackgroundHandler = AbtoAppInBackgroundHandler()
        registerActivityLifecycleCallbacks(abtoAppInBackgroundHandler)
    }

    override fun onTerminate() {
        // Fixed issue for some non-Java applications, like Delphi
        super.onTerminate();
        unregisterReceiver(abtoCallEventsReceiver)
        unregisterActivityLifecycleCallbacks(abtoAppInBackgroundHandler)
        app = null

        try {
            abtoPhone?.destroy()
        } catch (e: RemoteException) {
            // TODO Auto-generated catch block
            e.printStackTrace()
        }
    }

    fun isAppInBackground(): Boolean {
        return abtoAppInBackgroundHandler?.isAppInBackground ?: false
    }

    @SuppressLint("NewApi")
    fun isMainProcess(): Boolean {
//        if (Compatibility.isCompatible(28)) {
//            return getPackageName().equals(Application.getProcessName());
//        }

        return packageName.equals(getProcessNameCompat())
    }

    private fun getProcessNameCompat(): String? {
        val myPid = android.os.Process.myPid()
        val manager =
            getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val infos = manager.runningAppProcesses

        return infos.firstOrNull { it.pid == myPid }?.processName
        // may never return null
    }

    companion object {

        @JvmStatic
        private var app: AbtoFlutterNotificationApplication? = null

        fun getApp() = app!!
    }

}


fun Activity.turnScreenOnAndKeyguardOff() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
        setTurnScreenOn(true)
        with(getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager) {
            requestDismissKeyguard(this@turnScreenOnAndKeyguardOff, null)
        }
        setShowWhenLocked(true)
    } else {
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )

        with(getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                //isKeyguardLocked
                requestDismissKeyguard(this@turnScreenOnAndKeyguardOff, null)
            }
        }
    }
}

fun Activity.turnScreenOffAndKeyguardOn() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
        setShowWhenLocked(false)
        setTurnScreenOn(false)
    } else {
        window.clearFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
    }
}
