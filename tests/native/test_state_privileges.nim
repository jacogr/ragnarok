## Supplementary snapshot, domain, index, late-failure and runtime variant-guard contracts.
import ../../src/codec/[state_privileges, bounded]

## Failed/default results must reject access to success payloads in checked optimized builds.
proc guarded[T](value: PrivilegeResult[T]) =
  var caught = false
  try:
    discard value.value # A failed alternative cannot fabricate application data.
  except FieldDefect:
    caught = true # Field guards remain enabled under ARC/Clang LTO.
  doAssert caught

## A snapshot copied out of local scope retains independent fixed role/pair values.
proc captured(config: PrivilegeConfig): PrivilegeSnapshot =
  var source = PrivilegeState(manager: ServiceIndex(127), delegator: ServiceIndex(128),
    registrar: ServiceIndex(high(uint32)), assigners: @[ServiceIndex(255), ServiceIndex(256)],
    always: @[AlwaysAccumulate(service: ServiceIndex(255), gas: PrivilegeGas(high(uint64))),
      AlwaysAccumulate(service: ServiceIndex(256), gas: PrivilegeGas(0))])
  let encoded = privilegeStateEntry(source, config)
  doAssert encoded.error == PrivilegeError.None
  doAssert array[31, byte](encoded.value.key)[0] == 12
  source.assigners[0] = ServiceIndex(0)
  source.always[0].gas = PrivilegeGas(0)
  doAssert encoded.value.value[4] == 255
  var bytes = encoded.value.value
  let parsed = decodePrivilegeState(bytes, config)
  doAssert parsed.error == PrivilegeError.None and parsed.value.consumed == bytes.len
  result = parsed.value.snapshot
  # Destroy every caller buffer before observations outside this scope.
  for i in 0..<bytes.len: bytes[i] = 0
  source = default(PrivilegeState)

## Check retained handles, independent extraction copies and typed owner/index/failure contracts.
proc main() =
  doAssert sizeof(int) == 8 and sizeof(AlwaysAccumulate) == 16
  let config = PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(2), maxBytes: ByteLimit(100))
  let owner = captured(config)
  let info = privilegeInfo(owner).value
  doAssert uint32(info.manager) == 127 and uint32(info.delegator) == 128 and uint32(
      info.registrar) == high(uint32)
  doAssert info.cores == 2 and info.always == 2
  doAssert uint32(privilegeAssignerAt(owner, PrivilegeCoreIndex(0)).value) == 255
  doAssert uint32(privilegeAssignerAt(owner, PrivilegeCoreIndex(1)).value) == 256
  var pair = alwaysAccumulateAt(owner, PrivilegeEntryIndex(0)).value
  doAssert uint32(pair.service) == 255 and uint64(pair.gas) == high(uint64)
  pair.gas = PrivilegeGas(0)
  pair.service = ServiceIndex(0)
  doAssert uint64(alwaysAccumulateAt(owner, PrivilegeEntryIndex(0)).value.gas) == high(uint64)
  var replaced = owner
  replaced = default(PrivilegeSnapshot)
  doAssert privilegeInfo(owner).value.always == 2
  guarded(privilegeInfo(replaced))
  guarded(privilegeAssignerAt(replaced, PrivilegeCoreIndex(0)))
  guarded(alwaysAccumulateAt(replaced, PrivilegeEntryIndex(0)))
  let badCore = privilegeAssignerAt(owner, PrivilegeCoreIndex(high(uint64)))
  doAssert badCore.error == PrivilegeError.InvalidIndex
  guarded(badCore)
  let badEntry = alwaysAccumulateAt(owner, PrivilegeEntryIndex(2))
  doAssert badEntry.error == PrivilegeError.InvalidIndex
  guarded(badEntry)
  guarded(default(PrivilegeResult[PrivilegeRead]))
  var state = PrivilegeState(assigners: @[ServiceIndex(0), ServiceIndex(0)])
  let empty = privilegeStateEntry(state, PrivilegeConfig(cores: CoreCount(2),
    maxAlways: ElementLimit(0), maxBytes: ByteLimit(21)))
  doAssert empty.error == PrivilegeError.None and empty.value.value.len == 21
  state.always = @[AlwaysAccumulate(service: ServiceIndex(1)), AlwaysAccumulate(
      service: ServiceIndex(1))]
  let duplicate = privilegeStateEntry(state, config)
  doAssert duplicate.error == PrivilegeError.NonCanonical
  guarded(duplicate)
  var late = empty.value.value
  late[20] = 1
  late.add(@[byte(0), 0, 0, 0]) # A complete E4 key does not license a missing E8 gas allowance.
  let truncated = decodePrivilegeState(late, config)
  doAssert truncated.error == PrivilegeError.Truncated
  guarded(truncated)
  echo "PASS privileges: immutable capture, scope retention, independent pairs, nominal indices and result guards"

main()
