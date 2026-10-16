## Supplementary whole-state ownership, type-separated fields, result/index and copied-value checks.
import ../../src/[state_disputes, bounded]

## Failed/default results must retain inactive-field protection in checked optimized builds.
proc guarded[T](parsed: DisputeStateResult[T]) =
  var caught = false
  try:
    discard parsed.value # Failure cannot fabricate a successful owner, count or identity.
  except FieldDefect:
    caught = true # Runtime variant checks remain active under ARC/Clang LTO.
  doAssert caught

## Validate source/wire/copy/handle independence and typed errors through the public owner interface.
proc main() =
  doAssert sizeof(int) == 8 and sizeof(DisputeHash) == 32 and sizeof(OffenderKey) == 32
  let config = DisputeStateConfig(perSet: ElementLimit(3), totalItems: ElementLimit(8),
      maxBytes: ByteLimit(300))
  var a, b: array[32, byte]
  a[0] = 17
  b[0] = 18
  var source: DisputeState
  source.reports[JudgmentSet.Good] = @[DisputeHash(a), DisputeHash(b)]
  source.reports[JudgmentSet.Wonky] = @[DisputeHash(a)]
  source.offenders = @[OffenderKey(a), OffenderKey(b)]
  let encoded = disputeStateEntry(source, config)
  doAssert encoded.error == DisputeStateError.None
  doAssert array[31, byte](encoded.value.key)[0] == 5
  source.reports[JudgmentSet.Good][0] = default(DisputeHash)
  doAssert encoded.value.value[1] == 17
  var wire = encoded.value.value
  let parsed = decodeDisputeState(wire, config)
  doAssert parsed.error == DisputeStateError.None
  let retained = parsed.value.snapshot
  source = default(DisputeState)
  # Destroy caller wire after whole-parent private capture.
  for i in 0..<wire.len: wire[i] = 0
  let info = disputeStateInfo(retained)
  doAssert info.error == DisputeStateError.None
  doAssert info.value.reports[JudgmentSet.Good] == 2 and info.value.reports[JudgmentSet.Bad] == 0
  doAssert info.value.offenders == 2
  let first = judgedReportAt(retained, JudgmentSet.Good, DisputeStateIndex(0))
  doAssert first.error == DisputeStateError.None and array[32, byte](first.value)[0] == 17
  var copy = first.value
  copy = default(DisputeHash)
  doAssert array[32, byte](judgedReportAt(retained, JudgmentSet.Good, DisputeStateIndex(0)).value)[0] == 17
  doAssert array[32, byte](stateOffenderAt(retained, DisputeStateIndex(0)).value)[0] == 17
  var replaced = retained
  replaced = default(DisputeStateSnapshot)
  doAssert disputeStateInfo(retained).value.offenders == 2
  guarded(disputeStateInfo(replaced))
  guarded(judgedReportAt(replaced, JudgmentSet.Good, DisputeStateIndex(0)))
  let absent = judgedReportAt(retained, JudgmentSet.Bad, DisputeStateIndex(0))
  doAssert absent.error == DisputeStateError.InvalidIndex
  guarded(absent)
  let index = stateOffenderAt(retained, DisputeStateIndex(high(uint64)))
  doAssert index.error == DisputeStateError.InvalidIndex
  guarded(index)
  guarded(default(DisputeStateResult[DisputeStateRead]))
  let empty = disputeStateEntry(default(DisputeState), DisputeStateConfig(perSet: ElementLimit(0),
    totalItems: ElementLimit(0), maxBytes: ByteLimit(4)))
  doAssert empty.error == DisputeStateError.None and empty.value.value == @[0'u8, 0, 0, 0]
  source.offenders = @[OffenderKey(a), OffenderKey(a)]
  let duplicate = disputeStateEntry(source, config)
  doAssert duplicate.error == DisputeStateError.NonCanonical
  guarded(duplicate)
  let short = decodeDisputeState(@[0'u8, 0, 0], config)
  doAssert short.error == DisputeStateError.Truncated
  guarded(short)
  echo "PASS dispute state: immutable capture, copied identities, empty sets, domain/index and failure guards"

main()
