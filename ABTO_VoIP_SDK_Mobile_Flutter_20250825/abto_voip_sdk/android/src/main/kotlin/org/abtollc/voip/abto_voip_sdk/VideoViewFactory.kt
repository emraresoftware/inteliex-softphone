package org.abtollc.voip.abto_voip_sdk

import android.content.Context
import android.util.AttributeSet
import android.util.Log
import android.view.SurfaceView
import android.view.View

import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class VideoViewFactory(private val isOut: Boolean) :
  PlatformViewFactory(StandardMessageCodec.INSTANCE) {

  override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
    return NativeView(context, isOut)
  }

  internal class NativeView(context: Context?, isOut: Boolean) :
    PlatformView {

    val surfaceView = VoipSurfaceView(context)

    init {
      surfaceView.isOut = isOut
    }

    override fun getView(): View? = surfaceView

    override fun dispose() {
    }
  }

  class VoipSurfaceView : SurfaceView {
    var isOut: Boolean = false

    constructor(context: Context?) : super(context)

    constructor(context: Context?, attrs: AttributeSet?) : super(
      context,
      attrs
    )

    constructor(
      context: Context?,
      attrs: AttributeSet?,
      defStyleAttr: Int
    ) : super(context, attrs, defStyleAttr)

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
      super.onSizeChanged(w, h, oldw, oldh)
      Log.d("debug_sc", "old: $oldw, $oldh; new: $w, $h")
      if (isOut) {
        SipWrapper.getInstance().setupOutVideo(this)
      } else {
        SipWrapper.getInstance().setupIncVideo(this)
      }
    }
  }
}
