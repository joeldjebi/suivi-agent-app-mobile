import ActivityKit
import Flutter
import Foundation

/// Live Activity de la journée, pilotée par l'app Flutter (canal suivi_agent/day_activity) :
/// show (démarre ou met à jour) et end.
final class DayActivityBridge {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "suivi_agent/day_activity", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else { return result(false) }
      switch call.method {
      case "show":
        guard let args = call.arguments as? [String: Any] else { return result(false) }
        Task { result(await show(args)) }
      case "end":
        Task {
          await endAll()
          result(true)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @available(iOS 16.2, *)
  private static func state(_ args: [String: Any]) -> DayActivityAttributes.ContentState {
    let worked = args["workedSeconds"] as? Int ?? 0
    let pausedAt = (args["pausedAtMs"] as? Int).map { Date(timeIntervalSince1970: Double($0) / 1000) }
    return DayActivityAttributes.ContentState(
      status: args["status"] as? String ?? "active",
      workedStart: Date().addingTimeInterval(-Double(worked)),
      workedSeconds: worked,
      pausedAt: pausedAt,
      objectiveSeconds: args["objectiveSeconds"] as? Int ?? 8 * 3600,
      zone: args["zone"] as? String)
  }

  @available(iOS 16.2, *)
  private static func show(_ args: [String: Any]) async -> Bool {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
    let content = ActivityContent(state: state(args), staleDate: nil)
    let activities = Activity<DayActivityAttributes>.activities
    if let current = activities.first {
      await current.update(content)
      // Une seule activité à la fois.
      for extra in activities.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
      return true
    }
    do {
      _ = try Activity.request(
        attributes: DayActivityAttributes(structure: args["structure"] as? String ?? "Suivi Agent"),
        content: content)
      return true
    } catch {
      return false
    }
  }

  @available(iOS 16.2, *)
  private static func endAll() async {
    for activity in Activity<DayActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
