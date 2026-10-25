# Lookup provenance and age after population changes

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, recent
report-anchor tuples, historical lookup headers and child-committed state roots,
inclusive lookup age, reporting/availability, Safrole and ready expiry.

Two complete three-core chains use explicit122-byte trusted parameters, including
lookup age14,400 and twelve-slot epochs. Each preserves the earlier six→nine→six
reporting prefix, then jumps to the exact age boundary of an old lookup from slot2
or13. Equality is accepted; the same lookup one slot later rejects while a fresh
lookup permits genuine replacement. Historical lookup context remains independent
of the recent eight-block anchor window and includes the actual header and its
newer child, which commits the historical posterior root.

Recent anchor state roots, lookup state roots, hashes and slots are separately
mutated, independently re-signed and re-sealed. Every exact refusal preserves the
complete canonical map and selected head. Large guarantee slots use separate
bounded authored payload identifiers; the actual slot and age fields retain their
full E4 values. The large epoch skip clears expired ready rows without changing
service namespaces.

Expected original maps, blocks, complete successors and roots derive independently
before native execution. Explicit trusted parameters accompany local scenario
inputs and are hashed separately from state roots. Their decoder never falls back
after failure. GP protocol wire encodings and pins remain unchanged; the scenario
request transport is test-only. No other client emits expected bytes.

Completion requires26 transitions and ten exact refusals, independent age/root/
parameter/prefix invariants, unchanged previous reporting answers, strict corpus
completeness, source inventory and pinned formatting. Full JAM/STF and external
client conformance remain separate.

Observed checked macOS ARM64 ARC/Clang non-LTO: all26 transitions and ten
exact refusals passed complete output comparison. The unchanged32-transition/
three-refusal ticket corpus passed. All42 scoped independent/runner tests,
source inventory and pinned formatting passed.
