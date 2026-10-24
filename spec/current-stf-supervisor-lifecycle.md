# Whole-map supervisor reassignment lifecycle

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` supervisor 29/transfer 22 and `accounts.tex` effective supervisor.
Only the invoking account is reassigned; foreign-account publication guards remain.

Five originals hold one million tokens entirely in the source's protected pool.
A real report reassigns its own supervisor, then attempts a deferred protected-pool
transfer. Assigning another present supervisor immediately removes the caller's
protected-funding authority. Self-supervision retains it; a missing nominee leaves
the original effective self-supervision intact. Both controls send seven tokens.
Ordinary panic discards the reassignment; a checkpoint after reassignment retains
it. A later report proves the new authority state rather than resetting it: the
caller cannot reassign itself again after handing control to another supervisor.

Thirty complete signed transitions compare exact P/B/O, roots, stored supervisor
and incarnation, both funding pools, incoming credit, N/T/G, timestamps and no
replay. Host charges use independent instruction tables plus supervisor 1000,
transfer 575 and any actually offered gas; checkpoint 103 is charged only when called.
Full maps are calculated before native execution. Earlier fixtures, upstream vectors,
production logic and dependency pins are unchanged. M1 framing is complete;
account/request lifecycle and full JAM serialization/parity remain subsequent work.

Local checked ARC/Clang runs pass all 30 new transitions and existing supervised
transfer, balance-pool and upgrade regressions. Independent authority/conservation
and later-invocation invariants pass, with pinned formatting and inventory.
Local macOS evidence remains separate from exact-head Linux CI.
