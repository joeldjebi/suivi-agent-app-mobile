import ActivityKit
import Foundation

/// Journée de l'agent sur l'écran verrouillé et dans la Dynamic Island (Live Activity).
/// Fichier partagé par l'app (qui démarre et met à jour l'activité) et l'extension (qui l'affiche).
@available(iOS 16.1, *)
struct DayActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// active ou paused
    var status: String
    /// Début fictif du chrono : maintenant moins le temps travaillé (pauses déduites).
    var workedStart: Date
    /// Temps travaillé figé pendant une pause, en secondes.
    var workedSeconds: Int
    var pausedAt: Date?
    /// Objectif de la journée, en secondes.
    var objectiveSeconds: Int
    var zone: String?

    var paused: Bool { status == "paused" }
  }

  /// Nom de la structure.
  var structure: String
}
