package org.abtollc.voip.abto_voip_sdk

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** AbtoVoipSdkPlugin */
class AbtoVoipSdkPlugin: FlutterPlugin {

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    flutterPluginBinding
      .getPlatformViewRegistry().apply {
        registerViewFactory("out_video", VideoViewFactory(true))
        registerViewFactory("inc_video", VideoViewFactory(false))
      }

    SipWrapper.getInstance().setup(flutterPluginBinding)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    SipWrapper.getInstance().clear()
  }
}
