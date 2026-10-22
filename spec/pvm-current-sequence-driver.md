# Bounded current accumulation driver and terminal proof

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, accseq.
Drive genuine current history by repeatedly planning and executing the next entry.
Every success appends one flat fact; the execution entry ceiling bounds further
dispatch. Completion requires a genuine plan whose private dispatch observation
is false. Exact-capacity terminal completion needs no fake extra guest/history row.
An unaffordable report suffix may remain pending for a future block.

Provide one root entry point that executes the admitted initial cohort once and
then drives continuations with its frozen Parameters and frame. Require capacity
for the initial fact before guest work. Retain only genuinely failed initial,
planning or execution parents on refusal; never expose a successful prefix or
mutate caller state. A copied active-plan observation cannot forge completion.

The completed owner certifies recursive accumulation only. Final statistics,
last-accumulation timestamps, output/history and whole-block publication remain
separate and cannot consume it as a legacy completed-block owner.

Completion checks: signed three-entry flow and root/manual state parity, exact/
short history capacity, actual child failure preservation, zero-capacity/no-hash
preflight, active/default-plan refusal, unaffordable terminal suffix, private and
nominal owner boundaries, source lifetime and fresh ARC release.

Checked macOS ARC/Clang evidence passes signed three-entry/root-manual parity,
completion exactly at the entry ceiling, short-capacity refusal after private
progress, genuine initial/planning/execution parent reasons, zero-capacity/no-hash
preflight, active-plan copy rejection, unaffordable terminal suffix and source
immutability. The driver and affected continuation/input suites pass fresh
1,000-cycle ARC checks. All290 modules,11 runtime guards,6 compiler privacy/
terminal-vs-legacy checks, inventory and canonical formatting pass. Test policy
binding avoids a pinned formatter oscillation without semantic changes.
Logs: `build/current-sequence-driver-*`; exact-head Linux CI remains separate.
