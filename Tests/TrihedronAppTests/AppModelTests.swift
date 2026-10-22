import Foundation
import Testing
import TrihedronCore
import TrihedronScene
@testable import Trihedron

/// Pass 4. The first tests the executable target has ever had.
///
/// Passes 1–3 all deferred this because `AppModel.init()` read and `save()` wrote
/// Chancellor's real `~/Library/Application Support/Trihedron/workspace.json`, so
/// merely constructing a model in a test would clobber his saved notebook. Pass 4
/// makes the location injectable; every model below is built either in-memory
/// (`saveURL: nil`) or against a temp file, and none of them can reach the real one.
@MainActor
@Suite struct AppModelTests {

    /// A model that never touches the filesystem.
    private func memoryModel(_ lines: [String]) -> AppModel {
        let m = AppModel(saveURL: nil)
        m.entries = lines.map { Entry(text: $0) }
        m.reevaluate()
        return m
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vl-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }

    // MARK: - The injectable save location itself

    @Test func inMemoryModelWritesNothingAndLoadsNothing() throws {
        let m = AppModel(saveURL: nil)
        m.entries = [Entry(text: "1 + 1")]
        m.reevaluate()
        // Sample entries are only used when nothing loaded; a nil URL must load nothing.
        let fresh = AppModel(saveURL: nil)
        #expect(fresh.entries.count > 1)  // fell back to the sample notebook
        #expect(fresh.entries.contains { $0.text.contains("point A") })
    }

    @Test func entriesRoundTripThroughTheInjectedFile() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let saver = AppModel(saveURL: url)
        saver.entries = [Entry(text: "\\vec a = <1,2,3>"), Entry(text: "mag(a)")]
        saver.reevaluate()
        #expect(FileManager.default.fileExists(atPath: url.path))

