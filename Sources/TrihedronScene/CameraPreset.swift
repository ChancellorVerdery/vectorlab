import Foundation

public enum CameraPreset: String, CaseIterable, Identifiable, Sendable {
    case iso = "Iso"
    case top = "XY"
    case front = "XZ"
    case side = "YZ"

    public var id: String { rawValue }
}
