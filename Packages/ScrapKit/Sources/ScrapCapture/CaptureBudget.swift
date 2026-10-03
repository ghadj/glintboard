/// Time limits for the capture pipeline.
public enum CaptureBudget {
    /// How long the registry waits for the claiming provider before storing the fallback reference.
    public static let provider: Duration = .milliseconds(300)
}
