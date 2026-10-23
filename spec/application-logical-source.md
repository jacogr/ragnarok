# Fixed current logical source observations

The existing guarded CurrentLogicalResult now exposes exact original `currentLogicalUpdate`,
fixed full `currentLogicalContext` and cached `currentLogicalViewInfo`. Each refuses default owners
and retains only original immutable producer provenance. These observations are hash-free and avoid
heavy ordered-view/header/index copies. Consumers admit retention before taking heavy views; copied
context preserves the full original Parameters, physical snapshot and child identity. All aliases
remain subject to the plain ARC host lease contract. They add no supplied identity propagation,
trusted-root selection, installation or finality. The native suite checks genuine collected
qualification, exact original context and default/hash-free observations.
