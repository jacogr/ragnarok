# Guarantees extrinsic codec

Normative source: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix C.2
`encodeguarantees`/`guarantee` and reporting/assurance equations `guarantee`, `guaranteesextrinsic`
and `guarantorsig`. Published tiny/full wrapper JSON/binary hashes are in [pins.json](pins.json).

The wire is E(count), followed by complete canonical report bytes, an E4 evaluation slot, a
canonical credential count and its E2-index/64-byte-signature pairs. Credential count is exactly
two or three. Report cores are strictly increasing and unique; credential indices are strictly
increasing and within the caller's validator ceiling. Slot, guarantor index and signature are
separate nominal domains. Signatures are opaque encodings at this layer.

`GuaranteeConfig` supplies configured cores, the credential-validator ceiling and a retained frame
byte budget. Core/validator domains follow 0.8.0 `valcount`: 2..341 configured cores and 6..3*cores
validators in multiples of three. The outer count is at most the configured core ceiling.
The byte budget covers only the consumed extrinsic prefix, not unrelated trailing input. It is an
explicit resource policy, not an additional Gray Paper wire constant. An empty frame needs one byte.

This stateless codec does not select current/previous rotation key sets, establish validator
assignments, check timeslot eligibility or report anchors, enforce pending-core availability,
compare shard count with the actual active population, or verify credentials. Callers must supply
the appropriate structural ceiling and perform state/crypto checks separately. In particular,
`GuaranteeSlot` is serialized in the wrapper but remains outside `jam_guarantee || BLAKE2b(report)`.
The published tiny sample retains core 3 and is structurally checked under a permissive full
ceiling, with a separate rejection under actual tiny parameters; it is not a chain-eligible report.

## Ownership and atomicity

Encoding accepts stable borrowed `Guarantee` values. Each value retains an existing immutable
`OwnedReport`, an owned E4 slot and a fixed owned three-slot credential array with an explicit
active count. The encoder validates every source report, canonical order, credential and extent
before output capacity and alias checks, then commits. Source records and **all** nested private
report storage must be disjoint from the **whole** written destination, not only the individual
report's destination. `ownedReportOverlapsOutput` supports this composition using a Boolean;
it exposes no address or detached span.

Decoding first scans the whole extrinsic into bounded private metadata (at most 341 records)
without input-derived allocation. Only after all framing, child reports, ordering and resource
checks succeed does it allocate private ARC records and capture child reports into existing
immutable owners. Input must stay stable during the call. No input pointer or detached span
escapes. Nim allocation exhaustion retains the existing fail-stop policy; it is not presented as
recoverable allocation-failure handling.

`decodeGuarantees` returns a success-only `GuaranteesRead` containing the owner and exact
count/consumption. `guaranteeAt` returns a copied fixed record plus an immutable report handle;
mutating that copy cannot change the snapshot. `encodeOwnedGuarantees` re-emits canonical owned
records atomically. Default owners and signed invalid indices return typed failure. Failed/default
results contain no partial owner, value or progress.

Tests independently construct published wrapper bytes and observe every wrapper field, not merely
round-trip through one codec. Coverage includes full 341-core count, two/three credentials, E4/E2
boundaries, source/output budgets, every truncation of representative frames, late report/order/
credential failures, nested malformed framing, source mutation and copied-getter mutation,
whole-destination encoder sentinels, outer-record overlap, checked variant access, deterministic
malformed input, three nominal compiler rejections and private-owner field rejection. Run
`make check`.

## Compiler-port evidence

The numerical/compiler observations below record the original migration increment; see
[testing](../docs/testing.md) for current cumulative coverage and revision-specific CI results.

The pinned nightly port uses private `GuaranteeResult[T]` status/value storage, read-only `error`
and a success-precondition `value` accessor. `guaranteeFailure[T]` requires a non-success reason
for sibling adapters; there is no public raw success constructor. Defaults remain Uninitialized.
`OwnedGuarantees` uses a private nullable ARC reference, retained locally before nil checks.
The scan-before-allocation and full-source preflight policies, wire fields and error precedence
are preserved. Signature validity and state eligibility are not established by this codec.

`tools/test_runtime.py` runs all 7,617 original independent extrinsic requests, 7,555 corresponding
allocation-free inspections and 8,836 standalone capture/inspection/measurement/encoding cases.
`tests/guarantees_checks.py` parses standalone bytes directly, preserving budget error precedence
without introducing an artificial outer count. Tests include published fixtures, full population,
truncations, malformed inputs, unsigned configuration/budget boundaries and exact metadata/bytes.

The native suite retains late-failure atomicity and deliberate outer-record alias checks through
an aligned fixed array view. It adds parent replacement, escaped child retention and a warmed
1,000-cycle ARC release workload: live occupancy is unchanged at 16,608 bytes on the trial Mac.
That observation covers the isolated workload, not RSS or general leak freedom. Twenty-nine
runtime rejections guard public result paths and failure construction. Eight compilation checks
reject result/owner bypasses; three nominal checks reject slot, index and signature swaps.

Commands, compiler metadata, source/corpus hashes and exact diagnostics are retained in ignored
`build/tests/runtime/results.json` and adjacent logs. Local checked ARC/Clang LTO
verification does not establish Linux, block-composition or crypto parity; see
[the compiler record](../docs/nimony-trial.md).
