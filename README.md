# Trihedron

Native macOS 3D vector visualizer for statics (and later dynamics) work.
Type vectors in standard notation on the left; they appear in the 3D
viewport on the right. Scalars (dot products, magnitudes, angles) show
inline; vectors and points draw in the scene — and so do graphs: `y = x^2`
is a curve in the xy plane, `z = x^2 + y^2` a surface (see Graphing below).

## Run

- `scripts/make-app.sh --install` → builds and installs `/Applications/Trihedron.app`
- or open the package in Xcode and run the `Trihedron` scheme
- `swift test` runs the engine + render test suite

## Notation

```
a = <1, 2, 3>              vector — arrow (or hat when |a| = 1) renders automatically
\vec F = cos(30)i + sin(30)j   component form; i j k (or î ĵ k̂) multiply implicitly
A = (0, 0, 4)              parentheses make a point ('point A = …' also works)
r_AB                       B − A once points A and B exist (drawn from A)
\hat u = unit(F)           defines û, distinct from u — must be a true unit vector
\vec T = 50∠30             2D polar: magnitude ∠ angle in degrees (also 50 @ 30)
m = 12.5                   scalars use plain names
# heading                  comment line

a + b   a - b   2*a        arithmetic
r = Rû                     hatted symbols juxtapose: R·û  (û finds u when |u| = 1)
a * b   a · b   dot(a,b)   dot product
a × b   cross(a,b)         cross product
|a|     mag(a)             magnitude
angle(a, b)                angle in degrees (draws the arc in-scene)
proj(a, b)  comp(a, b)     vector / scalar projection of a onto b
F.x  F.y  F.z              components
moment(r, F)               r × F
moment(axis, r, F)         scalar moment about an axis
resultant(F1, F2, …)       sum of forces
dist(A, B)  triple(a,b,c)  distance, scalar triple product
sin cos tan …              degree-based; asin/acos/atan/atan2 return degrees
sqrt ln log exp pi e       scalar math;  rad(x) / deg(x) convert
```

## Graphing

A definition whose right-hand side uses an axis name — `x`, `y` or `z` —
that nothing above has defined is a graph, drawn in the same viewport as
the vectors. The name on the left is the dependent axis and picks the plane:

```
y = x^2                    curve in the xy plane
z = sin(deg(x))            curve in the xz plane (see the note on degrees)
x = y^2                    curve in the xy plane, x as a function of y
z = ln(y)                  curve in the yz plane — undefined for y ≤ 0, so it starts at 0
z = x^2 + y^2              surface over the xy plane
y = sin(deg(x)) * z        surface over the xz plane
y = x^2, x in [-3, 3]      explicit domain (x ∈ [-3, 3] also parses)
z = x*y, x in [0, 2], y in [0, 2]
```

Without a domain a graph spans the current axes — the box the vectors and
points make, recomputed as they change — and is clipped to that box, so a
parabola never forces the axes to grow just because it was drawn. With a
written domain the whole range is drawn and the axes grow to fit it.
`x`, `y` and `z` are not reserved: once `x = 3` is defined, `y = x^2` is the
number 9 exactly as before. Only an *unbound* axis name graphs. Trig stays
in degrees everywhere, so `z = sin(x)` over ±5 is nearly flat; write
`z = sin(deg(x))` for the wave with period 2π. Points where the expression
is undefined (`ln` of a negative, `1/x` at 0) break the curve rather than
spike, and a surface simply has a hole there. Curves are sampled at 200
points, surfaces on a 60 × 60 grid. The result line reads `curve in xz, x in
[-5, 5]` or `surface z(x, y), …`; a graph line has no value, so `y` cannot
be used in arithmetic further down.

Conventions: z is up (statics style), trig is in degrees, `i j k π e origin`
are reserved. Notation is applied automatically as a teaching aid: defined
vectors get the arrow drawn over their name, unit vectors get the hat, and
the decoration follows the value — change an upstream variable and it flips.
Explicit marks still parse, and an explicit `\hat` name (û) must truly have
magnitude 1. The notebook re-evaluates top-to-bottom on every edit and
autosaves to `~/Library/Application Support/Trihedron/workspace.json`.
Typing a space (or Return) renders finished notation in place — \hat u → û,
\vec F → F⃗, \theta → θ, < > → ⟨ ⟩ — and Return again commits the line.
The rendered form is real syntax: û is a distinct variable, F⃗ ≡ F, Greek
letters are plain identifiers, and · × √ π ∠ all parse.
Arrow girth and labels rescale with camera zoom; the arrowheads toggle in
the toolbar draws vectors as plain lines.

## Layout

- `Sources/TrihedronCore` — lexer → parser → evaluator → `Engine.evaluate(lines)`; pure, UI-free
- `Sources/TrihedronScene` — SceneKit scene builder (arrows, points, arcs, axes, grid, camera)
- `Sources/Trihedron` — SwiftUI app (notebook + viewport + toolbar)
- `Tests/` — notation, evaluator, worked statics problems, offscreen render smoke test
