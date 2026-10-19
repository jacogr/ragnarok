# Execution-dependent ready queue C(14)

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
accumulation.tex History and Queuing (D/E/newly deferred reports) and the final
ready/accumulated equations, with vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
Set m = target mod epoch length. Replace slot m with E(newly deferred reports,
actually processed package identities), clear cyclic ages 1 <= i < elapsed
slots, and apply E to surviving parent rows at cyclic ages i >= elapsed.
A full-epoch gap expires every parent row. The replacement uses newly deferred
reports, not the planner's larger q or the unprocessed priority suffix. Immediate
reports are not inserted into the ready ring. Preserve row order and canonical
remaining dependency sets; processed membership removes all matching reports
and dependencies. Parent accumulated history applies to D for new deferred
reports before processed membership, not wholesale to existing parent rows.

Pure projection accepts immutable original rings, stable available/processed
inputs and explicit times. It certifies no admission. Bound inspected report,
dependency and hash work, native extents, child profiles and output framing
before copies. Use sorted fixed hashes and binary membership, never recursive
Q evaluation. Return independent entry bytes and a retained immutable ready ring.

Opaque preparation accepts PublishedAccumulation and derives the original
admission, parent C(14)/C(15)/time, source profile, actual newly available reports
and exact processed original queue prefix internally. Its publication base is
the already coordinated account/C(13)/C(15)/C(16) successor; caller contexts or
foreign candidates cannot be substituted. Preparation is hash-free. Atomic
private/mutable publication changes only C(14), inherits store limits, skips an
unchanged entry, and requires exact prior identity before mutable publication.
No partial light mapping is accepted and no whole-block validity is claimed.

Completion witnesses cover expiry/wrap/full gaps, new deferred versus q,
processed reports/dependencies, immediate/unaffordable reports, duplicate hashes,
canonical order, profile/owner/slot failures, exact/short/full-width policies,
full-map preservation/root, rollback/retry, copied/detached lifetime and 1,000
ARC cycles. Next: recent-history binding/remaining block coordination. M1
framing remains complete; full state serialization/block parity remain open.

## Local verification (2026-10-19)

The selected accumulation_statistics native suite passed under pinned Nimony,
checked ARC/Clang LTO and prepared native libraries. Literal four-slot output
bytes cover the new deferred prerequisite/lookup union, cross-source duplicate
keys, overlapping historical hashes, processed-set duplicates, dropping matching
reports and removing only satisfied dependencies. New reports whose dependencies
become empty remain deferred records; an immediate unprocessed report is not
queued and its identity does not prematurely satisfy another report's dependency.
A parent dependency present in old accumulated history remains unchanged unless
newly processed, following the separate E applications in the pinned equations.

Literal surviving-slot masks cover one/two/three-slot advances, wraparound,
exact/full-epoch gaps, gaps longer than an epoch and maximal uint32 target time.
A singleton epoch replaces its one row correctly. Exact/short/full-width input
work policies and exact/one-byte-short output framing passed, including child
report budgets and valid nine-shard owners captured under a broader three-core
profile being rejected under two cores. Default owners, out-of-profile reports,
zero epoch length and non-increasing time are refused.

Three genuine coordinated sources cover inactive, fully processed and
unaffordable-suffix accumulation. Full processing removes all four original
ready reports; the unaffordable case processes only package 64 and leaves
packages 65/66/67 at original slot zero. Current slot two stays empty, proving
that planner q and an unprocessed priority suffix do not replace newly deferred
reports. Preparation derives original rings/time/availability and processed
prefix from its retained history; incoming guarantees are not mistaken for
newly available reports. No-op queue publication retains exact map identity
without hashing. Detached queue owners retain the complete coordinated source.

Each source completed 1,000 hash-free preparations and 1,000 private publication
cycles without retained ARC growth. Changed queue publication matches a
separately reconstructed complete-map root and preserves every coordinated
account/C(13)/C(15)/C(16) and unrelated value. Equal-root foreign maps and stale
changed priors are rejected before hashing; early/late mutable hash failures
leave the caller unchanged and retry succeeds. The enclosing suite retained
fresh 1,000-cycle evidence: 1,704,016 occupied bytes before and after.

Eleven strict runtime extraction/reason guards, four privacy rejections, two
nominal rejections and semantic compilation passed. Source-owned inventory,
nine inventory tooling tests, pinned changed-source formatter idempotency,
local feature links and whitespace checks passed. Witness development corrected
the lookup field spelling and used codec-valid nine shards for the broader-profile
boundary; seven shards are already refused by the underlying report codec.
Formatter-sensitive expressions were split without changing toolchain sources.
Logs/results remain under ignored build/pvm-ready-reconciliation*. These are
local macOS checks, separate from exact-head Linux CI. No existing planner,
producer, codec, runtime, vendor tree or dependency pin changed.

Next bounded work: bind recent history to the completed accumulation output and
original block context. Remaining block-stage coordination stays open. M1 framing
remains complete; full state serialization and block parity remain open.
