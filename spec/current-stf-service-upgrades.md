# Whole-map service code upgrades

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` upgrade 21/checkpoint and `accumulation.tex` current-code lookup.
This layer covers self-upgrade; it does not bypass foreign-account publication gates.

Five originals reserve honest old/replacement code requests and physical preimages.
Three signed reports per chain show that an upgrade changes exactly the account's
code hash and minimum accumulation/transfer gas (100/19), then later invocations
select that new code. Halt and checkpoint-panic commit the upgrade; ordinary panic
retains the old program. An underfunded first host call consumes its 500 report gas,
leaves code unchanged, and the next funded report upgrades before a later halt.
A replacement with an unfulfilled request remains honestly absent: later reports
still process with N=1/G=0 and advance timestamps, preserving the committed hash.

Forty complete signed transitions compare exact P/B/O, roots, both code namespaces,
request histories/footprints, C13, minimum gas fields, timestamps and no replay.
Expected gas comes from independent instruction tables plus upgrade 1028 and actual
checkpoint 103; no observed successor or native gas enters the reference.
Original code preimages remain retained. Upstream vectors, earlier frozen fixtures,
production code and dependency pins are unchanged. M1 framing is complete; wider
supervisor/account lifecycle and full JAM serialization/parity remain open.

Local checked ARC/Clang validation passes all 40 upgrade transitions and prior
memo/late-code whole-map regressions. Independent code/threshold/request and
cross-block gas/timestamp invariants pass, as do pinned formatting and inventory.
These local macOS checks are distinct from exact-head Linux CI.
