import Foundation

/// Ensures uniform-time responses for denied/out-of-scope requests,
/// preventing timing side-channel attacks that could probe resource existence.
enum TimingNormalizer {
    /// Minimum response time for denial responses (5ms).
    /// Calibrated to exceed the variance in fast-path permission checks
    /// while being shorter than real operations (AX tree walk, screenshot).
    static let defaultFloorNanoseconds: UInt64 = 5_000_000

    /// Execute a closure and ensure the total elapsed time is at least `floor` nanoseconds.
    /// If the closure finishes early, sleeps for the remainder.
    static func withMinimumDuration<T>(
        _ floorNanoseconds: UInt64 = defaultFloorNanoseconds,
        work: () -> T
    ) -> T {
        let start = DispatchTime.now()
        let result = work()
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds

        if elapsed < floorNanoseconds {
            let remaining = floorNanoseconds - elapsed
            Thread.sleep(forTimeInterval: Double(remaining) / 1_000_000_000)
        }

        return result
    }
}
