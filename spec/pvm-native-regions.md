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
Status: implementation and qualification in progress; no performance or readiness claim.

ARM follow-up: inspect remaining exits and accounting in the already connected region engine;
choose a separate bounded change from native evidence. Background compilation and relaxed gas
interruption are outside this experiment. No compiler/dependency pin or public default changes.
