package org.abtollc.voip.abto_voip_sdk

import android.os.Bundle

import androidx.appcompat.app.AppCompatActivity

import org.abtollc.utils.Log

/** GetPermissionsActivity */
class GetPermissionsActivity : AppCompatActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    org.abtollc.utils.Log.d("DEBUG_SIP_WRAPPER", "request2")
    PermissionUtil.grantedCallback = { this.finish() }
    PermissionUtil.deniedCallback = { this.finish() }
    PermissionUtil.request(this, *PermissionUtil.permissions)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<String?>,
    grantResults: IntArray
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    PermissionUtil.onRequestPermissionsResult(requestCode, grantResults)
  }
}
