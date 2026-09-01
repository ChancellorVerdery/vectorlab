import SwiftUI
import VectorLabCore
import VectorLabScene

struct NotebookView: View {
    @Bindable var model: AppModel
    @FocusState private var focusedEntry: UUID?

    var body: some View {
        List {
            ForEach($model.entries) { $entry in
                EntryRow(
                    entry: $entry,
                    outcome: model.outcome(for: entry.id),
                    focus: $focusedEntry,
                    onSubmit: {
                        let newID = model.addEntry(after: entry.id)
                        focusedEntry = newID
                    },
                    onCycleColor: { model.cycleColor(entry.id) },
                    onDelete: { model.remove(entry.id) }
                )
            }
            .onMove { from, to in
                model.entries.move(fromOffsets: from, toOffset: to)
            }

            Button("New line", systemImage: "plus") {
                focusedEntry = model.addEntry()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

private struct EntryRow: View {
    @Binding var entry: Entry
    let outcome: VectorLabCore.LineOutcome?
    var focus: FocusState<UUID?>.Binding
    let onSubmit: () -> Void
    let onCycleColor: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: onCycleColor) {
                Circle()
                    .fill(Color(nsColor: VectorLabScene.Palette.color(entry.colorIndex)))
                    .frame(width: 9, height: 9)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change color")
            .opacity(isDrawable ? 1 : 0.25)

            VStack(alignment: .leading, spacing: 1) {
                // ponytail: raw TextField when focused, MathPrint Text otherwise;
                // unfocused rows aren't Tab-reachable — click to edit
                if showsRawText {
                    TextField("type a vector, point, or expression…", text: $entry.text)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .focused(focus, equals: entry.id)
                        .onSubmit(renderOrSubmit)
                } else {
                    prettyText
                        .contentShape(Rectangle())
                        .onTapGesture { focus.wrappedValue = entry.id }
                        .accessibilityHint("Tap to edit")
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

            Spacer(minLength: 4)

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
                .foregroundStyle(.quaternary)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 2)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Delete line", role: .destructive, action: onDelete)
        }
    }

    private var isDrawable: Bool {
        outcome?.drawable != nil || outcome?.arc != nil
    }

    private var showsRawText: Bool {
        focus.wrappedValue == entry.id
            || entry.text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// First Return renders the typed notation as math in place (\hat u → û)
    /// and keeps editing; the next Return, with nothing left to render,
    /// commits the line and moves on.
    private func renderOrSubmit() {
        let trimmed = entry.text.trimmingCharacters(in: .whitespaces)
        let isComment = trimmed.hasPrefix("#") || trimmed.hasPrefix("//")
        let pretty = MathPrint.pretty(entry.text)
        if !isComment, pretty != entry.text {
            entry.text = pretty
        } else {
            onSubmit()
        }
    }

    @ViewBuilder private var prettyText: some View {
        let trimmed = entry.text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
            Text(entry.text)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
        } else {
            Text(MathPrint.pretty(entry.text))
                .font(.system(.body, design: .serif))
        }
    }
}
