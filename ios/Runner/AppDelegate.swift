import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Yakınlık sensörü kanalı: aktif çağrıda ekranı karartmak için
    let messenger = engineBridge.pluginRegistry.registrar(
      forPlugin: "proximity"
    )?.messenger() ?? (engineBridge.pluginRegistry as? FlutterBinaryMessenger)

    if let messenger = messenger {
      let proximityChannel = FlutterMethodChannel(
        name: "inteliex_softphone/proximity",
        binaryMessenger: messenger
      )
      proximityChannel.setMethodCallHandler { call, result in
        if call.method == "setActive" {
          let active = (call.arguments as? [String: Any])?["active"] as? Bool ?? false
          UIDevice.current.isProximityMonitoringEnabled = active
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
