import Foundation
import Testing

@testable import RescreenBroker

@Suite("TimingNormalizer")
struct TimingNormalizerTests {
    @Test("Default floor is 5ms")
    func defaultFloor() {
        #expect(TimingNormalizer.defaultFloorNanoseconds == 5_000_000)
    }

    @Test("Returns the result of the work closure")
    func returnsResult() {
        let result = TimingNormalizer.withMinimumDuration {
            return 42
        }
        #expect(result == 42)
    }

    @Test("Enforces minimum duration")
    func enforcesMinimum() {
        let start = DispatchTime.now()
        _ = TimingNormalizer.withMinimumDuration(10_000_000) { // 10ms floor
            // Instant operation
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        // Should have taken at least ~10ms (allow some tolerance)
        #expect(elapsed >= 8_000_000) // 8ms to account for scheduling jitter
    }

    @Test("Does not add delay when work exceeds floor")
    func noExtraDelay() {
        let start = DispatchTime.now()
        _ = TimingNormalizer.withMinimumDuration(1_000) { // 1 microsecond floor
            // Do some trivial work that definitely takes more than 1µs
            var sum = 0
            for i in 0..<1000 { sum += i }
            _ = sum
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        // Should complete without sleeping 5ms+ (the default floor)
        #expect(elapsed < 50_000_000) // well under 50ms
    }

    @Test("Works with different return types")
    func differentReturnTypes() {
        let stringResult = TimingNormalizer.withMinimumDuration(1_000) { "hello" }
        #expect(stringResult == "hello")

        let arrayResult = TimingNormalizer.withMinimumDuration(1_000) { [1, 2, 3] }
        #expect(arrayResult == [1, 2, 3])

        let optionalResult: Int? = TimingNormalizer.withMinimumDuration(1_000) { nil }
        #expect(optionalResult == nil)
    }
}
