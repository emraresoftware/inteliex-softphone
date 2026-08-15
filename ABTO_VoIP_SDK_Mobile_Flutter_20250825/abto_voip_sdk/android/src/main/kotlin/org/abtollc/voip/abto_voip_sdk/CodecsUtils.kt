package org.abtollc.voip.abto_voip_sdk

import java.lang.StringBuilder
import org.abtollc.sdk.AbtoPhoneCfg
import org.abtollc.utils.codec.Codec

object CodecsUtils {

  private fun getCodecs(isVideo: Boolean): List<Codec> {
    val codecs = if (isVideo) {
      listOf(
        Codec.H263, Codec.H264, Codec.VP8
      )
    } else {
      listOf(
        Codec.GSM, Codec.PCMA, Codec.PCMU,
        Codec.ILBC, Codec.speex_8000, Codec.G729,
        Codec.G722, Codec.G7221_16000, Codec.G723,
        Codec.SILK_8000, Codec.OPUS,
      )
    }

    return codecs
  }

  private fun getName(codec: Codec): String {
    when (codec) {
      Codec.H263 -> return "H263"
      Codec.H264 -> return "H264"
      Codec.VP8 -> return "VP8"
      Codec.GSM -> return "GSM"
      Codec.PCMA -> return "PCMA"
      Codec.PCMU -> return "PCMU"
      Codec.ILBC -> return "ILBC"
      Codec.speex_8000 -> return "SPEEDX"
      Codec.G729 -> return "G729"
      Codec.G722 -> return "G722"
      Codec.G7221_16000 -> return "G722_1"
      Codec.G723 -> return "G723"
      Codec.SILK_8000 -> return "SILK"
      Codec.OPUS -> return "OPUS"
      else -> return ""
    }
  }

  private fun getCodecByName(name: String): Codec {
    val codeList = Codec.values()
    for (codec in codeList) {
      if (getName(codec) == name) return codec
    }
    return codeList[0]
  }

  fun codecsString(abtoPhoneCfg: AbtoPhoneCfg, isVideo: Boolean): String {
    val type = abtoPhoneCfg.getCodecType()
    val data = StringBuilder()
    for (codec in getCodecs(isVideo)) {
      data.append(getName(codec))
      data.append("-")
      data.append(abtoPhoneCfg.getCodecPriority(codec, type, 0.toShort()))
      data.append(";")
    }
    return data.toString()
  }

  fun applyCodecs(abtoPhoneCfg: AbtoPhoneCfg, data: String) {
    val type = abtoPhoneCfg.getCodecType()
    val array = data.split(";").filter { !it.isNullOrEmpty() }.toList()

    for (value in array) { 
      val (codec, priority) = value.split("-").takeIf { it.size == 2 } ?: continue
      abtoPhoneCfg.setCodecPriority(getCodecByName(codec), type, priority.toShort())
    }
  }
}

