import Foundation
import Observation

/// Usage counters, persisted to UserDefaults a few seconds after they change.
@Observable @MainActor
final class StatsManager {
    private(set) var keystrokes: Int
    private(set) var clicks: Int
    private(set) var dings: Int
    private(set) var usageBySet: [String: Int]
    private(set) var firstTrackedAt: Date

    @ObservationIgnored private let store = UserDefaults.standard
    @ObservationIgnored private var flushTimer: Timer?
    @ObservationIgnored private var dirty = false

    private enum Key {
        static let keystrokes = "stats.keystrokes"
        static let clicks = "stats.clicks"
        static let dings = "stats.dings"
        static let usageBySet = "stats.usageBySet"
        static let firstTrackedAt = "stats.firstTrackedAt"
    }

    init() {
        let store = UserDefaults.standard
        keystrokes = store.integer(forKey: Key.keystrokes)
        clicks = store.integer(forKey: Key.clicks)
        dings = store.integer(forKey: Key.dings)
        usageBySet = store.dictionary(forKey: Key.usageBySet) as? [String: Int] ?? [:]
        if let date = store.object(forKey: Key.firstTrackedAt) as? Date {
            firstTrackedAt = date
        } else {
            firstTrackedAt = Date()
            store.set(firstTrackedAt, forKey: Key.firstTrackedAt)
        }
        flushTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.flush() }
        }
    }

    var totalEvents: Int { keystrokes + clicks + dings }

    var favouriteSet: String? {
        usageBySet.max { $0.value < $1.value }?.key
    }

    var usageSorted: [(name: String, count: Int)] {
        usageBySet.map { (name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    func record(_ played: SoundEngine.Played, setName: String) {
        switch played {
        case .key(_, let down):
            guard down else { return }
            keystrokes += 1
            usageBySet[setName, default: 0] += 1
        case .modifier(let down):
            guard down else { return }
            keystrokes += 1
            usageBySet[setName, default: 0] += 1
        case .ding:
            dings += 1
        case .click(let down):
            guard down else { return }
            clicks += 1
        }
        dirty = true
    }

    func reset() {
        keystrokes = 0
        clicks = 0
        dings = 0
        usageBySet = [:]
        firstTrackedAt = Date()
        store.set(firstTrackedAt, forKey: Key.firstTrackedAt)
        dirty = true
        flush()
    }

    func flush() {
        guard dirty else { return }
        dirty = false
        store.set(keystrokes, forKey: Key.keystrokes)
        store.set(clicks, forKey: Key.clicks)
        store.set(dings, forKey: Key.dings)
        store.set(usageBySet, forKey: Key.usageBySet)
    }
}
