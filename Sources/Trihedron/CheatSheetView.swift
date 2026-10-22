import SwiftUI

struct CheatSheetView: View {
    private let sections: [(String, [(String, String)])] = [
        ("Define", [
            ("a = <1, 2, 3>", "vector — the arrow (or hat if |a| = 1) appears automatically"),
            ("\\vec F = 3i + 4j - 5k", "component form — î ĵ k̂ work too, trig works: cos(30)i"),
            ("A = (0, 0, 4)", "parentheses make a point (the point keyword is optional)"),
            ("r_AB", "B − A once points A, B exist"),
            ("\\hat u = unit(F)", "û — must be a true unit vector (|û| = 1 enforced)"),
            ("\\vec T = 50∠30", "2D: magnitude ∠ angle°  (or 50 @ 30)"),
            ("m = 12.5", "scalars use plain names"),
            ("\\theta  \\alpha  \\Omega …", "Greek letters (θ, α, Ω) — real variable names"),
            ("F_1,  x^2  →  F₁,  x²", "digit sub/superscripts render as you type"),
            ("# heading", "comment line"),
        ]),
        ("Operate", [
            ("a + b,  a - b,  2*a", "add, subtract, scale"),
            ("Rû,  5î", "juxtaposition multiplies — û refers to u when |u| = 1"),
            ("a * b   or   a · b", "dot product"),
            ("cross(a, b)  or  a × b", "cross product"),
            ("|a|   or   mag(a)", "magnitude"),
            ("unit(a)", "unit vector"),
            ("angle(a, b)", "angle in degrees, draws the arc"),
            ("proj(a, b),  comp(a, b)", "projection of a onto b (vector / scalar)"),
            ("F.x,  F.y,  F.z", "components"),
        ]),
        ("Statics", [
            ("moment(r, F)", "M = r × F"),
            ("moment(axis, r, F)", "scalar moment about an axis"),
            ("resultant(F1, F2, …)", "sum of forces"),
            ("dist(A, B)", "distance between points"),
            ("point(v),  vector(A)", "convert vector ↔ point"),
            ("triple(a, b, c)", "a · (b × c)"),
        ]),
        ("Math", [
            ("sin cos tan  (degrees)", "asin acos atan atan2 → degrees"),
            ("sqrt  ln  log  exp  pi  e", "rad(x), deg(x) convert"),
        ]),
        ("Graph", [
            ("y = x^2", "an unbound x, y or z on the right makes a graph — this curve lies in the xy plane"),
            ("z = x^3 - x,   x = y^2", "the axis on the left is the dependent one: xz plane, xy plane"),
            ("z = x^2 + y^2", "two free axes make a surface"),
            ("y = x^2, x in [-3, 3]", "domain (∈ works too); otherwise it spans the axes"),
            ("z = sin(deg(x))", "trig is in degrees, so deg(x) gives the radian-style wave"),
            ("x = 3   then   y = x^2", "a defined x is just a number — y is 9, not a curve"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(sections, id: \.0) { title, rows in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            ForEach(rows, id: \.0) { syntax, meaning in
                                GridRow {
                                    Text(syntax)
                                        .font(.system(.callout, design: .monospaced))
                                    Text(meaning)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Text("Hitting space or Return renders finished notation in place (\\hat u → û, \\theta → θ); Return again commits the line and starts the next one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .frame(width: 480, height: 460)
    }
}
