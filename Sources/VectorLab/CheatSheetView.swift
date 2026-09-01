import SwiftUI

struct CheatSheetView: View {
    private let sections: [(String, [(String, String)])] = [
        ("Define", [
            ("a = <1, 2, 3>", "vector (also [1,2,3] or (1,2,3))"),
            ("\\vec F = 3i + 4j - 5k", "component form"),
            ("point A = (0, 0, 4)", "point, drawn as a dot"),
            ("r_AB", "B − A once points A, B exist"),
            ("\\hat u = unit(F)", "defines û — its own variable (also \\hat(u))"),
            ("F = cos(30)i + sin(30)j", "component form with trig"),
            ("T = 50∠30", "2D: magnitude ∠ angle°  (or 50 @ 30)"),
            ("# heading", "comment line"),
        ]),
        ("Operate", [
            ("a + b,  a - b,  2*a", "add, subtract, scale"),
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
            ("triple(a, b, c)", "a · (b × c)"),
        ]),
        ("Math", [
            ("sin cos tan  (degrees)", "asin acos atan atan2 → degrees"),
            ("sqrt  ln  log  exp  pi  e", "rad(x), deg(x) convert"),
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
                Text("Lines render as math notation when not being edited — click a line to edit its raw text.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .frame(width: 480, height: 460)
    }
}
