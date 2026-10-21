# Storage reads observe actual deletion and return full NONE

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, empty
storage writes, absent reads and full-width return registers; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author ReadMissing before original computation/signing. Delete key11 with an
invalid value pointer and zero length. Read the same self key with request3 and
an invalid maximum destination. Absence must return NONE without touching that
destination. Store all eight returned bytes at RW+3, then persist the eleven
bytes [21,22,23]+8xff. Compact load_imm with byteFF sign-extends to MAX64, checked
independently by the full eight-byte persisted return.

The original parent has no key: benign deletion, absent read and first creation.
The assured parent has the eleven-byte value: actual deletion, absent read and
restoration. A stale-parent read would find that value and panic at the invalid
destination. Actual Halt/Regular plus the full NONE word therefore proves the
read used current deleted state. No memory/response/report/terminal/source patch.

Only this mode receives original funding58/capture11 before root/signing/
computation. Its20 instructions/three hosts fit existing steps20/calls4 and
compact code below128 bytes; original gas10000 then20000 and all parameters
remain unchanged. Host costs2446+2410+2449=7305, plus one block at most997:
gas>7305and<=8302. Original and next actual gas must be equal.

Completion: one final key/eleven bytes for deletion plus restoration, footprint46/
item1/balance58/code retained, canonical timestamp3/history3/activity reports2/
actual gas/all29 parameters/aliases/finality1. Steps20 succeeds/19 refuses;
calls1/2 refuse at read/final write. Copy11 succeeds/10 refuses final write after
the smaller deletion/absent read fit. Final bytes10/key0 and zero captured-key
provenance refuse precisely. Run1000 full execution/composition/publication ARC
cycles, affected predecessors, semantic/tooling/inventory/format checks.

Next: retain a checkpointed deletion after input-controlled panic and a later
regular restoration. M1 framing complete; full state serialization, whole-block
parity and full chainspec equivalence remain open.

Observed local evidence: actual original and assured Halt/Regular persist
[21,22,23]+eight255 bytes. The assured parent has that existing key before actual
deletion; the subsequent read ignores its invalid destination and returns full
NONE. Pinned Omega_R in text/pvm_invocations.tex makes the absent output interval
empty and returns NONE, preserving memory. One final proof key/eleven bytes,
footprint46/item1/balance58/original code and equal actual gas within the
independent bounds are verified. Full canonical composition/publication,
parameters, aliases and finality checks pass.

Steps20 succeeds/19 refuses StepLimitExceeded; calls1/2 refuse
HostCallLimitExceeded. Copy11 succeeds/10 refuses DispatchFailure/LimitExceeded
at the final write. Final bytes10/key0 refuse Completion/Batch/LimitExceeded;
zero captured-key provenance refuses UnsupportedAccountEffects.

One thousand full successors retain753760/753760 occupied bytes. All ten
predecessor groups pass again at1000 cycles: storage tail754688, read754224,
branch687792, delete753424, fetch tail753792, ranges938352, list1459632,
individual inputs1406672, original storage2933856 and outcomes3162032 bytes
unchanged. Only guest factory, funding helper and original-execution helper
change among3464 predecessor inputs;3461 are identical. All four affected
semantic checks,35 tooling tests, inventory194 families/2436 probes/275 native
suites, and formatting2341 Nim sources plus Rust pass. Local checked-release
macOS evidence; remote CI remains separate.
