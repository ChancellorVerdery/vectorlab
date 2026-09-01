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

            // ponytail: the row is ALWAYS a live TextField — no pretty/raw
            // view swapping. Rendered math lives in the text itself (space
            // and Return rewrite \theta → θ), so editing can never be
            // blocked by focus/overlay tricks again.
            VStack(alignment: .leading, spacing: 1) {
                TextField("type a vector, point, or expression…", text: $entry.text)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused(focus, equals: entry.id)
                    .onSubmit(renderOrSubmit)
                    .onChange(of: entry.text) { old, new in
                        renderOnType(old: old, new: new)
                    }

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

    /// Live rendering while typing at the end of the line:
    /// - space right after a \command (\theta, \hat(a)) renders it and
    ///   swallows the space, like a LaTeX editor;
    /// - _1 and ^2 become ₁ and ² the moment the digit lands.
    /// Mid-line edits are left alone so the caret never jumps; operator
    /// conversions (* → ·) wait for Return.
    private func renderOnType(old: String, new: String) {
        guard focus.wrappedValue == entry.id,
              new.count == old.count + 1,
              new.hasPrefix(old)          // insertion at the end only
        else { return }
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return }

        if new.hasSuffix(" ") {
            let body = String(new.dropLast())
            guard body.contains(try! Regex(#"\\[a-zA-Z]+(\s*[({]?[\p{L}\p{N}_]*[)}]?)?$"#)) else { return }
            let pretty = MathPrint.pretty(body)
            if pretty != body {
                entry.text = pretty   // rendered — the space was the trigger, not content
            }
        } else {
            let scripted = MathPrint.applyScripts(new)
            if scripted != new {
                entry.text = scripted
            }
        }
    }

    /// First Return renders any remaining notation in place; the next
    /// Return, with nothing left to render, commits the line and moves on.
    private func renderOrSubmit() {
        let trimmed = entry.text.trimmingCharacters(in: .whitespaces)
        let isComment = trimmed.hasPrefix("#") || trimmed.hasPrefix("//")
        let pretty = MathPrint.pretty(entry.text)
        if !isComment, pretty != entry.text {
            entry.text = pretty
            // macOS can drop first responder when the text changes underneath
            // it — re-assert focus so the first Return keeps you in the field.
            let id = entry.id
            DispatchQueue.main.async { focus.wrappedValue = id }
        } else {
            onSubmit()
        }
    }
}
