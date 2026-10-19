# Accumulation-bound validator activity

## Scope and authority

Bind the [validator activity projection](validator-projection.md) to one genuine
[last-accumulation timestamp candidate](accumulation-times.md). Authority remains GP 0.8.0,
revision `07f041dabd073f9018b418e9ee72e79dd2185401`, statistics.tex validator equations and the
reporting_assurance.tex Reporters set. statistics.tex SHA-256 is
`a8bee7c99853ed116fb7ed5e45e9977c7c323ad386e5a7e6c8cefba509f2d2a9`.
No pins, codec widths, signature validation or projection arithmetic change.

## Contract

Only PreparedAccumulationTimes may construct PreparedAccumulationValidators. Retain the exact
source, derive its finalized execution/report admission chain, and use that chain's immutable
BlockTransitionResult and decoding profile. Decode C(13) from the admitted parent complete map,
with current/previous populations obtained from exact whole parent C(8)/C(9) entries. Decode
posterior active C(8) from the authenticated post-assurance stage, never from a caller roster or a
later PVM map. Parent time is exact whole C(11); candidate time/author are the retained authenticated
header. Epoch length and cores come from the retained profile, without caller overrides.

Use the exact body ticket count, preimage count and sum of all submitted preimage blob lengths,
and the body's assured parent indices. Use distinct verified reporter identities from this same
AdmittedReports owner, including reporters selected from the previous roster. Never substitute
incoming report count, accumulated work-items, credentials per report, supplied reporter positions,
provision host effects or caller observations for these sources. This stage derives bookkeeping
from submitted preimages; their request eligibility and final integration remain separate gates.

Independent ceilings bound copied whole chapters, decoded roster populations, parent service
statistics, selected body components, preimage work/aggregate bytes and all pure projection work.
Preflight component counts/byte extents before materialization, and use checked aggregate byte
addition. Exact whole-entry decoding rejects valid prefixes with suffixes. Missing/malformed parent
C(13) is a refusal, never synthesized zeros. Preserve selected roster/activity/projection causes
through guarded alternatives; ordinary failures/defaults carry reasons alone.

The immutable acyclic owner retains the exact timestamp source, copied derived observations and
pure projection. Getters retain immutable handles or copy fixed records. The state getter returns
the exact unchanged timestamp snapshot: no writes, forks, root reconstruction, hashing or repeated
signature verification. This is a certified partial bookkeeping stage, not whole-block acceptance
or combined C(13) publication. Caller-supplied pure projections cannot construct this certificate.

## Completion tests

Require genuine signed accumulated and empty histories with parent C(13), distinct field seeds,
verified guarantees and authentic assurance votes. Verify exact header/time/epoch/body observations,
all six projected fields, preserved parent C(13) and timestamp full-map identity. Submitted preimages
must affect author counts/bytes even when accumulation is empty. Epoch-boundary and skipped-epoch
signed witnesses exercise assurance-before-rotation and fresh-current activity. Malformed/missing/
suffixed C(13), short policies, default source, invalid extraction and projection overflow refuse
without changing the source; retry succeeds with a sufficient policy. Verify copied observations,
scoped-source lifetime, zero backend calls after certificates exist, strict runtime/private/nominal
probes and 1,000 scoped ARC cycles. Run selected native suite and affected fixture consumers,
source-owned inventory/Python discovery, pinned formatting and diff checks.

## Remaining work

Per-block core/service activity and combined C(13) publication, transfer/account/privilege
coordination and whole-block publication remain open. M1 framing is complete; full state
serialization and accumulation/block parity remain open.

## Local verification

`make unit SUITE=accumulation_validators` passes. Genuine signed empty and missing-code accumulated
histories derive literal validator fields from source C(11), header/profile, submitted preimages,
authenticated assurances and verified guarantees. Three submitted preimages, including an empty
blob, contribute count three and four payload bytes even with empty S. A genuine RingVRF ticket
contributes one ticket. Authentic assurance votes update parent-current positions before rotation
at slots 12 and 48. A separate slot-12 candidate admits slot-11 guarantees from the previous roster
while cyclically shifting posterior active identities; expected credit positions demonstrably differ
from credential positions. All six projected fields match independent seeded tuples and original
credential positions mapped through that explicit test permutation.

Parent and timestamp-candidate C(13) bytes remain unchanged. State getters retain the identical
complete timestamp snapshot, including the actual surviving service's accumulation timestamp.
Copied observations and projected/state owners survive source scope. Exact/short/full-width chapter,
roster, service-dictionary, component, preimage, assurance, reporter, comparison and retained-row
policies refuse or retry at the intended boundary; empty selected components require one framing
byte with zero observation budgets. Missing, truncated, wrong-count and suffixed authenticated
parent statistics refuse without fabricated rows. Author overflow and pre-rotation assurance overflow
retain the selected projection cause. Hash-disabled success/refusal paths make zero Blake2b calls.
Over 1,000 scoped success/refusal cycles occupied allocation remains 946,832 bytes before and after.

All nine runtime extraction guards and five compiler privacy/source-substitution rejections pass
through existing source-discovered runners. Python discovery passes 445 tests with seven skips;
inventory discovers 114 failure families, 1,688 probes and 179 native suites. Shared signed fixtures
now optionally construct genuine tickets, submitted blobs, epoch markers and shifted next-epoch
rosters/previous-slot guarantees before signing; defaults preserve their prior behavior. The affected
report-admission suite passes, including 1,000 ARC cycles at 294,032 bytes unchanged. The pure
validator projection, codecs, cryptographic primitives and PVM implementation are unchanged;
their prior algorithm evidence is reused. Logs remain under ignored `build/accumulation-validators/`
and native selected/evidence directories. These are local macOS checks; exact-head Linux CI is
separate. M1 framing is complete; full state serialization and accumulation/block parity remain open.

The final affected timestamp suite also passes, retaining its 1,000-cycle allocation at 1,493,760
bytes unchanged. Final pinned format/check passes for 1,567 Nim source files and the Rust crate;
`git diff --check` passes. No other production modules or upstream sources changed.
