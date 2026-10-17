## Isolated public/private result reads must reach the exact success contract for defaults and actual failures.
import std/[assertions, cmdline, syncio]
include ../../src/codec/state_privileges
let useDefault = paramStr(2) == "default"
let policy = PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(2), maxBytes: ByteLimit(100))
var invalid = policy
invalid.cores = CoreCount(0)
var strict = policy
strict.maxAlways = ElementLimit(1)
var tiny = policy
tiny.maxBytes = ByteLimit(20)
var zeroBytes = policy
zeroBytes.maxBytes = ByteLimit(0)
var huge = policy
huge.maxAlways = ElementLimit(high(uint64))
huge.maxBytes = ByteLimit(high(uint64))
let original = PrivilegeState(assigners: @[ServiceIndex(17), ServiceIndex(29)], always: @[
  AlwaysAccumulate(service: ServiceIndex(255), gas: PrivilegeGas(high(uint64))),
  AlwaysAccumulate(service: ServiceIndex(256), gas: PrivilegeGas(0))])
let duplicate = PrivilegeState(assigners: @[ServiceIndex(0), ServiceIndex(0)], always: @[
  AlwaysAccumulate(service: ServiceIndex(1)), AlwaysAccumulate(service: ServiceIndex(1))])
let encoded = privilegeStateEntry(original, policy)
assert encoded.error == PrivilegeError.None
let owner = decodePrivilegeState(encoded.value.value, policy).value.snapshot
# Each hostile count follows exactly twenty fixed E4 role/assigner bytes for two cores.
proc prefix(): seq[byte] = newSeq[byte](20)
var framing = prefix()
framing.add(128'u8)
framing.add(0'u8)
var excess = prefix()
excess.add(3'u8)
var overflow = prefix()
overflow.add(255'u8)
# The canonical maximum count cannot license an unrepresentable typed pair array.
for i in 0..<8: overflow.add(255'u8)
var disordered = prefix()
disordered.add(2'u8)
# Two complete all-zero pairs duplicate their numeric service key independently of any missing bytes.
for i in 0..<24: disordered.add(0'u8)
var gas = prefix()
gas.add(1'u8)
# A complete E4 key still lacks its mandatory E8 gas field.
for i in 0..<4: gas.add(0'u8)
var cursor = 0
case paramStr(1)
of "entry-config":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[StateEntry]) else: privilegeStateEntry(
      original, invalid)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.InvalidConfig)
  discard parsed.value.value.len
of "entry-count":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[StateEntry]) else: privilegeStateEntry(
      default(PrivilegeState), policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.InvalidCount)
  discard parsed.value.value.len
of "entry-policy":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[StateEntry]) else: privilegeStateEntry(
      original, strict)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.LimitExceeded)
  discard parsed.value.value.len
of "entry-order":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[StateEntry]) else: privilegeStateEntry(
      duplicate, policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.NonCanonical)
  discard parsed.value.value.len
of "entry-bytes":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[StateEntry]) else: privilegeStateEntry(
      original, tiny)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.LimitExceeded)
  discard parsed.value.value.len
of "decode-config":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState([], invalid)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.InvalidConfig)
  discard parsed.value.consumed
of "decode-fixed":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState([
      0'u8], policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.Truncated)
  discard parsed.value.consumed
of "decode-framing":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState(
      framing, policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.NonCanonical)
  discard parsed.value.consumed
of "decode-count":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState(
      excess, policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.LimitExceeded)
  discard parsed.value.consumed
of "decode-overflow":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState(
      overflow, huge)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.LengthOverflow)
  discard parsed.value.consumed
of "decode-order":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState(
      disordered, policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.NonCanonical)
  discard parsed.value.consumed
of "decode-gas":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState(
      gas, policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.Truncated)
  discard parsed.value.consumed
of "decode-bytes":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState(
      encoded.value.value, tiny)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.LimitExceeded)
  discard parsed.value.consumed
of "owner":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState([], policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.Truncated)
  discard parsed.value.snapshot
of "consumed":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeRead]) else: decodePrivilegeState([], policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.Truncated)
  discard parsed.value.consumed
of "info":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[PrivilegeInfo]) else: privilegeInfo(default(PrivilegeSnapshot))
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.InvalidOwner)
  discard parsed.value.manager
of "assigner-owner":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[ServiceIndex]) else: privilegeAssignerAt(
      default(PrivilegeSnapshot), PrivilegeCoreIndex(0))
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.InvalidOwner)
  discard parsed.value
of "assigner-index":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[ServiceIndex]) else: privilegeAssignerAt(
      owner, PrivilegeCoreIndex(high(uint64)))
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.InvalidIndex)
  discard parsed.value
of "pair-owner":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[AlwaysAccumulate]) else: alwaysAccumulateAt(
      default(PrivilegeSnapshot), PrivilegeEntryIndex(0))
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.InvalidOwner)
  discard parsed.value.gas
of "pair-index":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[AlwaysAccumulate]) else: alwaysAccumulateAt(
      owner, PrivilegeEntryIndex(high(uint64)))
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.InvalidIndex)
  discard parsed.value.service
of "natural-truncated":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[uint64]) else: readNatural([], cursor, policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.Truncated)
  discard parsed.value
of "natural-framing":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[uint64]) else: readNatural([128'u8, 0],
      cursor, policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.NonCanonical)
  discard parsed.value
of "natural-bytes":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[uint64]) else: readNatural([0'u8], cursor, zeroBytes)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.LimitExceeded)
  discard parsed.value
of "layout-count":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[Layout]) else: scan(excess, policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.LimitExceeded)
  discard parsed.value.count
of "layout-consumed":
  # Neither uninitialized nor failed operations authorize the selected data or progress.
  let parsed = if useDefault: default(PrivilegeResult[Layout]) else: scan(gas, policy)
  assert parsed.error == (if useDefault: PrivilegeError.Uninitialized else: PrivilegeError.Truncated)
  discard parsed.value.consumed
else:
  # Unknown trusted operations must not count as an expected access rejection.
  assert false
