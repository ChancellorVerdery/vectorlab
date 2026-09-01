import AppKit
import Foundation
import Observation
import VectorLabCore
import VectorLabScene

@Observable
final class AppModel {
    var entries: [Entry] = []
    private(set) var outcomes: [LineOutcome] = []

    var showAxes = true
    var showGrid = true
    var preset: CameraPreset = .iso
    var presetToken = 0
    var fitToken = 0

    init() {
        entries = Self.loadEntries() ?? Self.sampleEntries()
        reevaluate()
    }

    // MARK: - Evaluation

    func reevaluate() {
        outcomes = Engine.evaluate(entries.map(\.text))
        save()
    }

    func outcome(for id: UUID) -> LineOutcome? {
        guard let idx = entries.firstIndex(where: { $0.id == id }), outcomes.indices.contains(idx) else { return nil }
        return outcomes[idx]
    }

    var coloredDrawables: [ColoredDrawable] {
        zip(entries, outcomes).compactMap { entry, outcome in
            guard entry.visible, let d = outcome.drawable else { return nil }
            return ColoredDrawable(drawable: d, colorIndex: entry.colorIndex)
        }
    }

    var coloredArcs: [ColoredArc] {
        zip(entries, outcomes).compactMap { entry, outcome in
            guard entry.visible, let a = outcome.arc else { return nil }
            return ColoredArc(arc: a, colorIndex: entry.colorIndex)
        }
    }

    // MARK: - Entry editing

    @discardableResult
    func addEntry(after id: UUID? = nil) -> UUID {
        var entry = Entry()
        entry.colorIndex = entries.count % Palette.nsColors.count
        if let id, let idx = entries.firstIndex(where: { $0.id == id }) {
            entries.insert(entry, at: idx + 1)
        } else {
            entries.append(entry)
        }
        return entry.id
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        if entries.isEmpty { entries = [Entry()] }
    }

    func cycleColor(_ id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].colorIndex = (entries[idx].colorIndex + 1) % Palette.nsColors.count
    }

    func clearAll() {
        entries = [Entry()]
        reevaluate()
    }

    func loadExample() {
        entries = Self.sampleEntries()
        reevaluate()
    }

    // MARK: - Persistence (best-effort autosave)

    private static var saveURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("VectorLab", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workspace.json")
    }

    private func save() {
        // ponytail: saves on every re-eval (each keystroke); debounce if it ever matters
        guard let url = Self.saveURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url)
    }

    private static func loadEntries() -> [Entry]? {
        guard let url = saveURL, let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data), !entries.isEmpty
        else { return nil }
        return entries
    }

    private static func sampleEntries() -> [Entry] {
        let lines = [
            "# Example: 260 lb force along cable AB",
            "point O = (0, 0, 0)",
            "point A = (0, 0, 12)",
            "point B = (4, -3, 0)",
            "r_AB",
            "F = 260 * unit(r_AB)",
            "M_O = moment(r_OA, F)",
            "angle(F, r_OA)",
            "",
            "# Try: a = <1,2,3>   b = 2i - j   a*b   cross(a,b)   T = 50∠30",
        ]
        return lines.enumerated().map { i, text in
            Entry(text: text, colorIndex: i % Palette.nsColors.count)
        }
    }
}
