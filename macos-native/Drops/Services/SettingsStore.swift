import Foundation

/// Persists user-facing preferences that Stage 2 needs (retention days).
final class SettingsStore {
    static let retentionDaysKey = "drops.retentionDays"

    private let defaults: UserDefaults
    private(set) var retentionDays: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.retentionDaysKey) as? Int
        if let stored, (try? RetentionPolicy(days: stored)) != nil {
            retentionDays = stored
        } else {
            retentionDays = RetentionPolicy.defaultDays
        }
    }

    /// Accepts only 1...120. Illegal input leaves the previous valid value unchanged.
    @discardableResult
    func setRetentionDays(_ days: Int) throws -> Int {
        let policy = try RetentionPolicy(days: days)
        retentionDays = policy.days
        defaults.set(retentionDays, forKey: Self.retentionDaysKey)
        return retentionDays
    }
}
