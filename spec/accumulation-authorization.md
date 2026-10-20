# Accumulation-bound authorization pools

## Scope and authority

Bind [authorization-pool advancement](authorization-transition.md) to the exact
[lookup-preimage candidate](accumulation-preimages.md). Authority remains GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, authorization.tex SHA-256
`9873bce01eeb25d657aa32955e3f487388eeb6029128ffebb7ae312b0af1ca81`, pool-update equation and
notation's oldest-match subtraction/newest suffix. Reuse the existing single codec and algorithm.
No pins, wire widths, signing domains or PVM behavior change.

## Contract

Only PreparedAccumulationPreimages can construct PreparedAccumulationAuthorization. Retain that
exact source and derive its admitted report/credential/block graph. Use C(1) from the original
admitted parent, C(2) from the exact retained complete successor, the authenticated header slot and
source frame core count. Copy core/authorizer pairs only from the source's verified incoming
guarantees; newly available reports are not guarantee usage. No caller-selected source map, slot,
core population, projection or use list is accepted.

Callers supply only independent guarantee-descriptor, per-input hash/byte and output hash/byte
ceilings. Bound full-width counts/native descriptor extents and raw chapter lengths before copying
or allocating. Decode both exact chapters under source-derived cores and input policies. Refuse
missing, malformed and suffixed chapters rather than guessing queues or repairing state. Call the
existing pure transition with output policies: oldest-only used-hash removal, one posterior queue
item at slot modulo 80, newest-eight suffix and preserved duplicates/order.

Fork the exact preimage successor under inherited store ceilings and atomically replace C(1)
only. Retain source, copied slot/core/use/encoded-byte observations, independent canonical entry
and immutable complete successor. Entry queries copy bytes; defaults/refusals contain reasons
alone, with separately guarded codec, pure transition and store causes. No earlier source is
mutated, no guest/provision/statistics replay occurs, and C(2) remains unchanged.

This remains a supported report-only private candidate. The retained C(2) is the supported merger's
posterior value; this wrapper does not remove gates for unsupported queue/privilege effects.
Transfer recursion, remaining account/privilege effects, whole-block coordination/publication and
light-state proofs remain separate. M1 framing is complete; full state serialization and
accumulation/block parity remain open.

## Completion tests

Build genuine signed empty, incoming-only, available-only and combined lookup/guest histories.
Author nonzero ordered queues, empty/full pools and repeated used hashes before signing. Freeze
literal C(1) bytes and independently reconstructed complete-map roots for no use, oldest duplicate
removal, newest-eight truncation and queue wraparound. Preserve C(2), earlier C(3/13/14/15/16),
preimages, request histories, metadata/timestamps and opaque entries; prove retained original-parent
and source ownership, reusable preparation, copied observations/entry and detached lifetime.

Exercise missing/truncated/suffixed posterior queues, independent exact/one-below input/output/
guarantee policies and full-width policies. Reject default and detached source types; early
refusals must not hash. Inject immediate and late private Merkle failure, preserve source root/bytes
and retry. Require 1,000 ARC success/refusal cycles, strict runtime extraction/privacy/nominal
compiler guards, selected native checks, affected fixture consumers, Python/inventory and pinned
formatting. Reuse unchanged authorization vectors/algorithm and lower-layer execution evidence.

## Local verification

Passed `make unit SUITE=accumulation_authorization`: genuinely signed empty, incoming-only,
available-only and combined histories match literal C(1) entries and independently reconstructed
complete-map roots. Nonzero queue items distinguish slot positions 79, 80 and 81. Empty pools,
full pools, oldest-only duplicate use removal and newest-eight truncation pass. An available-only
report does not consume a pool member. Real earlier guest provisions, lookup preimages and every
C(2/3/13/14/15/16), account/request and opaque source entry remain unchanged.

Independent guarantee, input-byte/hash and output-byte/hash refusals occur before hashing with
selected early/codec/transition causes; exact and full-width limits pass. Missing, truncated and
suffixed posterior queues refuse with their intended store/codec reasons. Immediate and final
Merkle failures preserve source roots/pools and permit retry. Source reuse, detached lifetimes,
copied entry/facts and 1,000 ARC success/early-refusal/late-refusal cycles pass, retaining 1,475,344
occupied bytes before and after.

Nine strict runtime extraction guards and five compiler privacy/nominal rejections passed.
`make unit SUITE=accumulation_preimages` passes with its unchanged 1,164,480 occupied bytes before/
after 1,000 cycles, covering signed fixture defaults and actual guest provision capture. Python
passed 451 tests with seven skips; inventory passed 118 failure families, 1,722 probes and 183
native suites. Pinned formatting passed 1,601 Nim files and the Rust crate; diff checks pass.
`make unit SUITE=report_admission` also passes, retaining 294,032 occupied bytes before/after
1,000 cycles. No algorithm, codec, signature, PVM implementation or upstream pin changed.

Evidence is retained under ignored `build/accumulation-authorization/`. These are local macOS
checks, separate from exact-head Linux CI and complete block/STF parity. Next bounded work is to
combine retained consensus/report chapters with the private accumulation candidate. The supported
accumulation map starts from the admitted parent; its completed bookkeeping does not by itself
claim that consensus/report prefixes have been composed or a canonical block state published.
Remaining transfer/account/privilege merging and whole-block validation/publication remain open.
M1 framing remains complete; full state serialization and accumulation/block parity remain open.
