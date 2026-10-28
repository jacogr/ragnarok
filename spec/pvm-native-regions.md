# Connected native region experiment

Independent experiment stack rooted at `f45793f6bfe92d38488b52898652e5dfb49ddbdb` through the
PR-free `codex/pvm-jit-regions/base` branch. The queued default stack is not modified or extended.
Gray Paper, gas, stepping, host and handler-stream contracts remain unchanged.

First hypothesis: one observed closed one/two-block pure x86 loop can eliminate repeated
Nim/C/native returns while keeping whole-block gas and source quotas exact. Existing arithmetic
loads/stores remain unchanged so register retention is measured separately. Each block guards
source quota and gas before mutation. A guard returns the untouched header for canonical
partial/paid/out-of-gas handling. Every completed block records its source endpoint. No memory,
host call, dynamic branch or invocation pointer is compiled into the region. One append-only
region per exclusive stream, existing storage ceilings and native refusal remain bounded.

Required evidence: actual native region counters; reused frames and source snapshots; one/two
block paths with each external edge; exact zero/partial/full budgets, gas limits, paid reentry,
unsigned64 gas; full native/refusal opcode/memory/host/ownership gates. Same-runner both-order
public application comparison against the pinned parent, including cold/preparation/publication.
All native work stays on CI. Keep only a useful measured benefit without material regressions.
Status: retain x86 after four qualified paired cohorts and fresh-process validation;
[paired results and limitations](pvm-x86-regions-results.md) preserve exact measured heads.
Stable gains are claimed for sieve; process outliers and other workload limits remain explicit.

ARM follow-up: inspect remaining exits and accounting in the already connected region engine;
choose a separate bounded change from native evidence. Background compilation and relaxed gas
interruption are outside this experiment. No compiler/dependency pin or public default changes.


## Bounded fresh-process validation

A second x86 cohort at5ba781f7 confirms sieve gains and does not reproduce the first cold
Pinky outlier, but shows initialization slower in one process order. Subsequent qualified
replication shows overlapping parent/current distributions and supports retaining x86. Manual `jit-x86-replay` runs the unchanged complete70-process cohort and refusal controls,
then36 additional processes /468 complete checked calls across init/minimal/Pinky and paired
parent/current roles. Six fresh processes per role/case alternate relative order, reuse only the
sealed admitted binaries/inputs, and must match native activity exactly except compilation CPU.
Report process-median distributions separately from within-process reused samples and cold/owner
costs. Ordinary CI and the existing scoped-profile dispatch are unchanged. No runtime change is
mixed into this validation. Native code remains CI-only.
