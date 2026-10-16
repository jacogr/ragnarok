## Supplementary immutable snapshot, fixed-copy and default/failure guard contracts.
import ../../src/[state_safrole, bounded, assurances]

## Reading an inactive success field must trigger the retained checked-build field guard.
proc guarded[T](parsed: StateComponentResult[T]) =
  var caught = false
  try:
    discard parsed.value # Default/failure alternatives cannot publish a fabricated success value.
  except FieldDefect:
    caught = true # Optimized ARC builds must retain variant checks.
  doAssert caught

## Verify source destruction and extracted-copy mutation cannot change retained validator records.
proc main() =
  let config = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
      maxBytes: ByteLimit(2017))
  var source = newSeq[StateValidator](6)
  var field: array[32, byte]
  field[0] = 17
  source[0].bandersnatch = StateBsKey(field)
  let encoded = validatorEntry(ValidatorChapter.Active, source, config)
  doAssert encoded.error == StateComponentError.None
  doAssert array[31, byte](encoded.value.key)[0] == 8
  var wire = encoded.value.value
  let decoded = decodeStateValidators(wire, config)
  doAssert decoded.error == StateComponentError.None
  let retained = decoded.value.value
  # Destroy both original wire and typed source after snapshot creation.
  for i in 0..<wire.len: wire[i] = 0
  source[0] = default(StateValidator)
  let item = validatorAt(retained, StateValidatorIndex(0))
  doAssert item.error == StateComponentError.None
  doAssert array[32, byte](item.value.bandersnatch)[0] == 17
  var copy = item.value
  copy.bandersnatch = StateBsKey(default(array[32, byte]))
  doAssert array[32, byte](validatorAt(retained, StateValidatorIndex(0)).value.bandersnatch)[0] == 17
  doAssert validatorCount(retained).value == 6
  guarded(default(StateComponentResult[StateTime]))
  guarded(default(StateComponentResult[StateComponentRead[ValidatorStateSnapshot]]))
  var replaced = retained
  replaced = default(ValidatorStateSnapshot)
  doAssert validatorCount(retained).value == 6
  let absent = validatorCount(replaced)
  doAssert absent.error == StateComponentError.InvalidOwner
  guarded(absent)
  doAssert validatorAt(replaced, StateValidatorIndex(0)).error == StateComponentError.InvalidOwner
  let missing = validatorAt(retained, StateValidatorIndex(high(uint64)))
  doAssert missing.error == StateComponentError.InvalidIndex
  guarded(missing)
  let rejected = validatorEntry(ValidatorChapter.Staging, source.toOpenArray(0, 4), config)
  doAssert rejected.error == StateComponentError.InvalidCount
  guarded(rejected)
  let short = decodeStateValidators(@[6'u8], config)
  doAssert short.error == StateComponentError.Truncated
  guarded(short)
  let time = timeEntry(StateTime(high(uint32)))
  doAssert time.value == @[255'u8, 255, 255, 255]
  doAssert uint32(decodeStateTime(time.value).value.value) == high(uint32)
  echo "PASS state components: immutable snapshots, fixed copies, nil/index and result guards"

main()
