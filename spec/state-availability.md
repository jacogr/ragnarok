# Availability assignment state: chapter 10

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapter **10**, `text/reporting_assurance.tex` `eq:reportingstate` and
`eq:guarantee`, and C.2 guarantee/report serialization. Chapter hashes and exact published data
identities are recorded in [pins.json](pins.json). No dependency or toolchain revision changes.

## Exact value and standalone guarantees

`src/state_availability.nim` provides `availabilityStateEntry(values, config)` for C(10) and
`decodeAvailabilityState(input, config)` for one complete component prefix. There is exactly one
optional assignment for every configured core, in core-position order, **without an outer count**:

```text
for each configured core:
  0
  or 1 || full standalone guarantee || E4(registration timestamp)

standalone guarantee:
  work report || E4(guarantee evaluation slot)
  || E(credential count) || (E2(validator index) || signature[64]) credentials
```

A present assignment includes the **full guarantee**, not just its work report. The guarantee's
own evaluation slot and credential sequence precede the separate registration timestamp.
`AssignmentSlot` is nominally distinct from `GuaranteeSlot`. Both are exact little-endian E4,
including zero and values above the one-byte natural range. Absence contains neither a default
guarantee nor a registration time; it differs from presence with registration zero.

Existing report/credential checks are shared rather than copied into the state codec. New
`inspectGuarantee`, `decodeGuarantee`, `measureGuarantee` and `encodeGuaranteeValue` APIs in
`guarantees.nim` expose **one record without the extrinsic's outer count**. The private single-record
scan, source validation/measurement and commit phases also serve the existing extrinsic API.
Its inter-record ascending-core rule remains at the extrinsic layer, at the same validation point;
standalone state records do not impose an extrinsic sequence order. The existing 7,617-case
extrinsic regression suite protects its framing, error precedence, ownership, atomicity and aliases.

Child reports retain their current structural bounds/canonicality and immutable owners. Guarantees
require two or three ordered unique E2 credential indices within the supplied validator ceiling;
signatures remain opaque. Neither state composition nor a state fixture weakens those rules.

## Bounds, ownership and failures

`AvailabilityConfig` supplies the existing `GuaranteeConfig` (2..341 cores, valid validator profile,
per-guarantee byte ceiling), a caller present-item ceiling and a complete parent byte ceiling.
Every configured position needs at least one tag byte. Invalid profile/minimum byte policy is
rejected before input access. Encoder sources must contain exactly the configured slot count.
Present-item policy is checked before nested parsing/measurement. Tags, complete standalone
guarantees and registration timestamps all consume the parent budget, independently of child
byte ceilings. Checked arithmetic precedes parent additions; fixed profile bounds bound slot arrays.

The decoder scans **all** optional slots and nested guarantees before allocating **any** parent
or child report owners. Its bounded private stack layout retains only synchronous descriptors.
Complete prefix success returns its consumed extent; unrelated suffixes remain with the caller.
Malformed late tags, children or registration bytes publish no earlier owner/progress. The source
encoder preflights every child before allocating final output or child scratch; it then copies one
fresh standalone child buffer at a time. Peak extra scratch is bounded by the largest child, not
the number of present reports. Allocation exhaustion follows the existing Nim fail-stop policy.

`AvailabilityResult` defaults/failures carry only their reason. Nested report/credential/profile
errors retain their corresponding typed reason. `AvailabilitySnapshot` is a value handle to
private acyclic ARC storage. `availabilityInfo` returns copied cardinalities; `availabilityAt`
checks a nominal core position and returns a copied tagged assignment. Its fixed guarantee fields
are independent copies, while its `OwnedReport` handle safely retains immutable child bytes even
after the parent and every original input/source handle are gone. No mutable sequences, pointers
or detached report spans are exported. Absent alternatives retain runtime field guards.

