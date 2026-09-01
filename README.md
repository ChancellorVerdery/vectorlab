# VectorLab

Native macOS 3D vector visualizer for statics (and later dynamics) work.
Type vectors in standard notation on the left; they appear in the 3D
viewport on the right. Scalars (dot products, magnitudes, angles) show
inline; vectors and points draw in the scene.

## Run

- `scripts/make-app.sh --install` → builds and installs `/Applications/VectorLab.app`
- or open the package in Xcode and run the `VectorLab` scheme
- `swift test` runs the engine + render test suite

## Notation

```
\vec a = <1, 2, 3>         vector — the \vec mark (or typed arrow a⃗) is required
\vec F = cos(30)i + sin(30)j   component form; calls multiply into i j k implicitly
point A = (0, 0, 4)        point, drawn as a dot
r_AB                       B − A once points A and B exist (drawn from A)
\hat u = unit(F)           defines û, distinct from u — must be a true unit vector
\vec T = 50∠30             2D polar: magnitude ∠ angle in degrees (also 50 @ 30)
m = 12.5                   scalars use plain names
# heading                  comment line

a + b   a - b   2*a        arithmetic
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

Conventions: z is up (statics style), trig is in degrees, `i j k π e origin`
are reserved. Strict notation is enforced as a teaching aid: a definition
holding a vector needs the `\vec`/arrow mark, and a hatted name (û) must
have magnitude 1 — the error messages show the correct form. The notebook re-evaluates top-to-bottom on every edit and
autosaves to `~/Library/Application Support/VectorLab/workspace.json`.
While editing, press Return once to render your notation as math in place
(\hat u → û, \vec F → F⃗, < > → ⟨ ⟩); press Return again to finish the line.
The rendered form is real syntax — û is a distinct variable, F⃗ ≡ F, and
· × √ π ∠ all parse. Unfocused lines always render as math; click to edit.
Arrow girth and labels rescale with camera zoom; the arrowheads toggle in
the toolbar draws vectors as plain lines.

## Layout

- `Sources/VectorLabCore` — lexer → parser → evaluator → `Engine.evaluate(lines)`; pure, UI-free
- `Sources/VectorLabScene` — SceneKit scene builder (arrows, points, arcs, axes, grid, camera)
- `Sources/VectorLab` — SwiftUI app (notebook + viewport + toolbar)
- `Tests/` — notation, evaluator, worked statics problems, offscreen render smoke test
