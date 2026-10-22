import Foundation
import Testing
@testable import TrihedronCore

/// Runs lines in order, returns the value of the last non-blank line.
func lastValue(_ lines: [String]) throws -> Value {
    var evaluator = Evaluator()
    var last: Value?
    for line in lines {
        if let (_, value) = try evaluator.execute(Parser.parseLine(line)) {
            last = value
        }
    }
    guard let last else { throw EvalError("no value produced") }
    return last
}

func lastValue(_ lines: String...) throws -> Value { try lastValue(lines) }

func scalar(_ lines: String...) throws -> Double {
    guard case .scalar(let s) = try lastValue(lines) else { throw EvalError("expected scalar") }
    return s
}

func vector(_ lines: String...) throws -> Vec3 {
    let v = try lastValue(lines)
    if case .vector(let vec, _) = v { return vec }
    if case .point(let p) = v { return p }
    throw EvalError("expected vector")
}

func expectApprox(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9,
                  sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(actual - expected) <= tolerance,
            "expected \(expected), got \(actual)", sourceLocation: sourceLocation)
}

func expectApprox(_ actual: Vec3, _ expected: Vec3, tolerance: Double = 1e-9,
                  sourceLocation: SourceLocation = #_sourceLocation) {
    #expect((actual - expected).length <= tolerance,
            "expected \(expected), got \(actual)", sourceLocation: sourceLocation)
}
