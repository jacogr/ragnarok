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


## ARM one-block admission trial

Independent second layer: reuse the accepted resident ARM emitter for one observed self-loop,
in addition to its existing two/three-block regions. Gas/source guards, register allocation,
code storage and five-word context ABI are unchanged. Inactive proof/counter lanes remain empty;
only actual source blocks are charged. Independent source-step comparisons require actual native
region counters and cover1920 ordinary/specialized-header paid/gas/prefix/initial-value boundaries, with forced refusal.

The normal comparison can now take the same explicit pinned parent on ARM as x86; an empty
input retains the previous current-source A/A control. This avoids interpreting a current/current
ARM control as a paired optimization result. All native verification and timings remain on CI.
Status: pending; no claimed gain and no decision to keep either runtime trial yet.


ARM admission witness refinement: the `131 + 88` shape uses an existing specialized charge
worker and is intentionally excluded by ordinary-header identity checks. It remains a negative
region-admission witness with complete state coverage. A `149 + 172` ordinary header supplies
the actual positive self-loop witness. No runtime admission was broadened to make a test pass.
The maintainer approved expressing existing control-count minima in completed-block units:
CI at581c5b57 showed3 branch entries /2 header entries including one region completing17 blocks.
Replacing one aggregate entry by those17 completed blocks preserves the original4/3 thresholds;
all independent CPU/gas/PC/host/fault/source checks remain unchanged.


## ARM measured rejection

The isolated self-loop runtime is rejected after full qualified Linux measurements: DOOM
initialization regresses64–65% and loses almost all of the useful large-region native coverage.
[Exact-head tables and evidence](pvm-arm-regions-results.md) retain the trial and failure analysis.
ARM runtime is restored byte-for-byte from the accepted immediate parent. The useful paired
comparison support and full-state one-block refusal witnesses remain. No assertion or timeout
was weakened to keep this runtime. Both PRs remain draft in independent stack1786.
