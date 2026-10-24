# Whole-map request solicitation and forgetting

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` solicit25, forget26 and exceptional checkpoint selection.

Five originals cover solicitation, immediate forgetting, forgetting an original
pending request before checkpoint then discarding its recreation, panic rollback,
and checkpoint-panic retention. R is an explicit one-byte payload distinct from
code and existing I/Q requests. A pending reservation contributes exactly two
items and82 bytes; no preimage or availability history is invented. Repeated
report releases at4/6 check idempotence and later selected namespace retention.

Thirty signed transitions compare full original/block/successor bytes, complete
roots, requests, footprints, timestamps and N/T/G. The native qualifier observes
only explicitly authored identities and canonical histories; MissingKey is
accepted only as actual removal, with independent exact-map comparison deciding
presence. Four request observations bound the checkpoint/recreation path.

All30 checked ARC/Clang transitions and independent footprint/presence invariants
pass locally on macOS. Pinned formatting and inventory pass; Linux CI is separate.
Production logic, pins and historical fixtures remain unchanged. M1 framing is
complete; provision, ejection and broader serialization/parity remain next.
