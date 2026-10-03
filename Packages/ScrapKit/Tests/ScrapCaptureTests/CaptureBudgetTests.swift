import Testing

@testable import ScrapCapture

struct CaptureBudgetTests {
    @Test func providerBudgetIs300Milliseconds() {
        #expect(CaptureBudget.provider == .milliseconds(300))
    }
}
