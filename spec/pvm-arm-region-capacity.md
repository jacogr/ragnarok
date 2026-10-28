# Bounded ARM connected-region capacity trial

Independent draft stack1786, parent14105fe3d85be32dc98c9f6a584ef9dd903f0a99.
The rejected one-block admission remains excluded. This trial keeps the accepted observed
closed two/three-block admission, eight completed discovery visits, code generation, register
allocation, block gas/source guards and immutable invocation/publication semantics unchanged.

Hypothesis: eight append-only region records permit later useful loops to coexist with earlier
ones. Root records encode a one-based slot in their previously unused successor lane, preserving
12-byte per-node entries and constant-time execution lookup. Each root refuses independently;
no eviction, hotness ranking, worker thread or new opcode/shape admission is introduced.
A new region cannot capture another live region root as its canonical guard continuation.

The existing1,024 publication limit and1MiB arena remain fixed. Ordinary publications reserve
one slot for each remaining region (initially eight); each region image remains below1,024 words.
Metadata is a fixed eight-record array per exclusive stream. Failure preserves existing entries,
code and checked fallback. This explicit reservation tradeoff is part of the measured experiment.

Qualification requires the native/refused full opcode, register/memory, gas/source-budget,
host-event, source-snapshot and ownership gates. Literal tests fill all eight slots plus the
ordinary publication quota; independent guards/visit equations check320 calls across all roots,
unchanged old code after full-capacity/duplicate refusal, and mismatched proof metadata.
A root-local invalid-image refusal precedes valid admissions. Two disjoint loops in one stream
both require actual native region activity, then264 paid/gas/source-prefix comparisons retain
full state against the independent single-step oracle. One-block admission remains excluded.
Same-runner both-order full application cohorts compare the exact parent with candidate,
including constructor, cold, reused and core/lifecycle costs and the interpreted reference.
All native work runs only on CI. Keep only qualified useful benefit without material regressions;
otherwise restore this runtime trial and preserve useful rejection evidence.

Status: implementation prepared; native correctness and paired performance qualification pending.
