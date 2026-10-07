import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Boutons des notifications push (« Approuver », « Refuser ») : gardés jusqu'à ce que
  /// l'app Flutter les lise (elle peut démarrer à cette occasion).
  private var pushActions: FlutterMethodChannel?
  private var pendingActions: [[String: Any]] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // Notifications affichées app ouverte et réponses transmises aux extensions (Firebase,
    // notifications locales).
    UNUserNotificationCenter.current().delegate = self
    if let registrar = registrar(forPlugin: "SuiviPushActions") {
      let channel = FlutterMethodChannel(
        name: "suivi_agent/push_actions", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "takePending" else { return result(FlutterMethodNotImplemented) }
        result(self?.pendingActions ?? [])
        self?.pendingActions = []
      }
      pushActions = channel
    }
    if let registrar = registrar(forPlugin: "SuiviDayActivity") {
      DayActivityBridge.register(messenger: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    let action = response.actionIdentifier
    if info["gcm.message_id"] != nil,
      action != UNNotificationDefaultActionIdentifier,
      action != UNNotificationDismissActionIdentifier
    {
      var data: [String: String] = [:]
      for (key, value) in info {
        if let key = key as? String, let value = value as? String { data[key] = value }
      }
      pendingActions.append(["action": action, "data": data])
      pushActions?.invokeMethod("ready", arguments: nil)
    }
    super.userNotificationCenter(
      center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
