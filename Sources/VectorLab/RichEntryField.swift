import SwiftUI
import VectorLabCore

/// Single-line attributed editor for a notebook entry. The plain string
/// binding stays the source of truth; letter subscripts (_AB) are typeset
/// live as true subscripts by styling runs without changing characters.
/// ponytail: experimental — if editing misbehaves, swap back to TextField
/// in EntryRow (this type is self-contained for exactly that reason).
struct RichEntryField: View {
    @Binding var text: String
    var focus: FocusState<UUID?>.Binding
    let id: UUID
    let onCommit: () -> Void

    @State private var rich = AttributedString()

    var body: some View {
        TextEditor(text: $rich)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 26)
            .focused(focus, equals: id)
            .onKeyPress(.return) {
                renderOrSubmit()
                return .handled
            }
            .onChange(of: rich) { syncFromRich() }
            .onChange(of: text) { syncFromRaw() }
            .onAppear { syncFromRaw() }
            .overlay(alignment: .leading) {
                if text.isEmpty {
                    Text("type a vector, point, or expression…")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Sync (string ↔ attributed)

    private func syncFromRich() {
        let old = text
        let raw = String(rich.characters).replacingOccurrences(of: "\n", with: "")
        guard raw != old else {
            syncFromRaw()
            return
        }
        text = raw
        liveRender(old: old, new: raw)
        syncFromRaw()
    }

    private func syncFromRaw() {
        let styled = styled(text)
        if rich != styled {
            rich = styled
        }
    }

    /// Base monospace with subscript styling on _LETTER runs. Digit-only
    /// subscripts aren't styled — applyScripts turns those into ₁ glyphs.
    private func styled(_ raw: String) -> AttributedString {
        let base = AttributeContainer().font(.system(.body, design: .monospaced))
        let sub = AttributeContainer()
            .font(.system(size: 10, design: .monospaced))
            .baselineOffset(-3)

        var result = AttributedString()
        var plain = ""
        func flushPlain() {
            if !plain.isEmpty {
                result += AttributedString(plain, attributes: base)
                plain = ""
            }
        }

        var idx = raw.startIndex
        while idx < raw.endIndex {
            if raw[idx] == "_" {
                var j = raw.index(after: idx)
                var run = "_"
                var sawLetter = false
                while j < raw.endIndex, raw[j].isLetter || raw[j].isNumber {
                    if raw[j].isLetter { sawLetter = true }
                    run.append(raw[j])
                    j = raw.index(after: j)
                }
                if sawLetter {
                    flushPlain()
                    result += AttributedString(run, attributes: sub)
                    idx = j
                    continue
                }
            }
            plain.append(raw[idx])
            idx = raw.index(after: idx)
        }
        flushPlain()
        return result
    }

    // MARK: - Live rendering (moved from EntryRow)

    /// Space completes a \command (\theta, \hat(a)) and swallows itself;
    /// _1 / ^2 become ₁ / ² the moment the digit lands. End-of-line only.
    private func liveRender(old: String, new: String) {
        guard focus.wrappedValue == id,
              new.count == old.count + 1,
              new.hasPrefix(old)
        else { return }
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return }

        if new.hasSuffix(" ") {
            let body = String(new.dropLast())
            guard body.contains(try! Regex(#"\\[a-zA-Z]+(\s*[({]?[\p{L}\p{N}_]*[)}]?)?$"#)) else { return }
            let pretty = MathPrint.pretty(body)
            if pretty != body {
                text = pretty
            }
        } else {
            let scripted = MathPrint.applyScripts(new)
            if scripted != new {
                text = scripted
            }
        }
    }

    /// First Return renders remaining notation; the next commits the line.
    private func renderOrSubmit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let isComment = trimmed.hasPrefix("#") || trimmed.hasPrefix("//")
        let pretty = MathPrint.pretty(text)
        if !isComment, pretty != text {
            text = pretty
            let entryID = id
            DispatchQueue.main.async { focus.wrappedValue = entryID }
        } else {
            onCommit()
        }
    }
}
