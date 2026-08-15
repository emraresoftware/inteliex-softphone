import 'package:flutter/foundation.dart';

import 'method_channel_voip_platform_bridge.dart';
import 'no_op_voip_platform_bridge.dart';
import 'voip_platform_bridge.dart';

VoipPlatformBridge createVoipPlatformBridge() {
  if (kIsWeb) {
    return const NoOpVoipPlatformBridge();
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.android:
      return MethodChannelVoipPlatformBridge();
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return const NoOpVoipPlatformBridge();
  }
}
