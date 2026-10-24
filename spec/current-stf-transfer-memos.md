# Whole-map memo-driven transfer effects

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
Appendix C.2 transfer framing and `pvm_invocations.tex` fetch/write/yield/checkpoint.

A real report-driven transfer carries all 128 distinct memo octets into service 42.
The recipient fetches the canonical whole input list or single item and writes
and yields exactly 32 fetched bytes. Both selectors recover the same first 32 memo
octets with their different framing offsets; independent fetch charges differ by 66.
A tail slice crosses the last 16 memo bytes into E8 gas and is clamped, retaining
eight initialized sentinel bytes. This makes input encoding and partial-copy
semantics visible in the complete storage map, C16 and recent-history/MMR output.

Halt, panic rollback and checkpoint-panic independently select storage/yield
retention while preserving incoming credit. The retained write adds one item and
67 footprint bytes. All 20 signed transitions and exact P/B/O checkpoints are
calculated before native execution, including N/T/G, timestamps and the next
empty block's no-replay/C16-clearing behavior. The maintained driver declares key 7
for either explicit service; unrelated namespace identities remain unchanged.

Earlier fixtures, upstream vectors, production logic and dependency pins remain
unchanged. M1 framing is complete; service lifecycle follows this transfer work,
while full JAM serialization and external trace parity remain open.

Local checked ARC/Clang validation passes all 20 new transitions and prior
report-guest, forwarding and admission regressions. Independent byte-slice,
footprint/output and gas invariants pass, as do pinned formatting and inventory.
This local macOS evidence is distinct from exact-head Linux CI.
