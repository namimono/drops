import Foundation

/// Shared measurement helpers for Stage 0 latency baselines.
final class Stage0PerformanceMetrics: @unchecked Sendable {
    static let shared = Stage0PerformanceMetrics()

    private let lock = NSLock()
    private var persistentFirstFrameSamples: [Double] = []
    private var transientReadySamples: [Double] = []

    /// Target: P95 < 300 ms for persistent shelf first frame.
    static let persistentFirstFrameBudgetMs = 300.0
    /// Target: P95 < 200 ms for transient shelf drag-ready.
    static let transientReadyBudgetMs = 200.0

    func recordPersistentFirstFrame(seconds: Double) {
        lock.lock()
        persistentFirstFrameSamples.append(seconds * 1000)
        lock.unlock()
        NSLog("[Stage0][Perf] persistent first-frame=%.1fms", seconds * 1000)
    }

    func recordTransientReady(seconds: Double) {
        lock.lock()
        transientReadySamples.append(seconds * 1000)
        lock.unlock()
        NSLog("[Stage0][Perf] transient drag-ready=%.1fms", seconds * 1000)
    }

    func summary() -> String {
        lock.lock()
        defer { lock.unlock() }
        let persistent = describe(samples: persistentFirstFrameSamples, budget: Self.persistentFirstFrameBudgetMs)
        let transient = describe(samples: transientReadySamples, budget: Self.transientReadyBudgetMs)
        return """
        [Stage0][Perf] Baseline summary
        - Persistent create→first-frame: \(persistent)
        - Transient create→drag-ready: \(transient)
        Measurement method: CFAbsoluteTimeGetCurrent around show(). Future stages reuse the same markers.
        """
    }

    private func describe(samples: [Double], budget: Double) -> String {
        guard !samples.isEmpty else {
            return "no samples (budget P95 < \(Int(budget))ms)"
        }
        let sorted = samples.sorted()
        let p95 = percentile(sorted, 0.95)
        let avg = samples.reduce(0, +) / Double(samples.count)
        let status = p95 <= budget ? "PASS" : "OVER"
        return String(
            format: "n=%d avg=%.1fms p95=%.1fms budget=%.0fms [%@]",
            samples.count,
            avg,
            p95,
            budget,
            status
        )
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * p)) - 1)
        return sorted[max(0, index)]
    }
}
