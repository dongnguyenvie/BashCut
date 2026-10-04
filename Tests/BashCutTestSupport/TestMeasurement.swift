import Foundation

/// Benchmark lines that docs/status/implementation.md quotes come from test logs. This is the only place tests
/// write to standard output; diagnostics belong in assertions.
public enum TestMeasurement {
    public static func report(_ line: String) { print(line) }
}
