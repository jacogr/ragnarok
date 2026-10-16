## Supplementary whole-state ownership, type-separated fields, result/index and copied-value checks.
import std/[assertions, syncio]
import ../../src/codec/[state_disputes, bounded]

## Validate source/wire/copy/handle independence and typed errors through the public owner interface.
proc main() =
  assert sizeof(int) == 8 and sizeof(DisputeHash) == 32 and sizeof(OffenderKey) == 32
  let config = DisputeStateConfig(perSet: ElementLimit(3), totalItems: ElementLimit(8),
      maxBytes: ByteLimit(300))
  var a = default(array[32, byte])
  var b = default(array[32, byte])
  a[0] = 17
  b[0] = 18
  var source = default(DisputeState)
  source.reports[JudgmentSet.Good] = @[DisputeHash(a), DisputeHash(b)]
  source.reports[JudgmentSet.Wonky] = @[DisputeHash(a)]
  source.offenders = @[OffenderKey(a), OffenderKey(b)]
  let encoded = disputeStateEntry(source, config)
  assert encoded.error == DisputeStateError.None
  assert array[31, byte](encoded.value.key)[0] == 5
  source.reports[JudgmentSet.Good][0] = default(DisputeHash)
  assert encoded.value.value[1] == 17
  var wire = encoded.value.value
  let parsed = decodeDisputeState(wire, config)
  assert parsed.error == DisputeStateError.None
  let retained = parsed.value.snapshot
  source = default(DisputeState)
  # Destroy caller wire after whole-parent private capture.
  for i in 0..<wire.len: wire[i] = 0
  let info = disputeStateInfo(retained)
  assert info.error == DisputeStateError.None
  assert info.value.reports[JudgmentSet.Good] == 2 and info.value.reports[JudgmentSet.Bad] == 0
  assert info.value.offenders == 2
  let first = judgedReportAt(retained, JudgmentSet.Good, DisputeStateIndex(0))
  assert first.error == DisputeStateError.None and array[32, byte](first.value)[0] == 17
  var copy = first.value
  copy = default(DisputeHash)
  assert array[32, byte](judgedReportAt(retained, JudgmentSet.Good, DisputeStateIndex(0)).value)[0] == 17
  assert array[32, byte](stateOffenderAt(retained, DisputeStateIndex(0)).value)[0] == 17
  var replaced = retained
  replaced = default(DisputeStateSnapshot)
  assert disputeStateInfo(retained).value.offenders == 2
  let absent = judgedReportAt(retained, JudgmentSet.Bad, DisputeStateIndex(0))
  assert absent.error == DisputeStateError.InvalidIndex
  let index = stateOffenderAt(retained, DisputeStateIndex(high(uint64)))
  assert index.error == DisputeStateError.InvalidIndex
  let empty = disputeStateEntry(default(DisputeState), DisputeStateConfig(perSet: ElementLimit(0),
    totalItems: ElementLimit(0), maxBytes: ByteLimit(4)))
  assert empty.error == DisputeStateError.None and empty.value.value == @[0'u8, 0, 0, 0]
  source.offenders = @[OffenderKey(a), OffenderKey(a)]
  let duplicate = disputeStateEntry(source, config)
  assert duplicate.error == DisputeStateError.NonCanonical
  let short = decodeDisputeState(@[0'u8, 0, 0], config)
  assert short.error == DisputeStateError.Truncated
  echo "PASS dispute state: immutable capture, copied identities, empty sets, domain/index and failure guards"

main()
