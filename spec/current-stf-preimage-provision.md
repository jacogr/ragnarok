# Whole-map queued preimage provision

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` provide28, forget26, checkpoint selection, fnprovide and C13 statistics.

Five explicit R-request originals cover ordinary provision, panic discard,
checkpoint-panic retention, forgetting before provision and forgetting after
queueing provision. The final provision step rechecks request relevance after
selected account changes. An irrelevant queued pair never creates an orphan P.
Retained provision fulfills the request with history[4]; a later report cannot
replace that first availability slot. Its reserved footprint stays unchanged.
Forgotten requests release exactly two items and82 bytes. VM provision contributes
N/G but no extrinsic preimage count or bytes in C13.

Thirty signed transitions compare exact originals, block bytes, full checkpoints
and roots, metadata, namespaces, histories, timestamps and activity. One-byte
provision capture and union limits are explicit in initial/continuation rounds.
Post-qualification declares only R and original namespace identities.

Checked ARC/Clang native cases and independent relevance/history/footprint and
statistics invariants pass locally on macOS, alongside request regressions,
pinned formatting and inventory. Linux CI remains separate. Existing fixtures,
production logic and all dependency pins remain unchanged. M1 framing is complete;
ejection and broader serialization/parity are subsequent work.
