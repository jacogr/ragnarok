# Tickets extrinsic codec

Normative source: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix C.1
natural/fixed integer definitions and C.2 `encodetickets`. Published tiny/full JSON and binaries
come from the recorded `davxy/jam-test-vectors` v0.8.0 pin in [pins.json](pins.json).

The wire is a canonical general-natural count followed by fixed 785-byte records: one **E1**
attempt octet and 784 opaque RingVRF proof bytes. The attempt is never compact encoded; values
128..255 still occupy exactly one byte. Every octet/proof pattern has a structural representation.
Checking the attempt against the epoch's submission allowance, verifying proof validity and
ordering tickets by their VRF outputs belong to Safrole and crypto, not this codec.

`TicketAttempt`, `TicketProof` and `TicketLimit` are nominal domains. Records own every byte.
`encodeTickets` borrows stable typed source records and writes a caller byte buffer;
`decodeTickets` borrows wire bytes and writes caller-supplied owned typed records. Successful
records outlive input mutation without a backing-buffer owner. A default/failed result exposes
only its reason; counts and consumed/written prefixes exist only on success.

Count policy is explicit: conventional tiny/full extrinsic ceilings are 3/16. This framing API
accepts a caller ceiling, including zero, rather than inferring chain configuration from bytes.
The test-only 128-record case exercises a multi-octet outer count; it does not claim chain eligibility.

Encoder preflight: count ceiling, checked host extents, full output capacity, then disjointness
of all source records and the written prefix. Decoder preflight: canonical count, count ceiling,
full wire stride proof, typed capacity, checked typed extent and overlap. The complete borrowed
input, including trailing bytes, is protected from typed-output overlap. No destination changes
on failure. Unused destination elements/bytes stay unchanged on success. Decoders consume one
prefix; standalone consumers must enforce full consumption themselves.

Tests cover both hash-pinned published profiles, every E1 attempt, count boundaries, representative
complete truncations, overlong/huge counts, exact/short capacities, alias rejection, owned lifetime,
unused-output sentinels and deterministic structured/random inputs. Two nominal compiler probes
reject raw attempts and proof/attempt swaps. Run `python3 tests/test_tickets.py` and
`python3 tests/test_tickets_harness.py`. Optimized native tests keep ARC/Clang LTO and all guards.

## Nimony port verification

The pinned nightly port keeps result status/payload private, exposes read-only `error` and guards
`written`/`count`/`consumed` with success preconditions. Default results remain Uninitialized.
Local proof arrays are explicitly initialized; every attempt remains exactly E1 and every proof
remains 784 opaque bytes. The production paths retain their allocation-free, atomic behavior.

`tools/test_nimony.py` checks all 22,939 original independent requests, six additional unsigned
limit boundary cases and 22,654 direct inspections: **45,599 comparisons**. Inspection expectations
use the independent decoder with capacity above the maximum count representable by the actual
input length; inspection itself allocates no records. Every original/new decode input is included.
Published tiny/full pairs retain their pinned hashes, and every possible attempt byte is observed.

The adapter mutates successful caller inputs before printing decoded fields and checks nonzero
sentinels throughout failed/unused typed output. Native tests preserve short-output atomicity,
source independence and encoder/decoder overlap rejection, adding a typed destination entirely
inside trailing input. Trusted alias fixtures use writable fixed array views within real storage.
Ten runtime misuse checks reject default/failed progress access across all three APIs; twelve
compilation checks reject private-state access, retagging, raw success construction and property
assignment. Two existing nominal checks reject raw attempts and proof/attempt swaps.

Commands, toolchain metadata, source/corpus hashes and exact diagnostics are recorded in ignored
`build/nimony-trial/verification/results.json` and adjacent logs. Local macOS ARM64 checked ARC/
Clang LTO conformance does not establish Linux, RingVRF verification or Safrole eligibility parity;
see [the trial](../docs/nimony-trial.md).
