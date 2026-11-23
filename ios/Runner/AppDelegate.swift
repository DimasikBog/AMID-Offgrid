import Flutter
import UIKit
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var filesChannel: FlutterMethodChannel?
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "com.amid.offgrid/files", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    filesChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup" else { result(FlutterMethodNotImplemented); return }
      guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else {
        result(FlutterError(code: "INVALID_PATH", message: "File path is required", details: nil)); return
      }
      do {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).resolvingSymlinksInPath().standardizedFileURL
        var file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(support.path + "/") else {
          result(FlutterError(code: "INVALID_PATH", message: "Path must be inside app support", details: nil)); return
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "BACKUP_FLAG_FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }
}
