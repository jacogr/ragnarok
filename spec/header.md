# Header and marker codecs

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`. Normative sources are
Appendix C.2 `encodeunsignedheader`, full header, epoch marker and Safrole ticket encodings;
`header.tex` header/markers; `safrole.tex` `valcount`, `epochmarker`, `winningticketsmarker` and
`ticket`; and `judgments.tex` `judgmentmarker`, with its maximum offense counts in
`definitions.tex`. Exact chapters and both tiny/full header JSON/binary fixtures are hashed in
[pins.json](pins.json). No upstream source or vector is changed.

## Wire and structural policy

Unsigned header order is parent hash32, prior state root32, extrinsic commitment32, E4 slot,
optional epoch marker, optional winner marker, E2 author index, entropy-yielding VRF encoding96,
canonical natural offender count and Ed25519 offender keys32. The full header appends the exact
96-byte seal **after all unsigned fields**, including offender keys. The signing payload omits
only that final seal; unsigned decoding consumes that prefix even when a seal follows in input.
The three commitments, slot, author, two entropy roles, key roles, ticket identifier, entropy
proof and seal have nominal types. Signatures/keys are opaque encodings at this layer.

`EpochMarker` is absent (`00`) or present (`01`, epoch entropy32, ticket entropy32, canonical
natural validator count, ordered Bandersnatch32/Ed25519-32 key pairs). GP 0.8.0 makes the validator
sequence variable: count is a multiple of three from six through three times configured cores.
It is **not** inferred from the current author population. Validator-index order is preserved;
there is no codec-level key sorting, deduplication or curve-point validation.

`WinnersMarker` is absent (`00`) or present (`01`, exactly `epochSlots` complete winning tickets).
There is **no count discriminator** on the present winner sequence. Each `WinningTicket` is an
opaque identifier32 followed by an E1 `TicketAttempt`, reusing the existing ticket entry-index
domain. The full 0..255 E1 range has a structural encoding; contest eligibility is external.
Sequence order/duplicates are preserved. The state-derived outside-in winning sequence is not a
sorted set and cannot be reconstructed or validated from framing alone.

The offender sequence preserves exact input order and duplicates. `judgmentmarker` defines it as
culprit keys followed by fault keys; each underlying evidence sequence is independently ordered.
The concatenation can descend at the boundary or repeat an identity across sections. Its
structural maximum is **32 entries**, derived from 16 culprits plus 16 faults. Equality with the
actual new offenders requires the block's disputes and state and is not claimed here.

`HeaderConfig` supplies configured cores, the posterior author-validator ceiling, positive epoch
length and a serialized-prefix byte budget. Core/author domains follow the existing assurance
configuration: cores 2..341, author population 6..3*cores in multiples of three. An E2 author index
must be below the supplied author ceiling. Pending epoch cardinality uses the core ceiling
independently, permitting validator population changes between epochs. Callers select the actual
posterior population and chain parameters; the codec does not derive them from a marker.

`fullHeaderConfig(maxBytes)` selects 341 cores, 1023 authors and 600 epoch slots. Tiny fixtures use
2 cores, 6 authors and 12 slots. Custom positive epoch lengths remain explicit parameters rather
than an inferred wire count. Even a maximal uint64 configured length is compared against available
input by division before any conversion, multiplication, iteration or allocation. Insufficient
present-winner input returns `Truncated`; an absent winner marker needs only its discriminator.
Encoder length growth and typed alias strides are checked before host arithmetic can overflow.
`maxBytes` bounds only the consumed/written prefix; unrelated trailing data does not consume it.
Standalone fixed-ticket APIs have no configuration or byte-budget parameter.

This increment does not verify entropy/seal signatures or points, calculate header/extrinsic
hashes, check parent/state/time eligibility, require or prohibit markers at epoch boundaries,
derive winner selection, or compare offenders with disputes. Those remain cryptographic/state
and block-composition work. Standalone consumers must separately require complete input
consumption when trailing bytes are forbidden.

## Ownership, atomicity and errors

Encoder source records own fixed fields and borrow their public sequences for one stable
synchronous call. Source types use Nim's public `byref` annotation so alias checks observe the
caller's source storage consistently, including small marker descriptors. This controls parameter
passing; it exports no pointer and introduces no borrowed decoder results.

Encoding preflight checks every nested source marker, validator/ticket cardinality, author,
offender count and host byte extent before serialized budget, complete output capacity and alias
checks. The whole written destination must be disjoint from fixed source records/descriptors,
all validator keys, winners and offenders. Standalone marker/fixed-ticket encoders use the same
atomicity policy. A late source failure cannot write an earlier parent hash, marker or proof.
Unused destination suffix bytes remain unchanged.

Decoding scans into bounded private metadata without input-derived allocation. Fixed extents
check available input before budget; optional tags then require 0/1; canonical count framing
precedes prefix-budget/count bounds and fixed sequence extents. Author policy follows complete
E2/proof availability, then offender framing, then the final seal for a full header. Failed scans
discard every partial field and cursor. Only complete validation authorizes an immutable private
ARC copy of the exact consumed prefix. Source input stays stable during the synchronous call;
allocation exhaustion retains Nim's existing fail-stop policy.

`OwnedHeader` and `OwnedUnsignedHeader` are distinct handles: an unsigned capture cannot be used
as a sealed header. `unsignedPart` retains the full parent's snapshot and selects its exact
signing prefix. `headerEpoch` and `headerWinners` retain that same original snapshot, with private
matching marker coordinates. Marker views survive release of every header/unsigned handle and
all caller source storage. Standalone marker decoding uses the same immutable representation.

`headerInfo`, `unsignedHeaderInfo`, `epochMarkerInfo` and `winnersMarkerInfo` copy fixed metadata.
Optional metadata is tagged, so absence exposes no default entropy or present sequence count.
`epochValidatorAt`, `winningTicketAt` and `headerOffenderAt` copy complete fixed records through
their matching retained owner. No mutable backing sequence, pointer or detached span is exported.
Owner re-emission copies only the selected validated interval and rejects destinations overlapping
any part of the retained wire. Default owners and signed invalid/absent-marker indices return
failure. Failed/default results carry only their reason, never a value, owner or progress.
Optimized builds keep both result and optional-alternative field guards.

## Verification

Run `python3 tests/test_header_harness.py` and `python3 tests/test_header.py`. Independent Python
construction exactly reconstructs all four pinned published headers and their seal-free signing
prefixes. The native encoder receives independently constructed named typed fields; decoder
observations compare every fixed field, indexed validator, ticket and offender identity rather
than relying on same-codec round trips. Input is overwritten after capture; getter copies are
mutated; signing/marker child views outlive their parents; owner re-emission checks exact bytes
and untouched suffix capacity.

Coverage includes every small representative truncation and sampled full-profile key/ticket
boundaries; all optional combinations; every illegal optional tag octet; E1/E2/E4 and natural
count-width boundaries; every E1 attempt value; GP validator cardinalities and independent pending/
author populations; configured winner count mismatches and maximal uint64 epoch length; offender
count maxima with duplicate/descending identities; overlong/huge counts; exact/short/spare outputs;
consumed-byte budget boundaries; deterministic structured/arbitrary malformed input; late-source
atomicity; fixed/descriptor/key/ticket/offender aliases; guarded failed/absent access; five nominal
compiler rejection probes and four private-owner probes. Eight harness known-answer tests protect
the independent oracle. Linux CI builds with ARC/Clang LTO and all existing assertion, bounds,
range, field and overflow checks enabled. Passing framing tests is not state/signature validation.
