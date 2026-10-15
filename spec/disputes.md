# Disputes extrinsic codec

Normative source: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix C.2
`encodedisputes`, Judgments `disputesextrinsics` and its ordering equations, and constants
`Cmaxextrinsicverdicts`/`Cmaxextrinsicoffenses` (both 16). Exact chapter and published fixture
hashes
are recorded in [pins.json](pins.json).

The extrinsic concatenates three canonical natural-count sequences: verdicts, culprits and faults.
A verdict is a 32-byte report hash, E4 epoch index, canonical variable judgment count and judgments.
Each judgment is a Boolean octet (0/1), E2 judge index and 64-byte Ed25519 signature (67 bytes).
A culprit is a report hash, 32-byte Ed25519 offender key and signature (128 bytes). A fault inserts
a Boolean octet between the report hash and key (129 bytes). Signatures remain opaque here.
Each outer section has at most 16 records. An empty extrinsic is exactly `00 00 00`.

Verdict report hashes are strictly ascending and unique. Within each verdict, judge indices are
strictly ascending and unique. Culprits and faults are independently strictly ascending and unique
by offender key, comparing identity bytes lexicographically. Ordering is checked, never repaired
inside production APIs. A key can occur once in each evidence section; cross-section eligibility
requires state context. Epoch, judge, report hash, offender key and signature have nominal types.

`DisputeConfig.validators` is an explicit structural ceiling covering **both** eligible current and
previous validator populations: 6..1023 in multiples of three. A judgment count cannot exceed that
ceiling, and each E2 index must be below it. A caller must not use a smaller current population as
the ceiling when a previous-epoch verdict can reference a larger population. `maxBytes` bounds the
consumed extrinsic prefix, not unrelated trailing input. It is caller resource policy, not another
wire constant. The fixed section/count ceilings prove every extent fits even a 32-bit host `int`.

This codec does not choose a validator set from the epoch, check current/previous epoch eligibility,
require exactly `floor(2*len(selected_set)/3)+1` votes, establish good/bad/wonky vote thresholds,
verify signatures/domains, check prior report histories or punish sets, or require supporting
fault evidence. Those are contextual judgment/state validation. In particular, an accepted
zero-judgment verdict demonstrates variable framing, not a chain-valid quorum.

## Ownership, failure and atomicity

`Disputes`/`Verdict` are encoder sources whose sequences must remain stable during a synchronous
call. The encoder validates configuration, section counts, every verdict/judgment identity and
evidence ordering, then the complete byte budget. Capacity and alias checks follow full source
validation. It checks the whole written destination against the outer descriptor, all source record
sequences and every nested judgment sequence before committing any bytes. Unused output suffix
bytes remain unchanged. Nim Boolean source fields cannot represent illegal wire tag values.

`decodeDisputes` first scans without allocation, using fixed private metadata for at most 16
verdicts.
For counts, canonical framing precedes prefix-budget and count-ceiling checks. Fixed extents check
remaining input before byte budget; complete judgment/evidence section extents precede their record
checks. Verdict order precedes judgment-count parsing. Judgment validation checks Boolean, index
ceiling, then order; fault validation checks Boolean before key order. Every failure discards all
private progress. Only a complete successful scan authorizes input-derived allocation and capture
of the validated prefix in private acyclic ARC storage. Input remains stable during the call.
Allocation exhaustion retains Nim's existing fail-stop policy.

`OwnedDisputes` retains bytes and matching private metadata together. `disputesInfo`, `verdictAt`,
`judgmentAt`, `culpritAt` and `faultAt` return copied fixed metadata/records, never mutable
sequences,
backing pointers or detached spans. Caller input mutation, destruction and copied-getter mutation
cannot affect the owner. `encodeOwnedDisputes` copies its original validated prefix atomically.
Default owners and signed invalid indices return failure; failed/default tagged results carry no
value, owner or consumed progress. Optimized builds preserve variant-field guards.

## Published fixtures and verification

Both pinned tiny and full published JSON samples reconstruct their binary fixtures byte-for-byte,
but put verdict hashes in descending order (`dd1b…` before `2bdb…`). They therefore intentionally
return `NonCanonical` under this project's GP ordering policy. Test-only sorted copies exercise
all original fields with canonical verdict order. No upstream fixture is edited, and a derived copy
is never described as an unmodified published acceptance vector. Tiny has five votes per verdict;
full has 683, with a variable natural prefix in the 0.8.0 wire format.

Run `python3 tests/test_disputes_harness.py` and `python3 tests/test_disputes.py`. Tests
independently
construct typed sources and observe every decoded field. They cover the full 16-verdict/1023-vote
ceiling plus 16 culprits/faults; natural-count width transitions; representative exhaustive
truncation and byte-budget boundaries; sampled full-vector vote boundaries; excessive/overlong
counts; all 254 illegal Boolean values in judgments and faults; late duplicate/descending hashes,
indices and keys; E2/E4 boundaries; deterministic structured/arbitrary malformed bytes; unchanged
destinations on failure; immutable-owner/source lifetimes and getter copies; outer/nested aliases;
four nominal-domain compiler rejections and one private-owner rejection. Linux CI runs the same
checked ARC/Clang LTO builds with assertions, bounds, range, field and overflow checks enabled.
