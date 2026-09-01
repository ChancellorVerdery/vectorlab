import SwiftUI
import UniformTypeIdentifiers
import VectorLabCore
import VectorLabScene

struct NotebookView: View {
    @Bindable var model: AppModel
    @FocusState private var focusedEntry: UUID?
    @State private var draggingID: UUID?

    var body: some View {
        // ponytail: plain ScrollView, not List — List's row selection/drag
        // machinery swallowed clicks meant for the text fields
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach($model.entries) { $entry in
                    EntryRow(
                        entry: $entry,
                        outcome: model.outcome(for: entry.id),
                        focus: $focusedEntry,
                        onSubmit: { focusedEntry = model.addEntry(after: entry.id) },
                        onCycleColor: { model.cycleColor(entry.id) },
                        onDelete: { model.remove(entry.id) },
                        onMove: { delta in model.move(entry.id, by: delta) },
                        onDragStart: { draggingID = entry.id }
                    )
                    .onDrop(of: [.text], delegate: EntryDropDelegate(
                        itemID: entry.id, entries: $model.entries, draggingID: $draggingID))
                }

                Button("New line", systemImage: "plus") {
                    focusedEntry = model.addEntry()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .padding(.leading, 30)
            }
            .padding(10)
        }
    }
}

/// Live-reorders entries as the dragged row passes over others.
private struct EntryDropDelegate: DropDelegate {
    let itemID: UUID
    @Binding var entries: [Entry]
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingID, dragging != itemID,
              let from = entries.firstIndex(where: { $0.id == dragging }),
              let to = entries.firstIndex(where: { $0.id == itemID })
        else { return }
        withAnimation {
            entries.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

private struct EntryRow: View {
    @Binding var entry: Entry
    let outcome: VectorLabCore.LineOutcome?
    var focus: FocusState<UUID?>.Binding
    let onSubmit: () -> Void
    let onCycleColor: () -> Void
    let onDelete: () -> Void
    let onMove: (Int) -> Void
    let onDragStart: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Dragging works ONLY from this handle — clicks anywhere else
            // go straight to the text field.
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .contentShape(Rectangle())
                .onDrag {
                    onDragStart()
                    return NSItemProvider(object: entry.id.uuidString as NSString)
                }
                .accessibilityLabel("Drag to reorder")

            Button(action: onCycleColor) {
                Circle()
                    .fill(Color(nsColor: VectorLabScene.Palette.color(entry.colorIndex)))
                    .frame(width: 9, height: 9)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change color")
            .opacity(isDrawable ? 1 : 0.25)

            // ponytail: the row is ALWAYS a live editor — no pretty/raw view
            // swapping. Rendered math lives in the text itself (space and
            // Return rewrite \theta → θ); letter subscripts are styled by
            // RichEntryField without changing the underlying string.
            VStack(alignment: .leading, spacing: 1) {
                RichEntryField(
                    text: $entry.text,
                    focus: focus,
                    id: entry.id,
                    onCommit: onSubmit
                )

                if let outcome {
                    if let message = outcome.errorMessage {
                        if !entry.text.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else if !outcome.resultText.isEmpty {
                        Text(outcome.resultText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isDrawable {
                Button(entry.visible ? "Hide in scene" : "Show in scene",
                       systemImage: entry.visible ? "eye" : "eye.slash") {
                    entry.visible.toggle()
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }

            Button("Delete line", systemImage: "xmark.circle.fill", action: onDelete)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Move up", systemImage: "arrow.up") { onMove(-1) }
            Button("Move down", systemImage: "arrow.down") { onMove(1) }
            Divider()
            Button("Delete line", role: .destructive, action: onDelete)
        }
    }

    private var isDrawable: Bool {
        outcome?.drawable != nil || outcome?.arc != nil
    }
}
