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
