import AppKit
import Foundation
import Observation
import TrihedronCore
import TrihedronScene

@Observable
final class AppModel {
    var entries: [Entry] = []
    private(set) var outcomes: [LineOutcome] = []
    /// `entries.map(\.id)` as of the last `reevaluate()`. `outcomes[i]` belongs to
    /// `outcomeIDs[i]` — NOT to `entries[i]`, which may already have been reordered
    /// or shortened by an edit that has not been re-evaluated yet.
    private var outcomeIDs: [UUID] = []

    var showAxes = true
    var showGrid = true
    var showArrowheads = true
    var preset: CameraPreset = .iso
    var presetToken = 0
    var fitToken = 0

    /// Where `save()` writes and `init` reads. `nil` means this model is in-memory only:
    /// nothing is loaded and nothing is written. Defaults to the real app-support location.
    private let saveURL: URL?

    init(saveURL: URL? = AppModel.defaultSaveURL()) {
        self.saveURL = saveURL
        entries = Self.loadEntries(from: saveURL) ?? Self.sampleEntries()
        reevaluate()
    }

    // MARK: - Evaluation

    func reevaluate() {
        // Hidden lines still define names, but their geometry is not in the
        // scene, so they must not size the axes a graph spans.
        let drawn = Set(entries.indices.filter { entries[$0].visible })
        outcomes = Engine.evaluate(entries.map(\.text), drawnLines: drawn)
        outcomeIDs = entries.map(\.id)
        save()
    }

    func outcome(for id: UUID) -> LineOutcome? {
        guard let idx = outcomeIDs.firstIndex(of: id) else { return nil }
        return outcomes[idx]
    }

    var coloredDrawables: [ColoredDrawable] {
        entries.compactMap { entry in
            guard entry.visible, let d = outcome(for: entry.id)?.drawable else { return nil }
            return ColoredDrawable(drawable: d, colorIndex: entry.colorIndex)
        }
    }

    var coloredArcs: [ColoredArc] {
        entries.compactMap { entry in
            guard entry.visible, let a = outcome(for: entry.id)?.arc else { return nil }
            return ColoredArc(arc: a, colorIndex: entry.colorIndex)
        }
    }

    // MARK: - Entry editing

    @discardableResult
    func addEntry(after id: UUID? = nil) -> UUID {
        let insertAt = id.flatMap { id in entries.firstIndex(where: { $0.id == id }).map { $0 + 1 } }
            ?? entries.count
        var entry = Entry()
        entry.colorIndex = Self.colorIndex(insertingAt: insertAt, among: entries)
        entries.insert(entry, at: insertAt)
        return entry.id
    }

    func remove(_ id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        if entries.isEmpty { entries = [Entry()] }
        reevaluate()
    }

    /// The first palette slot that neither immediate neighbour of the insertion
    /// point is using, walking forward from the count-based default. Falls back
    /// to that default when the palette is too small to avoid both.
    private static func colorIndex(insertingAt index: Int, among entries: [Entry]) -> Int {
        let n = Palette.nsColors.count
        let taken = Set([index - 1, index].compactMap { i -> Int? in
            guard entries.indices.contains(i) else { return nil }
            return ((entries[i].colorIndex % n) + n) % n
        })
        let start = entries.count % n
        for step in 0..<n where !taken.contains((start + step) % n) {
            return (start + step) % n
        }
        return start
    }

    func move(_ id: UUID, by delta: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + delta
        guard entries.indices.contains(target) else { return }
        entries.swapAt(idx, target)
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

    /// `~/Library/Application Support/Trihedron/workspace.json`, creating the directory.
    /// The app was called VectorLab until September 2026; a notebook saved under
    /// that name is copied across the first time the new location is empty.
    static func defaultSaveURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("Trihedron", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("workspace.json")
        migrateLegacyWorkspace(
            to: url, from: base.appendingPathComponent("VectorLab/workspace.json"))
        return url
    }

    /// One-time copy of a pre-rename notebook. Never overwrites, never
    /// deletes: the old file stays where it was in case the old app is
    /// still around to read it.
    static func migrateLegacyWorkspace(to url: URL, from legacy: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacy.path) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: legacy, to: url)
    }

    private func save() {
        // ponytail: saves on every re-eval (each keystroke); debounce if it ever matters
        guard let url = saveURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // .atomic: this runs on every keystroke, so a plain write leaves a real
        // window where a crash or a full disk truncates the saved notebook in place.
        try? data.write(to: url, options: .atomic)
    }

    private static func loadEntries(from url: URL?) -> [Entry]? {
        guard let url, let data = try? Data(contentsOf: url),
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
            "\\vec F = 260 * unit(r_AB)",
            "\\vec M_O = moment(r_OA, F)",
            "angle(F, r_OA)",
            "",
            "# Try: \\vec a = <1,2,3>   \\hat u = unit(a)   a*û   cross(a, û)   \\vec T = 50∠30",
            "# Graph: y = x^2   z = sin(deg(x))   z = x^2 + y^2, x in [-2, 2], y in [-2, 2]",
        ]
        return lines.enumerated().map { i, text in
            Entry(text: text, colorIndex: i % Palette.nsColors.count)
        }
    }
}
