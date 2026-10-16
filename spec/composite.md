# Optional blobs, work outputs and preimage extrinsics

Normative basis: Gray Paper **v0.8.0**, commit
`07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix **C.1.3**
(discriminators) and **C.2** (block serialization), specifically `maybe`,
`encodepreimages` and the work-output operator `O` in
[text/serialization.tex](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/serialization.tex).
Official fixtures retain vector commit
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`; hashes are in `pins.json`.

## Wire formats

Here `E` is canonical general-natural encoding, `E4` is four-byte unsigned
little-endian encoding, and `blob` bytes have identity encoding.

| Schema | Encoded form |
| --- | --- |
| Absent optional blob | `E(0)` |
| Present optional variable blob | `E(1) + E(blob.length) + blob` |
| Successful work output | `E(0) + E(blob.length) + blob` |
| Work error | `E(tag)` only |
| Preimage extrinsic | `E(recordCount) + (E4(service) + E(blob.length) + blob)*` |

Work-error tags are 1 out-of-gas, 2 panic, 3 bad exports, 4 oversize, 5 BAD,
and 6 BIG, exactly as C.2 specifies. Unknown discriminators are rejected before
constructing enum/union values. Overlong natural discriminators are rejected,
including optional absence encoded as `80 00`.

The optional API explicitly chooses a **variable blob** as its payload schema;
other optional types require their own payload codecs. Preimages preserve wire
order. These functions implement serialization, without imposing state-transition
rules such as preimage ordering/uniqueness or protocol resource constants.

## API and validation

See [the Nim codec guide](../docs/codec.md) and source modules under `src/codec/`.
Independent references, official vectors, boundary/fuzz and failure-atomicity checks live under `tests/`.

### Nimony result and variant safety

On `nimony`, `CompositeWrite`, `OptionalResult`, `WorkResult` and `PreimageResult` hide their
status and payload fields. Read-only `error` exposes the outcome; successful data and progress
properties have Nimony success preconditions. Default results remain `Uninitialized`, distinct
from validated empty values. Private storage prevents direct retagging, payload reads and raw
success construction through safe code.

Optional/work-output values use `absentBlob`, `presentBlob`, `successfulWork` and `failedWork`
source constructors. Their tags are read-only and span access requires presence/Success. Spans
are returned by value, retain no buffer, and still require the documented caller-owned stable pool.
Source construction does not validate span bounds; encoders retain their typed span/policy errors.
`failedWork` rejects Success because it requires a span. Default optional/work values keep their
existing absent/empty-Success semantics and bytes.

Sibling encoders may explicitly report completed extents using `compositeWritten` (nonnegative)
or failures using `compositeFailure` (reason other than None). These constructors do not validate
or write a caller buffer; each encoder remains responsible for preflight and atomic commit.
The Nimony-only runner checks both result alternatives, all six work-error tags, absent payload
access, constructor preconditions and raw-state bypass attempts. Wire encodings are unchanged.
