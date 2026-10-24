# Bounded deterministic light-evidence retention

Scope: storage-only soft retention ceilings over the existing immutable light snapshot and
independently accepted complete root. Authority remains the pinned Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` Merklization and the
[proof contract](storage-light-state-proofs.md). V1 formats, hard resource policies,
compiler/provider pins and application/startup gates remain unchanged.

`LightRetentionLimits` supplies explicit per-call item, logical raw-value and complete encoded
image byte ceilings, plus source-entry scan and eviction-count allowances. All soft ceilings
must fit the exact inherited hard policy. The complete empty-image overhead must fit even when
retaining no queries. Source scan and descriptor capacities are checked before scratch allocation.
Incoming proofs plus actual removals share the inherited mutation allowance.

`planLightRetention(snapshot, proofs, limits)` is a crypto-free advisory planner. It checks
incoming cardinality/shape and duplicate identities, releases replaced old charges, then accounts
for the complete final set. Incoming query identities are protected. When necessary it removes
unprotected old queries in ascending canonical serialized-key order until all three soft ceilings
fit. It never skips a canonical candidate to favor another quota: the result is deterministic,
without wall clocks, access history or hidden mutable reader state. An incoming set that cannot
fit, or insufficient scan/eviction/mutation allowance, returns a typed refusal without a plan.
A successful opaque plan exposes guarded `len` and independently mutable `forgottenKeys` copies.
It retains no source image, proof batch, native owner or root-selection authority.

`admitRetained(snapshot, proofs, limits)` plans, then uses the existing combined immutable update
to verify incoming proofs and produce one final canonical image. The planner does not authenticate
proofs. A changed-root, malformed or backend-refused proof cannot evict anything. Preparation
preserves the exact chain/root and hard policy; retained old proof bytes are not rehashed. Empty
incoming input may explicitly trim old knowledge. An already-fitting empty edit is a hash-free
no-op. Read-only snapshots can use a fitting no-op but cannot trim or admit beyond zero writes.

Present-empty and authenticated Absent consume entries and encoded proof bytes. Eviction changes
local knowledge to UnknownKey, never authenticated absence. Retained readers, cursors and caller
inputs stay independent. Limits bound logical work and representation, not total process RSS or
the caller's history of retained snapshots. Canonical eviction is an explicit opt-in policy;
existing manual admission and forgetting retain their behavior. Durable journal admission and
bounded maintenance are subsequent review units on the same stack.

Completion checks compare canonical outputs/removal choices with an independent small-map model
across incoming subsets and resource ceilings. They also cover exact mutation/scan/removal limits,
replacements at capacity, protected incoming keys, zero/read-only inputs, caller mutation, stale
positive/negative and present-empty semantics, each observed provider failure, typed default/
privacy guards, retained readers, and 1,000 scoped successful/failing ARC cycles.

Local checked ARC/Clang ThinLTO evidence: all 2,304 incoming-subset/quota model cases pass.
One thousand successful/copy/late-provider-refusal cycles retain 39,952 occupied bytes
before/after. Four runtime guards, three real successful controls and two strict privacy
rejections pass. Existing incremental-update, atomic-batch and selective-export suites pass.
Full pinned formatting and inventory pass. These results are local macOS arm64 evidence;
exact-head Linux checks and hardware power-loss qualification remain distinct.
