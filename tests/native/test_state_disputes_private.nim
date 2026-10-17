## Project-only arithmetic, retained-owner and scoped ARC checks; no compiler/private-runtime hooks.
import std/[assertions, syncio]
include ../../src/codec/state_disputes

## Small explicit per-set and whole-parent ceilings include all four canonical count prefixes.
proc policy(): DisputeStateConfig =
  DisputeStateConfig(perSet: ElementLimit(3), totalItems: ElementLimit(8), maxBytes: ByteLimit(300))

## Construct four canonical sets directly, allowing repeated identities across independently framed domains.
proc source(marker: byte): DisputeState =
  result = default(DisputeState)
  var first = default(array[32, byte])
  var second = default(array[32, byte])
  first[0] = marker
  second[0] = marker+1
  # Report membership remains independent for good, bad and wonky sets.
  for kind in [JudgmentSet.Good, JudgmentSet.Bad, JudgmentSet.Wonky]:
    result.reports[kind] = @[DisputeHash(first)]
  result.offenders = @[OffenderKey(first), OffenderKey(second)]

## Return an owner after all callee-local sources/entry/wire aliases retire or are destroyed.
proc escaped(marker: byte): DisputeStateSnapshot =
  var original = source(marker)
  let encoded = disputeStateEntry(original, policy())
  assert encoded.error == DisputeStateError.None
  var wire = encoded.value.value
  let parsed = decodeDisputeState(wire, policy())
  assert parsed.error == DisputeStateError.None
  result = parsed.value.snapshot
  original = default(DisputeState)
  # Private typed capture must survive mutation of every original wire byte.
  for i in 0..<wire.len: wire[i] = 0

## Each scope releases replaced/retained parents, copied fields and late malformed parent temporaries.
proc cycle() =
  var owner = escaped(17)
  let alias = owner
  owner = escaped(29)
  assert array[32, byte](judgedReportAt(alias, JudgmentSet.Wonky, DisputeStateIndex(0)).value)[0] == 17
  assert array[32, byte](stateOffenderAt(owner, DisputeStateIndex(1)).value)[0] == 30
  var info = disputeStateInfo(alias).value
  info.reports[JudgmentSet.Good] = 0
  info.offenders = 0
  assert disputeStateInfo(alias).value.reports[JudgmentSet.Good] == 1
  assert disputeStateInfo(alias).value.offenders == 2
  var copy = stateOffenderAt(alias, DisputeStateIndex(0)).value
  copy = default(OffenderKey)
  assert array[32, byte](stateOffenderAt(alias, DisputeStateIndex(0)).value)[0] == 17
  owner = default(DisputeStateSnapshot)
  assert disputeStateInfo(owner).error == DisputeStateError.InvalidOwner
  assert disputeStateInfo(alias).value.offenders == 2
  assert judgedReportAt(alias, JudgmentSet(255), DisputeStateIndex(0)).error ==
      DisputeStateError.InvalidTag
  assert judgedReportAt(alias, JudgmentSet.Good, DisputeStateIndex(high(uint64))).error ==
      DisputeStateError.InvalidIndex
  assert stateOffenderAt(alias, DisputeStateIndex(high(uint64))).error ==
      DisputeStateError.InvalidIndex
  var original = source(43)
  var wire = disputeStateEntry(original, policy()).value.value
  # A duplicate final offender rejects the whole parent before any retained storage is allocated.
  for i in 0..<32:
    let octet = wire[wire.len-64+i]
    wire[wire.len-32+i] = octet
  let before = getOccupiedMem()
  assert decodeDisputeState(wire, policy()).error == DisputeStateError.NonCanonical
  assert before == getOccupiedMem()
  let duplicate = original.offenders[0]
  original.offenders[1] = duplicate
  assert disputeStateEntry(original, policy()).error == DisputeStateError.NonCanonical
  let empty = decodeDisputeState([0'u8, 0, 0, 0], policy()).value.snapshot
  assert disputeStateInfo(empty).value.offenders == 0
  assert stateOffenderAt(empty, DisputeStateIndex(0)).error == DisputeStateError.InvalidIndex

# Direct stride/count probes never fabricate impossible sequence descriptors or allocate advertised extents.
let huge = DisputeStateConfig(perSet: ElementLimit(high(uint64)), totalItems: ElementLimit(high(
    uint64)), maxBytes: ByteLimit(high(uint64)))
var total = 0'u64
var cursor = high(int)-33
assert charge(1, 1, huge, total, cursor) == DisputeStateError.None
assert cursor == high(int) and total == 1
assert charge(0, 1, huge, total, cursor) == DisputeStateError.LengthOverflow
assert cursor == high(int) and total == 1
assert charge(0, 0, huge, total, cursor) == DisputeStateError.None
cursor = high(int)-32
assert charge(1, 1, huge, total, cursor) == DisputeStateError.LengthOverflow
assert cursor == high(int)-32 and total == 1
cursor = 0
assert charge(high(uint64), 1, huge, total, cursor) == DisputeStateError.LimitExceeded
assert cursor == 0 and total == 1
total = 0
assert charge(high(uint64), 1, huge, total, cursor) == DisputeStateError.LengthOverflow
assert cursor == 0 and total == 0
# Warm up allocator initialization before comparing this isolated live occupancy workload.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Scope exit releases the final immutable owner and every source/copy/failure temporary.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
echo "STATE_DISPUTES_ARC_RELEASE cycles=1000 occupied_before=", beforeRelease, " occupied_after=", afterRelease
echo "Nimony chapter 5: canonical domain separation, escaped/replaced owners, copied fields and scoped ARC release passed"
