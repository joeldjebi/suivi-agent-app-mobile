import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DayActivityBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.1, *) {
      DayActivityWidget()
    }
  }
}

/// « 3 h 12 », « 45 min ».
private func formatWorked(_ seconds: Int) -> String {
  let h = seconds / 3600
  let m = (seconds % 3600) / 60
  if h == 0 { return "\(m) min" }
  return m == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", m))"
}

@available(iOS 16.1, *)
struct DayActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DayActivityAttributes.self) { context in
      LockScreenView(state: context.state, structure: context.attributes.structure)
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let state = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(state.paused ? "En pause" : "En journée", systemImage: state.paused ? "pause.circle.fill" : "figure.walk")
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.paused ? .orange : .green)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Chrono(state: state).font(.title3.monospacedDigit().weight(.semibold))
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            if let zone = state.zone { Text(zone).font(.subheadline).lineLimit(1) }
            Objective(state: state)
          }
        }
      } compactLeading: {
        Image(systemName: state.paused ? "pause.fill" : "figure.walk")
          .foregroundStyle(state.paused ? .orange : .green)
      } compactTrailing: {
        Chrono(state: state).monospacedDigit().frame(maxWidth: 64)
      } minimal: {
        Image(systemName: state.paused ? "pause.fill" : "figure.walk")
          .foregroundStyle(state.paused ? .orange : .green)
      }
    }
  }
}

/// Chrono du temps travaillé : il tourne seul en journée, il est figé en pause.
@available(iOS 16.1, *)
private struct Chrono: View {
  let state: DayActivityAttributes.ContentState
  var body: some View {
    if state.paused {
      Text(formatWorked(state.workedSeconds))
    } else {
      Text(timerInterval: state.workedStart...Date.distantFuture, countsDown: false)
        .multilineTextAlignment(.trailing)
    }
  }
}

/// Progression vers l'objectif de la journée.
@available(iOS 16.1, *)
private struct Objective: View {
  let state: DayActivityAttributes.ContentState
  var body: some View {
    let goal = max(state.objectiveSeconds, 60)
    VStack(alignment: .leading, spacing: 4) {
      if state.paused {
        ProgressView(value: Double(min(state.workedSeconds, goal)), total: Double(goal))
      } else {
        ProgressView(
          timerInterval: state.workedStart...state.workedStart.addingTimeInterval(TimeInterval(goal)),
          countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
      }
      Text("Objectif \(formatWorked(goal))").font(.caption2).foregroundStyle(.secondary)
    }
    .tint(state.paused ? .orange : .green)
  }
}

@available(iOS 16.1, *)
private struct LockScreenView: View {
  let state: DayActivityAttributes.ContentState
  let structure: String
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(state.paused ? "En pause" : "Journée en cours")
            .font(.headline)
            .foregroundStyle(state.paused ? .orange : .green)
          Text(state.zone ?? structure).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
        }
        Spacer()
        Chrono(state: state)
          .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
          .foregroundStyle(.white)
      }
      Objective(state: state)
      if state.paused, let since = state.pausedAt {
        Text("Pause depuis \(since, style: .time)").font(.caption).foregroundStyle(.white.opacity(0.7))
      }
    }
    .padding(16)
  }
}