Source arrays and decoder bytes remain stable during the synchronous call only. Later source,
input, extracted-credential or owner-handle mutation cannot alter retained data. Encoded payloads
belong to the caller and must stay stable during a later [trie call](state-trie.md).

The codec does not verify signatures, assurances, timeouts, active-set transitions, registration
chronology, occupancy eligibility or the contextual match between an embedded report's core and
its outer state position. Child core/profile bounds still apply. These are state-transition/import
checks, not properties inferred from T's ordered optional sequence. Passing framing checks does
not establish a valid availability state or cryptographic consensus eligibility.

## Evidence and reproduction

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_availability_harness.py
python3 tests/test_state_availability.py
python3 tests/test_guarantees.py
python3 tests/test_block.py
```

Six literal harness checks protect independent optional framing, full-guarantee composition,
separate E4 times, byte/item policy and inherited credentials. **2,949** native requests compare
complete entry keys/bytes, retained child report/slot/credential/registration observations,
consumed extents or failure-only reasons. Cases include all-absent and mixed/present patterns,
every proper truncation of representative parents, every reserved optional tag in early/late
positions, tiny/full all-absent shapes including 341 positions, incorrect source lengths, independent
E4 boundaries, exact/one-below child/parent byte limits, present-item ceilings, invalid profiles,
zero/one/four credentials, duplicate/descending/out-of-profile indices, malformed late children,
overlong/huge credential counts, late core positions through 340 and 127/128/255/256 report-core
framing, randomized assignments/mutations, suffixes and four partial C(10) trie integrations.

Expected child data uses the existing independent Python report/guarantee equations. The test-only
reference adapts its one-record extrinsic oracle by accounting for the known count prefix; the
production implementation uses shared record helpers and has no synthetic-prefix/copy workaround.
Authored current-valid tiny-profile reports explicitly use six erasure shards. This does not
modify the full-profile generator or published data. Native supplementary tests protect whole-parent
capture, child report lifetime after parent scope exits, fixed credential copies, optional absence,
default/index/field guards and independent timestamps. Two nominal compiler probes reject
GuarantorIndex-as-core and GuaranteeSlot-as-registration substitutions; one privacy probe rejects
access to retained storage.

Twelve published pre/post/profile observations come from six exact JSON paths at vector revision
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`: tiny/full assurances
`no_assurances-1.json`, `some_assurances-1.json`, and disputes
`progress_invalidates_avail_assignments-1.json`. All original named fields remain unchanged.
Their state bytes are explicitly derived from JSON, not standalone published T(state) binaries.
The frozen fixture reports have empty lookup dictionaries and successful work results; the fixture
converter asserts that supported schema rather than silently omitting unsupported fields.

The eight assurance-state observations pass decoding. The four zeroed dispute-state observations
retain **LimitExceeded** from the existing report erasure-shard policy; their report sources cannot
be captured for encoding and retain **InvalidReport**. They also contain empty credentials, but
that is not the first decoder failure. No zeros, credentials or signatures are invented to make
these raw fixtures pass. Successful authored cases separately exercise full guarantees. Recorded
published verdict counts distinguish these expected rejections from success evidence.

Every consumed Git blob is SHA-256 checked before parsing, without source/gitlink changes, sparse
checkout expansion or generator execution; partial clones may fetch promised pinned data. Tests do
not execute assurance/dispute STFs, verify supplied signatures or establish full-state roots.
Nim 2.2.12 ARC/Clang LTO builds retain assertions/bounds/range/field/overflow guards. Ignored
`build/state-availability/` records commands, request SHA-256, published verdict counts, logs and
results. Linux CI runs the suite and uploads diagnostics; local results are macOS arm64 and Linux
confirmation requires CI after push. Existing crypto parity gates remain unchanged.

M1's C.1/C.2 framing baseline remains covered; complete state serialization remains open. Next
planned bounded chunk: **service request history entries**. The
[M1 checklist](../docs/m1.md) tracks service entries and whole-state integration.