        let loader = AppModel(saveURL: url)
        #expect(loader.entries.map(\.text) == ["\\vec a = <1,2,3>", "mag(a)"])
        #expect(loader.outcome(for: loader.entries[1].id)?.resultText.contains("3.7417") == true)
    }

    @Test func corruptSaveFileFallsBackToTheSampleNotebookInsteadOfCrashing() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)

        let m = AppModel(saveURL: url)
        #expect(m.entries.contains { $0.text.contains("point A") })
    }

    // MARK: - The VectorLab → Trihedron rename

    /// A notebook saved by the app under its old name is copied to the new
    /// location once, and the old file is left alone.
    @Test func legacyWorkspaceIsCopiedOnceAndNeverOverwritten() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("tri-migrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("VectorLab/workspace.json")
        let current = base.appendingPathComponent("Trihedron/workspace.json")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let saved = try JSONEncoder().encode([Entry(text: "\\vec a = <1, 2, 3>")])
        try saved.write(to: legacy)

        AppModel.migrateLegacyWorkspace(to: current, from: legacy)
        #expect(try Data(contentsOf: current) == saved)
        #expect(FileManager.default.fileExists(atPath: legacy.path), "the old notebook must survive")

        // The new file now exists, so a second migration must not touch it.
        let newer = try JSONEncoder().encode([Entry(text: "y = x^2")])
        try newer.write(to: current)
        AppModel.migrateLegacyWorkspace(to: current, from: legacy)
        #expect(try Data(contentsOf: current) == newer)

        // And the model opened on the new location reads the migrated notebook.
        let loader = AppModel(saveURL: current)
        #expect(loader.entries.map(\.text) == ["y = x^2"])
    }

    @Test func migrationWithNoLegacyFileWritesNothing() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("tri-migrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let current = base.appendingPathComponent("Trihedron/workspace.json")
        AppModel.migrateLegacyWorkspace(to: current, from: base.appendingPathComponent("VectorLab/workspace.json"))
        #expect(!FileManager.default.fileExists(atPath: current.path))
    }

    // MARK: - Graphs in the notebook

    /// A hidden line's vector is not in the scene, so it must not size the
    /// axes a graph spans: the model passes visibility through to the engine.
    @Test func hiddenLinesDoNotSizeAGraphsDomain() throws {
        let m = memoryModel(["\\vec F = <10, 0, 0>", "y = 0.1 * x"])
        func firstX() -> Double? {
            guard case .curve(let segments)? = m.outcome(for: m.entries[1].id)?.drawable?.shape else { return nil }
            return segments.first?.first?.x
        }
        #expect(abs((firstX() ?? 0) + 12) < 1e-9)
        m.entries[0].visible = false
        m.reevaluate()
        #expect(firstX() == -5)
        #expect(m.coloredDrawables.count == 1, "the hidden vector is not handed to the scene")
    }

    // MARK: - outcome(for:) is keyed by index, not by id  (pass-2/3 lead)

    /// `outcome(for:)` finds the entry's *index* and reads `outcomes[index]`.
    /// Any edit that reorders or shortens `entries` without an immediate
    /// `reevaluate()` therefore pairs an entry with a stale neighbour's result.
    /// In the app `remove` is exactly such an edit: it does not reevaluate
    /// (only `ContentView.onChange` does, on the next SwiftUI update).
    @Test func outcomeStaysWithItsOwnEntryAfterRemove() throws {
        let m = memoryModel(["1 + 1", "10 + 10", "100 + 100"])
        let third = m.entries[2].id
        #expect(m.outcome(for: third)?.resultText == "200")

        m.remove(m.entries[0].id)
        // The third line is now at index 1, so an index-keyed lookup hands back
        // the SECOND line's result. Its own answer is still 200.
        #expect(m.outcome(for: third)?.resultText == "200")
    }

    @Test func outcomeStaysWithItsOwnEntryAfterMove() throws {
        let m = memoryModel(["1 + 1", "10 + 10", "100 + 100"])
        let first = m.entries[0].id
        m.move(first, by: 2 - 0)  // no-op guard check below; move by 1 twice
        m.move(first, by: 1)
        #expect(m.outcome(for: first)?.resultText == "2")
    }

    /// Same class of bug on the drawing side: `coloredDrawables`/`coloredArcs`
    /// `zip` entries against outcomes positionally, so a removal shifts every
    /// arrow onto the wrong entry's colour and label.
    @Test func drawablesStayWithTheirOwnEntryAfterRemove() throws {
        let m = memoryModel([
            "\\vec a = <1,0,0>",
            "\\vec b = <0,2,0>",
            "\\vec c = <0,0,3>",
        ])
        m.entries[2].colorIndex = 5
        m.remove(m.entries[0].id)

        let labels = m.coloredDrawables.compactMap(\.drawable.label)
        #expect(labels == ["b", "c"])
        // c is gone from the environment's point of view? No — b and c still
        // evaluate. The point is that c's arrow keeps c's colour.
        if let cItem = m.coloredDrawables.first(where: { $0.drawable.label == "c" }) {
            #expect(cItem.colorIndex == 5)
        } else {
            Issue.record("c was not drawn at all")
        }
    }

    // MARK: - addEntry colour  (pass-1 lead)

    /// `addEntry` sets `colorIndex = entries.count % palette` BEFORE inserting,
    /// so a mid-notebook insert gets the colour of whatever is currently last —
    /// and, more visibly, can land the same colour as the neighbour it is
    /// inserted next to.
    @Test func insertedEntryDoesNotShareItsNeighboursColor() throws {
        let m = AppModel(saveURL: nil)
        m.entries = (0..<8).map { Entry(text: "\($0)", colorIndex: $0) }
        m.reevaluate()

        // 8 entries, palette of 8: a new entry gets 8 % 8 == 0, the same colour
        // as entry 0 — which is exactly the neighbour we insert after.
        let newID = m.addEntry(after: m.entries[0].id)
        let inserted = try #require(m.entries.first { $0.id == newID })
        #expect(m.entries[1].id == newID)
        #expect(inserted.colorIndex != m.entries[0].colorIndex)
        #expect(inserted.colorIndex != m.entries[2].colorIndex)
    }

    // MARK: - Editing operations that already work (regression pins)

    @Test func removeLastEntryLeavesOneBlankEntryWithAMatchingOutcome() throws {
        let m = memoryModel(["1 + 1"])
        m.remove(m.entries[0].id)
        #expect(m.entries.count == 1)
        #expect(m.entries[0].text == "")
        // Whatever the model reports for the surviving entry must describe THAT
        // entry, not the removed one.
        #expect(m.outcome(for: m.entries[0].id)?.resultText != "2")
    }

    @Test func moveRejectsOutOfRangeTargets() throws {
        let m = memoryModel(["a", "b"])
        let order = m.entries.map(\.id)
        m.move(order[0], by: -1)
        m.move(order[1], by: 1)
        m.move(UUID(), by: 1)
        #expect(m.entries.map(\.id) == order)
    }

    @Test func cycleColorWrapsThroughThePalette() throws {
        let m = memoryModel(["a"])
        let id = m.entries[0].id
        let start = m.entries[0].colorIndex
        for _ in 0..<Palette.nsColors.count { m.cycleColor(id) }
        #expect(m.entries[0].colorIndex == start)
    }

    @Test func hiddenEntriesAreNotDrawn() throws {
        let m = memoryModel(["\\vec a = <1,0,0>", "\\vec b = <0,1,0>"])
        m.entries[0].visible = false
        #expect(m.coloredDrawables.compactMap(\.drawable.label) == ["b"])
    }
}
