# Validator epoch activity

Use pinned GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
statistics.tex Validator Activity, and vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
Increment old-current assurances once per assuring validator before comparing
epoch quotients. With any epoch crossing, move that updated accumulator to
previous and initialize a fresh posterior-active-sized current array. Otherwise
retain previous unchanged. Credit the block author with one block, original
ticket/preimage counts and original preimage payload bytes. Credit each posterior
active key once when present in the reporter set, irrespective of repeated
credentials or reports. Preserve fixed E4 validator encoding; sums beyond uint32
are typed local representation refusals, never wrapping or protocol invalidity.

The pure projection accepts immutable activity/roster owners plus explicit raw
block context, preimages, assurance records and reporter keys. It certifies no
signatures or block provenance. Preparation accepts only AdmittedReports and
reads exact parent C(13)/C(8)/C(9)/C(11), posterior C(8), original header/extrinsics
and verified reporter identities from its retained source. Reject missing or
inexact chapters and inconsistent populations. Bound both epoch arrays and prior service rows,
encoded chapters/components, ticket/preimage/vote/reporter populations, payload
bytes and reporter comparison work before allocation/materialization. Retain an
opaque immutable source owner, return copied epoch rows and guarded failures,
and make no state writes or C(13) publication.

Completion witnesses cover same epoch, boundary, skipped epochs, resized
posterior populations, old-epoch assurances, reporter identity deduplication,
all six E4 overflows, exact/short/full-width limits, missing/malformed source,
default/private results, source lifetime and 1,000 hash-free ARC cycles.
Next: complete C(13) assembly/publication. M1 framing remains complete; full
state serialization and block parity remain open. Pins unchanged.

## Local verification (2026-10-19)

The selected report_admission native suite passed with the pinned compiler,
checked ARC/Clang LTO and prepared native dependencies. Pure independent arrays
covered same epoch, exact boundary, skipped epochs and a six-to-nine posterior
population change while retaining the updated six-row old accumulator. A
nine-row prior previous population remains unchanged within its epoch. Duplicate
raw assurances count once per old index, and duplicate reporter keys credit
once per matching posterior key. All six fixed E4 counter overflow cases passed,
including assurance overflow before rollover. All six fields are compared in
every expected row.

Genuinely signed incoming-only and incoming-plus-available blocks retain an
explicit parent C(13), three original preimages (one empty), posterior active
keys and the exact verified reporter set. Preparation derives the author, zero
original ticket count, all preimage metrics and old-index assurance increments
from that source. Missing, malformed and suffixed C(13) are refused. Prior
service-row limits produce a typed local LimitExceeded; accepting one old
service row succeeds with its exact budget. Detached owners retain the original
source graph and copied rows cannot mutate retained counters.

Each signed case completed 1,000 hash-free preparation/release cycles without
retained memory growth. The enclosing suite retained fresh 1,000-cycle evidence:
293,232 occupied bytes before and after. Five extraction guards, three privacy
rejections, one nominal source rejection and semantic module compilation passed.
Exact/short/full-width raw limits, independent source byte/work limits, invalid
owners/slots/authors/assurers, forged epoch tags and full-width indices passed.
Source-owned inventory and its nine tooling tests passed. Changed Nim sources
passed pinned formatter idempotency, local feature links and whitespace checks.

Development initialized local owner/sequence arrays explicitly for the pinned
compiler and corrected service-count policy refusal classification before the
final successful run. Logs/results remain under ignored
build/pvm-validator-activity*. These are local macOS checks; exact-head Linux CI
is separate. No codec, PVM runtime, vendor tree or dependency pin changed.

Next bounded work: assemble and publish complete C(13) from source-matched
validator, core and service metrics. Independent account/history/statistics
candidates still require coordinated block publication. M1 framing remains
complete; full state serialization and block parity remain open.
