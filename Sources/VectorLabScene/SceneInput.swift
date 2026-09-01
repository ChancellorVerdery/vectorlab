import Foundation
import VectorLabCore

public struct ColoredDrawable: Equatable, Sendable {
    public var drawable: Drawable
    public var colorIndex: Int

    public init(drawable: Drawable, colorIndex: Int) {
        self.drawable = drawable
        self.colorIndex = colorIndex
    }
}

public struct ColoredArc: Equatable, Sendable {
    public var arc: ArcSpec
    public var colorIndex: Int

    public init(arc: ArcSpec, colorIndex: Int) {
        self.arc = arc
        self.colorIndex = colorIndex
    }
}
