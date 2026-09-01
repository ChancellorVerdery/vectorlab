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
a = <1, 2, 3>              vector  (also [1,2,3], (1,2,3), ⟨1,2,3⟩, \langle…\rangle)
\vec F = 3i + 4j - 5k      component form
point A = (0, 0, 4)        point, drawn as a dot
r_AB                       B − A once points A and B exist (drawn from A)
u = unit(F)                unit vector
T = 50∠30                  2D polar: magnitude ∠ angle in degrees (also 50 @ 30)
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
are reserved. The notebook re-evaluates top-to-bottom on every edit and
autosaves to `~/Library/Application Support/VectorLab/workspace.json`.

## Layout

- `Sources/VectorLabCore` — lexer → parser → evaluator → `Engine.evaluate(lines)`; pure, UI-free
- `Sources/VectorLabScene` — SceneKit scene builder (arrows, points, arcs, axes, grid, camera)
- `Sources/VectorLab` — SwiftUI app (notebook + viewport + toolbar)
- `Tests/` — notation, evaluator, worked statics problems, offscreen render smoke test
