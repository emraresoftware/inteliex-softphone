package org.abtollc.voip.abto_voip_sdk

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

import androidx.core.app.ActivityCompat
import androidx.fragment.app.Fragment

typealias ResultCallback = () -> Unit

/** PermissionUtil */
object PermissionUtil {
  var permissions = arrayOf<String>(
    android.Manifest.permission.READ_PHONE_STATE,
    android.Manifest.permission.USE_SIP,  //   Manifest.permission.READ_CONTACTS,
    android.Manifest.permission.RECORD_AUDIO,  //   Manifest.permission.WRITE_EXTERNAL_STORAGE,
    android.Manifest.permission.CAMERA
  )

  fun checkPermissions(context: Context, vararg keys: String): Boolean {
    for (key in keys) {
      if (ActivityCompat.checkSelfPermission(context, key) != PackageManager.PERMISSION_GRANTED) {
        return false
      }
    }
    return true
  }


  private const val REQUEST_CODE: Int = 121
  var grantedCallback: ResultCallback? = null
  var deniedCallback: ResultCallback? = null

  fun request(activity: Activity, vararg keys: String) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      activity.requestPermissions(keys, REQUEST_CODE)
    }
  }

  fun request(fragment: Fragment, vararg keys: String) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      fragment.requestPermissions(keys, REQUEST_CODE)
    }
  }

  fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
    if (requestCode == REQUEST_CODE) {
      for (grantResult: Int in grantResults) {
        if (grantResult == -1) {
          deniedCallback?.invoke()
          clearCallbacks()
          return
        }
      }
    }
    grantedCallback?.invoke()
    clearCallbacks()
  }

  fun isAppCanRequestPermissions(activity: Activity, vararg keys: String): Boolean {
    var allowed = true
    for (key in keys) {
      if (!ActivityCompat.shouldShowRequestPermissionRationale(activity, key)) {
        allowed = false
        break
      }
    }
    return allowed
  }

  private fun clearCallbacks() {
    grantedCallback = null
    deniedCallback = null
  }
}
