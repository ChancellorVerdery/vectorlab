import AppKit
import SwiftUI
import VectorLabCore

/// Single-line attributed editor for a notebook entry. The plain string
/// binding stays the source of truth; letter subscripts (_AB) typeset live
/// as true subscripts, and a `\vec NAME` token renders as a full-width
/// arrow drawn over the name (the \vec itself is hidden, not removed).
/// ponytail: experimental — if editing misbehaves, swap back to TextField
/// in EntryRow (this type is self-contained for exactly that reason).
struct RichEntryField: View {
    @Binding var text: String
    var focus: FocusState<UUID?>.Binding
    let id: UUID
    let onCommit: () -> Void

    @State private var rich = AttributedString()
    @State private var arrowSpans: [ArrowSpan] = []

    // ponytail: calibration knobs — overlay alignment over TextEditor's
    // internal insets; tweak if arrows sit off their names
    private static let textLeadingInset: CGFloat = 5
    private static let arrowTopOffset: CGFloat = 0

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
            .overlay(alignment: .topLeading) {
                ForEach(arrowSpans) { span in
                    VecArrowShape()
                        .stroke(style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(.primary)
                        .frame(width: max(6, span.width), height: 6)
                        .offset(x: Self.textLeadingInset + span.x, y: Self.arrowTopOffset)
                        .allowsHitTesting(false)
                }
            }
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
        let built = Self.buildStyled(text)
        if rich != built.attr { rich = built.attr }
        if arrowSpans != built.spans { arrowSpans = built.spans }
    }

    // MARK: - Styling + measurement

    struct ArrowSpan: Equatable, Identifiable {
        var x: CGFloat
        var width: CGFloat
        var id: CGFloat { x }
    }

    private struct StyledLine {
        var attr = AttributedString()
        var spans: [ArrowSpan] = []
    }

    private static let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
    private static let baseNSFont = NSFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)
    private static let subNSFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private static let baseAdvance = ("0" as NSString).size(withAttributes: [.font: baseNSFont]).width
    private static let subAdvance = ("0" as NSString).size(withAttributes: [.font: subNSFont]).width
    private static let hiddenAdvance = ("0" as NSString).size(withAttributes:
        [.font: NSFont.monospacedSystemFont(ofSize: 1, weight: .regular)]).width

    private static let baseStyle = AttributeContainer().font(.system(.body, design: .monospaced))
    private static let subStyle = AttributeContainer()
        .font(.system(size: 10, design: .monospaced))
        .baselineOffset(-3)
    // Present in the string (it IS the notation) but rendered invisibly.
    private static let hiddenStyle = AttributeContainer()
        .font(.system(size: 1))
        .foregroundColor(.clear)
    // A \vec still waiting for its name: visible but dimmed.
    private static let pendingStyle = AttributeContainer()
        .font(.system(.body, design: .monospaced))
        .foregroundColor(.secondary)

    private static func isNameChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c.unicodeScalars.count > 1
    }

    /// One pass: builds the styled line and, for every hidden `\vec NAME`,
    /// records the measured x/width of the name for the arrow overlay.
    private static func buildStyled(_ raw: String) -> StyledLine {
        var line = StyledLine()
        let chars = Array(raw)
        var i = 0
        var x: CGFloat = 0
        var spanStart: CGFloat?

        func append(_ s: String, _ style: AttributeContainer, advance: CGFloat) {
            line.attr += AttributedString(s, attributes: style)
            x += advance * CGFloat(s.count)
        }

        func closeSpan() {
            if let start = spanStart, x > start {
                line.spans.append(ArrowSpan(x: start, width: x - start))
            }
            spanStart = nil
        }

        while i < chars.count {
            let c = chars[i]

            // \vec / \vector followed by whitespace: hide it, arrow the name.
            if c == "\\" {
                var j = i + 1
                var cmd = ""
                while j < chars.count, chars[j].isLetter { cmd.append(chars[j]); j += 1 }
                if cmd == "vec" || cmd == "vector" || cmd == "overrightarrow" {
                    var token = "\\" + cmd
                    while j < chars.count, chars[j] == " " { token.append(" "); j += 1 }
                    closeSpan()
                    if j < chars.count, isNameChar(chars[j]) {
                        // Name present: hide the command, arrow the name.
                        append(token, hiddenStyle, advance: hiddenAdvance)
                        spanStart = x
                    } else {
                        // Still typing: keep \vec visible (dimmed) until the
                        // name it decorates exists.
                        append(token, pendingStyle, advance: baseAdvance)
                    }
                    i = j
                    continue
                }
            }

            // _AB → true subscript (underscore hidden); digits alone are ₁ glyphs.
            if c == "_", i + 1 < chars.count, chars[i + 1].isLetter || chars[i + 1].isNumber {
                var j = i + 1
                var run = ""
                var sawLetter = false
                while j < chars.count, chars[j].isLetter || chars[j].isNumber {
                    if chars[j].isLetter { sawLetter = true }
                    run.append(chars[j])
                    j += 1
                }
                if sawLetter {
                    append("_", hiddenStyle, advance: hiddenAdvance)
                    append(run, subStyle, advance: subAdvance)
                    i = j
                    continue
                }
            }

            if spanStart != nil, !isNameChar(c) { closeSpan() }
            append(String(c), baseStyle, advance: baseAdvance)
            i += 1
        }
        closeSpan()
        return line
    }

    // MARK: - Live rendering

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

/// The over-name arrow: a line with an open head at the right.
private struct VecArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addLine(to: CGPoint(x: rect.maxX - 1, y: y))
        p.move(to: CGPoint(x: rect.maxX - 4, y: y - 2.4))
        p.addLine(to: CGPoint(x: rect.maxX - 1, y: y))
        p.addLine(to: CGPoint(x: rect.maxX - 4, y: y + 2.4))
        return p
    }
}
