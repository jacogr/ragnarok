# Shared structural source intervals

`handler_stream.nim` privately shares a bounded source interval between the ARM macro-header
and x86 complete-source checks. `FlatSourceInterval` contains source first/last ordinals, source
span and the captured header charge. `flatSourceIntervalAt` borrows the current frame, checks
header array bounds, positive caller-capped span, widened fact extent and a final ending fact,
then copies those values. Failure leaves its output untouched. It allocates nothing and adds
no source-fact traversal.

This weak structural result is not complete-header, original-priced-block or child authority.
ARM retains its distinct result type, 64-source-fact cap, earlier-ending and leading-noop checks
and all role/child validation. X86 retains its 65-fact cap, packed-PC and priced-block identity,
original source count, interior ending/fallthrough, every-nonnoop site, handler-kind and exact
destination checks. A genuinely captured paid-interior suffix can have a valid interval while
x86 still refuses it as an original-priced complete target. Neither architecture's admission
policy or machine lowering changes.

Qualification uses only real immutable source and normal engine transitions. The read-only
five-scalar query under existing ARM macro-receipt/x86 source-witness gates adds no target
resolution or frame/plan mutator; its captured complete-entry mapping is an adapter check,
not part of the common interval contract. The gated x86 target query calls the actual complete
target predicate on copied observed coordinates.

`make unit SUITE=pvm_source_interval` covers 64/65 cap distinctions, leading/interior folded
noops, copied output preservation, missing captured PCs, literal scalar effects/source attempts,
and genuine paid suffixes. `pvm_x86_wide_default` retains its native positive controls and adds
an old terminal-coordinate check across genuine unpaid suffix capture and paid reentry, using its
existing sealed graph. Cached paid interior reentry reuses its body without emitting a new header;
a fresh paid entry can capture a suffix header before execution. Both paths remain unchanged.
Existing ARM macro/frame witnesses retain native child and full-state qualification. Captured
charge/bookkeeping parity does not replace an independent gas oracle.

Zero-length or inconsistent private captured arrays cannot be created through these immutable
public source paths. Their local guards remain explicit; qualification introduces no mutation
hook to fabricate those unreachable states. Source ownership and stream/child identity remain
with their existing boundaries, separate from this interval.
