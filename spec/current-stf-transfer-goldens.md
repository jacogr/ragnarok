# Whole-map deferred transfer goldens

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` transfer and checkpoint equations and `accumulation.tex` accseq.

The independent Python reference calculates twenty signed block transitions before
native execution. One report drives service 99; its real deferred transfer debits
seven tokens and a later transfer-only invocation credits service 42 exactly once.
Halt, panic rollback, checkpoint-panic retention, zero amount and a below-minimum
gas offer are separate authored originals. Full checkpoints, block octets, roots,
C13 N/T/G statistics, timestamps and empty C16 are compared exactly. Gas uses the
pinned independent instruction table plus literal transfer 575/checkpoint 103 costs.

Original upstream vectors and earlier fixtures remain unchanged. Component
transfer witnesses do not substitute for full block publication. Supervisor
conflicts, repeated forwarding and wider lifecycle cases remain subsequent work.
M1 framing is complete; full serialization and general JAM parity remain open.

Local verification uses checked ARC/Clang release builds and compares every P/B/O
line against the independent reference. The20 transfer transitions and35 original
report-guest regression transitions pass. The explicit recipient minimum is10;
historical fixtures retain their original maximum transfer minimum by default.
Production logic, dependency pins and upstream vectors remain unchanged.
