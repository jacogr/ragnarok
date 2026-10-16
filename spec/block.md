# Complete extrinsic and block codecs

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix C.2
complete extrinsic/block equations. Child policies come from the pinned serialization, header,
Safrole, reporting, availability and judgments chapters and their existing contracts in `spec/`.
Exact sources and tiny/full `extrinsic`/`block` JSON/binary hashes are in [pins.json](pins.json).
The vector source is `davxy/jam-test-vectors` v0.8.0
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. No vendor bytes or gitlinks are changed.

## Composition and configuration

A complete extrinsic concatenates **tickets, preimages, guarantees, assurances, disputes**, in that
order. Each child retains its existing sequence framing; disputes has three sequences. There is
no additional outer count or discriminator. The empty complete extrinsic is seven zero octets.
A block is a complete sealed header followed immediately by that complete extrinsic.
Decoders consume one prefix; a standalone consumer must separately reject trailing bytes.

`FrameConfig` explicitly supplies cores, structural validator ceiling, positive epoch length,
ticket count limit, preimage item/per-blob/aggregate payload limits and total serialized byte
budget. Core/validator domains match the existing assurance configuration (2..341 cores,
6..3*cores validators, multiple of three). Ticket limit is at most 16; zero is a useful restrictive
caller policy. Full configuration selects 341/1023/600/16. Tiny fixture configuration uses
2/6/12/3. Preimage policies remain explicit resource limits, not newly invented protocol constants.
The byte budget includes every count and framing octet in the consumed parent prefix; unrelated
input/output suffixes do not consume it. Each child receives the remaining whole-parent budget.

The validator ceiling is a structural bound. Actual active/pending populations, eligibility,
commitments, header extrinsic-root hashing, parent/state/time relationships, offender equality,
credentials and seal/VRF verification belong to state/crypto validation. A composed codec value
does not claim those properties.

## Ownership and API

`Component[kind: static[ComponentKind]]` privately captures exact validated child bytes and configuration.
Header, ticket, preimage, guarantee, assurance and dispute components are nominally distinct:
a wire-compatible component of another schema cannot be substituted. Header components always
contain a seal. `decodeComponent` scans before copying; it does not export mutable storage or
source coordinates. Input must remain stable during the synchronous call and may then be mutated
or released. Default handles are invalid, including for empty child sequences.

`Extrinsic` is a typed source of five immutable component handles. `ownExtrinsic` validates and
retains those children without a whole-frame encode/decode round trip or duplicate frame buffer.
`decodeExtrinsic` validates all five children before any input-derived snapshot allocation.
`Block` combines a header component and `OwnedExtrinsic`; `decodeBlock` likewise validates the
complete sealed header and all extrinsics before capturing either. Private acyclic ARC references
release storage when the last retaining handle is destroyed. Allocation exhaustion follows Nim's
existing fail-stop policy; this API does not promise recoverable allocation failure.

Parent child getters retain their immutable components after parent/input release. Metadata
getters copy counts and consumed extents. Disputes cardinality is the sum of verdicts, culprits and
faults; use `readDisputes` for separate section counts. `readTickets`/`readAssurances` return fresh
independent record sequences. `readPreimages`, `readGuarantees`, `readDisputes` and `readHeader`
materialize the existing family owner APIs on demand and may allocate another snapshot. This is
an explicit access cost, not a zero-copy promise. Re-emission copies exact validated child bytes.

## Preflight and failures

`FrameResult` carries a value only on `None`. `InvalidComponent` carries only a selected, typed
child failure (kind plus the matching child error); all other failures/defaults carry only their
reason. No failed branch publishes an owner, partial value or consumed offset. On the Nimony port,
result tags/payloads and nested schema/reason fields are private. Read-only `value` requires success;
`cause` requires `InvalidComponent`; each selected child reason requires its matching read-only
`kind`. Supported contracts remain enabled in checked optimized builds.

Invalid shared configuration precedes source traversal/input framing. Children are inspected in
wire order with existing child error precedence. Preimages additionally checks serialized wire
budget during traversal, independently of payload budgets. Counts, available extents and host
conversions are proved before allocation. A late child failure discards every partial parent
field/cursor. Child failure attribution remains typed; a parent budget violation can be either
a nested child's budget error or the parent's final prefix-budget error, according to where it
is first detected.

Source encoding revalidates every child under the requested parent configuration, including when
it was captured under broader limits. Each child must consume its entire immutable snapshot:
a different profile may not reinterpret it as a shorter valid prefix. Extent mismatch returns
`InvalidConfig`; otherwise the existing child's failure is preserved. Complete source validity,
checked aggregate arithmetic and byte budget precede output capacity, then alias checks.

Before writing the first byte, the whole written destination is checked against borrowed parent
source descriptors and every immutable child wire, including children written later. Capacity
or late policy/alias failures leave the entire output unchanged; successful writes preserve spare
suffix bytes. Encoders copy directly after preflight, with no whole-frame staging allocation.
Public source records use Nim's supported `byref` parameter annotation to preserve source-storage
identity for descriptor alias checks.

## Published fixtures and verification

Independent JSON construction reproduces all four original composite binaries exactly. Their
existing structural-policy issues remain visible: tiny samples contain a guarantee with core 3
under a two-core profile and fail `Guarantees/LimitExceeded`; both profiles have descending dispute
verdict hashes, so full samples fail `Disputes/NonCanonical`. The first failure in wire order wins.
Tests author counterparts by choosing tiny core 0 and sorting verdicts; originals remain untouched.
Header hashes/signatures are opaque and are not recomputed in these counterparts. They establish
codec structure, **not chain-valid blocks**.

Run `python3 tests/test_block_harness.py` and `python3 tests/test_block.py`. Seven harness known
answers protect the independent Python references. The native checked ARC/Clang LTO run compares
17,194 deterministic requests: independent encoder sources/decoder observations, child wire and
counts, truncation/malformed mutations, exact/short/spare capacity, whole/payload budgets and
stricter recapture policies. Native regressions cover child lifetime, returned-copy independence,
profile reinterpretation, unchanged output on late failure, descriptor/private-wire cross-child
aliases, and selected result/cause field guards. Three nominal and three private-owner compiler
rejections protect the API. A white-box test includes only this project's own module to exercise
otherwise inaccessible private-wire alias paths; production exports no backing pointer.
Linux CI runs the same runner and retains its build, type-check and result diagnostics.

## Nimony branch verification

On this experimental branch, reproduce the checked ARC/Clang LTO port with
`python3 tools/test_nimony.py --compiler build/nimony-trial/nimony/bin/nimony`; the historical
Nim 2 runner above is not a second supported source target. The cumulative runner includes all
17,194 unchanged independent requests, the seven oracle known answers, both native composition
suites, 85 isolated result/cause misuse rejections and 28 private/nominal compilation rejections.
The release workload retains every original child across parent replacement and source erasure,
then materializes all six family APIs. After 100 warmups, 1,000 isolated scopes return live allocator
occupancy to baseline. Commands, source/request/output hashes and individual verdicts are retained
in `build/nimony-trial/verification/results.json`. See [the trial](../docs/nimony-trial.md) for exact
compiler/environment and cumulative totals. Verification is local macOS ARM64; this increment does
not establish Nimony Linux, complete M1, M2/M3 or cryptographic/state parity.
