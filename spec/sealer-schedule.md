# Safrole sealer schedule selection

Target: Gray Paper **0.8.0**, revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/safrole.tex`, equations `slotkeysequence` and `fallbackkeysequence`, including outside-in
sequencer Z. Source hashes and vector revision remain pinned in `spec/pins.json`.

## Inputs and result

`src/state/sealer_schedule.nim` implements `selectSafroleSchedule`. It borrows exact serialized
parent C(4), staged posterior C(4), posterior active roster C(8), parent/target slots, posterior
entropy[2], and finite chain/resource policy. Both chapters and the active roster are decoded
with exact consumption and independent byte/count ceilings before schedule generation. Parent and
staged accumulators must have strictly increasing identifiers; no sorting or repair is applied.
Null and repeated validator keys remain valid structural records.

The parent input supplies the old schedule and old accumulator. The staged input supplies the
pending roster, ring root and already admitted accumulator to preserve. These are deliberately
separate: ticket admission may have reset or replaced the staged accumulator on epoch crossing.
The caller supplies the correctly rotated active roster and entropy; this API does not authenticate
header entropy, prove stage order, verify submitted proofs or execute a complete Safrole transition.

Success retains a complete immutable C(4) candidate with only its schedule replaced. No store is
modified. Source buffers can be changed or retired after return. Extracted fixed records and mutable
re-encoding sources cannot mutate the retained snapshot. Default and failed results contain only
their reason; private payload extraction requires successful selection. Allocation failure retains
the client's fail-stop policy.

## Selection rules

- Slots strictly advance, without wrapping. Epoch length and tail start are positive, and the
  tail starts before the epoch ends. Schedule allocation and each E4 fallback index must fit.
- Within one epoch, preserve the complete parent schedule, including its ticket/key alternative.
- On exactly one epoch crossing, use tickets only when the parent slot was at/after tail start
  and the **parent** accumulator contains exactly one epoch of tickets. Z preserves whole ticket
  records in order `0, n-1, 1, n-2, ...`, including their original attempts.
- Every other crossing uses fallback: for each slot ordinal i, hash exactly posterior entropy[2]
  followed by little-endian E4(i), with Blake2b-256. Decode the first four hash bytes as a
  little-endian integer, reduce modulo the posterior active population, and copy that validator's
  Bandersnatch key. No domain prefix, count, terminator, null-key filtering or deduplication applies.
- Skipped epochs require fallback even with a saturated parent contest and a parent tail slot.
  Crossing before the tail and crossing with an unsaturated contest also require fallback.
- Same-epoch and ticket paths perform no fallback hashes. First/late primitive refusal returns
  `BackendFailure`, exposing no partial schedule. Output C(4) must independently fit the policy;
  replacing 32-byte keys with 33-byte tickets can exceed an otherwise valid input byte ceiling.

## Evidence and reproduction

The `sealer_schedule` Hastur suite compares complete posterior C(4) bytes for all **33 accepted**
Safrole cases at vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`: 15 tiny and 18 full.
The helper transports verbatim parent/posterior fields through existing independent codecs; it
contains no schedule permutation, fallback hashing or state-transition implementation. Every
consumed JSON blob is SHA-256 pinned, including the newly consumed full set-resize-4 case. Failed
whole-Safrole cases with unrelated proof/extrinsic errors do not define this isolated projection.

Authored native tests cover both retained variants, the exact adjacent/tail/saturation predicates,
multiple skipped epochs, an odd-length outside-in permutation, attempt preservation, a deliberately
different staged accumulator, null active keys, frozen independent E4 hash answers, first/last hash
refusal, invalid/wrapped slots, invalid/overflowing policies, malformed/suffixed inputs, noncanonical
contests, exact/input/output budget boundaries and escaped immutable owners. A scoped 1,000-cycle
success/late-refusal workload requires identical before/after live Nim allocation occupancy; it is
workload-specific ownership evidence, not a general leak audit.

Two compiler privacy checks and two runtime extraction probes protect the result. Run
`make check-modules check-unit check-failures check-guards check-python`. Reports, prepared fixture
hashes and native evidence remain under ignored `build/tests/`. M1 codec behavior and outstanding
specification checkpoints are unchanged; these tests do not establish complete Safrole execution.

## Next bounded work in this PR

Add atomic working-store publication of the candidate C(4), retaining the parent snapshot through
rotation, entropy/time and ticket admission. Check all required stage inputs and test no-op,
rollback/budget refusal, snapshot lifetime and published pipeline projections. Header epoch/winner
marker validation follows as a separate slice; seal authentication and complete block execution
remain later work.
