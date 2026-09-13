import Foundation
import Observation

/// Runs `apply` now and again whenever any @Observable property it read changes.
/// Changes are coalesced onto the next main-actor turn.
@MainActor
func observeChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in
            observeChanges(apply)
        }
    }
}
