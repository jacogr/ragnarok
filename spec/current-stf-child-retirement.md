# Whole-map funded child retirement

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, new20,
forget26 and eject23. Seven chains link actual reserved creation to reservation
cleanup, same-invocation retirement refusal and later successful deletion.

Registrar99 funds child77 with224 under7/item,1/byte,100/account, using all four
source/destination pool combinations. Its pending code request is forgotten,
releasing two items and110 bytes without fabricating a preimage. Eject still
refuses at creation slot4, even though the child is empty. A later report at6
finds77 occupied (no repeated new debit), then retires it and refunds both child
pools into99's liquid balance. Protected funding therefore returns as liquid.

Panic discards birth/cleanup/deletion/refund together. A checkpoint before eject
retains the empty child and excludes later retirement; a checkpoint after eject
retains deletion and refund. Complete maps prove no residual child namespaces,
no child participation, exact creator gas/timestamps and conservation throughout.

Forty-two signed transitions and independent chronology/pool/namespace invariants
are checked with the maintained ARC/Clang profile, affected creation/ejection
regressions, pinned formatting and inventory. Capture declares the known77 child
and permits only observed MissingKey for selected cleanup/deletion. Production
logic, pins and historical fixtures remain unchanged. Local macOS evidence is
separate from Linux CI; local checkpoint envelopes do not claim JAM wire parity.
