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
    var decoration: LineDecoration?
    let onCommit: () -> Void

    @State private var rich = AttributedString()
    @State private var arrowSpans: [ArrowSpan] = []

    // ponytail: calibration knobs — overlay alignment over TextEditor's
    // internal insets; tweak if arrows sit off their names
    private static let textLeadingInset: CGFloat = 5
    private static let arrowTopOffset: CGFloat = -2   // capitals reach higher than lowercase

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
            .onChange(of: decoration) { syncFromRaw() }
            .onAppear { syncFromRaw() }
            .overlay(alignment: .topLeading) {
                ForEach(arrowSpans) { span in
                    Group {
                        if span.kind == .hat {
                            HatShape()
                                .stroke(style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                        } else {
                            VecArrowShape()
                                .stroke(style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                        }
                    }
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
        let built = Self.buildStyled(text, decoration: decoration)
        if rich != built.attr { rich = built.attr }
        if arrowSpans != built.spans { arrowSpans = built.spans }
    }

    // MARK: - Styling + measurement

    struct ArrowSpan: Equatable, Identifiable {
        enum Kind: Equatable { case arrow, hat }
        var x: CGFloat
        var width: CGFloat
        var kind: Kind = .arrow
        var id: CGFloat { x }
    }

    /// Exposed to tests (pass 10): this is the only place the on-screen string
    /// is rebuilt, and its plain characters are written back into `text`.
    struct StyledLine {
        var attr = AttributedString()
        var spans: [ArrowSpan] = []
    }

    private static let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
    private static let baseNSFont = NSFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)
    private static let subNSFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    /// `hiddenStyle` declares `.system(size: 1)` with NO design, so the font
    /// that actually lays it out is the PROPORTIONAL system font. Measuring it
    /// with the monospaced one (which is what this did until pass 13) puts
    /// every arrow after a `\vec ` 0.70pt too far right, 1.77pt after a
    /// `\overrightarrow `. Mirror the declaration exactly.
    private static let hiddenNSFont = NSFont.systemFont(ofSize: 1)

    /// Real advance of `s` in `f`. Pass 13 replaced the old `advance × count`
    /// model with this: monospace is not a promise about every glyph, only
    /// about the ones the font has. Subscript digits (₀-₉) and ∠ fall back
    /// 0.21pt narrow, and a combining arrow (F⃗, which the lexer accepts as
    /// `\vec F`) reflows its base character by up to 1.60pt. Counting
    /// characters cannot see any of that; measuring cannot miss it.
    ///
    /// Cached because this runs per character, per keystroke: measuring an
    /// unrealistically long 63-character line costs 418µs cold and 32µs warm.
    /// `NSCache` rather than a dictionary so no isolation is claimed that the
    /// call sites (SwiftUI body, and the tests) do not already have.
    private static let advanceCache = NSCache<NSString, NSNumber>()

    static func width(_ s: String, _ f: NSFont) -> CGFloat {
        let key = "\(f.fontName)|\(f.pointSize)|\(s)" as NSString
        if let hit = advanceCache.object(forKey: key) { return CGFloat(hit.doubleValue) }
        let w = (s as NSString).size(withAttributes: [.font: f]).width
        advanceCache.setObject(NSNumber(value: Double(w)), forKey: key)
        return w
    }

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

    /// One pass: builds the styled line, records explicit `\vec NAME` arrow
    /// spans, and tracks every name run so the engine-derived decoration
    /// (arrow / unit hat) can be drawn over the defined name automatically.
    static func buildStyled(_ raw: String, decoration: LineDecoration?) -> StyledLine {
        var line = StyledLine()
        let chars = Array(raw)
        var i = 0
        var x: CGFloat = 0
        var spanStart: CGFloat?

        // Name-run tracking for automatic decoration.
        var runStartX: CGFloat?
        var runs: [(x: CGFloat, width: CGFloat, endPos: Int)] = []
        var eqPos: Int?
        var charPos = 0

        func beginRun() { if runStartX == nil { runStartX = x } }
        func endRun() {
            if let sx = runStartX, x > sx { runs.append((sx, x - sx, charPos)) }
            runStartX = nil
        }

        func append(_ s: String, _ style: AttributeContainer, font: NSFont) {
            line.attr += AttributedString(s, attributes: style)
            x += width(s, font)
        }

        func closeSpan() {
            if let start = spanStart, x > start {
                line.spans.append(ArrowSpan(x: start, width: x - start, kind: .arrow))
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
                    endRun()
                    if j < chars.count, isNameChar(chars[j]) {
                        // Name present: hide the command, arrow the name.
                        append(token, hiddenStyle, font: hiddenNSFont)
                        spanStart = x
                    } else {
                        // Still typing: keep \vec visible (dimmed) until the
                        // name it decorates exists.
                        append(token, pendingStyle, font: baseNSFont)
                    }
                    charPos += token.count
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
                    beginRun()
                    append("_", hiddenStyle, font: hiddenNSFont)
                    append(run, subStyle, font: subNSFont)
                    charPos += 1 + run.count
                    i = j
                    continue
                }
            }

            if isNameChar(c) {
                beginRun()
            } else {
                endRun()
                if spanStart != nil { closeSpan() }
                if c == "=", eqPos == nil { eqPos = charPos }
            }
            append(String(c), baseStyle, font: baseNSFont)
            charPos += 1
            i += 1
        }
        closeSpan()
        endRun()

        // Automatic notation: decorate the defined name (last run before =)
        // per the engine's verdict — hat for unit vectors, arrow otherwise.
        if let decoration, let eq = eqPos,
           let nameRun = runs.last(where: { $0.endPos <= eq }) {
            let kind: ArrowSpan.Kind = decoration == .unitHat ? .hat : .arrow
            line.spans.removeAll {
                $0.x < nameRun.x + nameRun.width && nameRun.x < $0.x + $0.width
            }
            line.spans.append(ArrowSpan(x: nameRun.x, width: nameRun.width, kind: kind))
        }
        return line
    }

    // MARK: - Live rendering

    /// A \command still waiting for the space that completes it: \theta,
    /// \hat(a), \vec F. Compiled once — liveRender runs on every keystroke.
    private static let trailingCommand = /\\[a-zA-Z]+(\s*[({]?[\p{L}\p{N}_]*[)}]?)?$/

    /// What a space keystroke turns `new` into, or nil to leave it alone.
    /// Extracted from `liveRender` so it is testable on its own: `liveRender`
    /// needs a live FocusState binding, this needs nothing.
    ///
    /// The space swallows itself only when it COMPLETED the trailing
    /// \command. Testing `pretty(body) != body` is not that question: any
    /// unrelated rewrite elsewhere on the line — `*`→`·`, `pi`→`π`, `@`→`∠` —
    /// also makes it true, and then the user's space vanished while `\hat`
    /// was still waiting for its name. The next keystroke glued onto the
    /// command (`\hatu`) and the line stopped parsing, permanently, on an
    /// ordinary one: `\vec F = 3*\hat u`. So ask the real question — is the
    /// trailing command still pending after the rewrite? — and if it is, put
    /// the space back.
    static func spaceCompletion(_ new: String) -> String? {
        guard new.hasSuffix(" ") else { return nil }
        let body = String(new.dropLast())
        guard let pending = body.firstMatch(of: trailingCommand) else { return nil }
        let pretty = MathPrint.pretty(body)
        guard pretty != body else { return nil }
        let stillPending = pretty.firstMatch(of: trailingCommand).map { String(pretty[$0.range]) }
        return stillPending == String(body[pending.range]) ? pretty + " " : pretty
    }

    /// What one keystroke turns `new` into, or nil to leave the text alone.
    /// This is the WHOLE decision `liveRender` makes, guards included, pulled
    /// out for the same reason pass 11 pulled out `spaceCompletion`: the only
    /// thing a test cannot supply is the live `FocusState` binding. Passes
    /// 8-11 each left "the guards are untested" in the handoff; they are
    /// testable now.
    ///
    /// The two guards mean END-OF-LINE typing only. An insertion or a delete
    /// anywhere else fails `hasPrefix` or the count, and the line is left
    /// exactly as the user edited it until Return runs `pretty` over it.
    static func keystrokeRewrite(old: String, new: String) -> String? {
        guard new.count == old.count + 1, new.hasPrefix(old) else { return nil }
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }

        if new.hasSuffix(" ") { return spaceCompletion(new) }
        let scripted = MathPrint.applyScripts(new)
        return scripted != new ? scripted : nil
    }

    /// Space completes a \command (\theta, \hat(a)) and swallows itself;
    /// _1 / ^2 become the script glyph the moment the digit lands.
    private func liveRender(old: String, new: String) {
        guard focus.wrappedValue == id else { return }
        if let rewritten = Self.keystrokeRewrite(old: old, new: new) { text = rewritten }
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

/// The unit-vector hat: a centered ^ over the name, no wider than the name.
private struct HatShape: Shape {
    func path(in rect: CGRect) -> Path {
        let half = min(4, rect.width * 0.45)
        var p = Path()
        p.move(to: CGPoint(x: rect.midX - half, y: rect.maxY - 1))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY + 1))
        p.addLine(to: CGPoint(x: rect.midX + half, y: rect.maxY - 1))
        return p
    }
}

/// The over-name arrow: a line with an open head at the right. The head
/// scales with span width so one-letter names (B, T, F) get a small neat
/// head instead of a chevron half the arrow's length.
private struct VecArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let head = min(3, rect.width * 0.32)
        let barb = head * 0.7
        var p = Path()
        let y = rect.midY
        let tip = rect.maxX - 0.5
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addLine(to: CGPoint(x: tip, y: y))
        p.move(to: CGPoint(x: tip - head, y: y - barb))
        p.addLine(to: CGPoint(x: tip, y: y))
        p.addLine(to: CGPoint(x: tip - head, y: y + barb))
        return p
    }
}
