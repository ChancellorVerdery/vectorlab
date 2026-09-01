import Foundation

public struct EvalError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// A computed value. Vectors carry an optional anchor: the tail point to draw
/// from, known when the vector came from point subtraction (r_AB is anchored
/// at A). Anchor propagates through scalar multiply/divide, unit() and
/// negation so forces along position vectors stay attached to their point.
public enum Value: Equatable, Sendable {
    case scalar(Double)
    case vector(Vec3, anchor: Vec3?)
    case point(Vec3)

    public var isVector: Bool { if case .vector = self { return true }; return false }

    public func asScalar(_ context: String) throws -> Double {
        guard case .scalar(let s) = self else { throw EvalError("\(context) needs a number, got \(typeName)") }
        return s
    }

    public func asVector(_ context: String) throws -> Vec3 {
        guard case .vector(let v, _) = self else { throw EvalError("\(context) needs a vector, got \(typeName)") }
        return v
    }

    /// Points give their coordinates; vectors are treated as position vectors.
    public func asPosition(_ context: String) throws -> Vec3 {
        switch self {
        case .point(let p): return p
        case .vector(let v, _): return v
        case .scalar: throw EvalError("\(context) needs a point or vector, got a number")
        }
    }

    public var typeName: String {
        switch self {
        case .scalar: return "a number"
        case .vector: return "a vector"
        case .point: return "a point"
        }
    }
}
