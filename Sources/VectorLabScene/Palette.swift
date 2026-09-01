import AppKit

public enum Palette {
    /// Vector colors, cycled per entry. Chosen to stay distinct on the dark viewport.
    public static let nsColors: [NSColor] = [
        .systemBlue, .systemRed, .systemGreen, .systemOrange,
        .systemPurple, .systemTeal, .systemPink, .systemYellow,
    ]

    public static func color(_ index: Int) -> NSColor {
        nsColors[((index % nsColors.count) + nsColors.count) % nsColors.count]
    }
}
