# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_annulled_creation_union_arc_release"}

## Real new/supervisor/eject guests prove final n membership, original cancellation and same-frame collision invalidity.
import std/[assertions, syncio]
import ../../../src/state/accumulation/[creation_union as accumulation_creation_union,
    annulment as accumulation_annulment, dispatch as accumulation_dispatch,
    outcome as accumulation_outcome, effects as accumulation_effects, inputs as accumulation_inputs,
    invocation as accumulation_invocation]
import ../../../src/state/store
import ../../../src/codec/[bounded, composite]
import ../../../src/codec/state/[accounts as state_accounts, service_values as state_service_values,
    privileges as state_privileges, layout as state_layout, trie as state_trie]
import ../../../src/chain/parameters
import ../../../src/pvm/machine
import ../../support/[accumulation_batch_context, accumulation_annulment_context,
  pvm_accumulation_context, pvm_accumulation_program, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc profile(): Parameters =
  ## Zero deposits isolate membership while every host still executes under the real gas schedule.
  var wire = encodeParameters(pvmParameters())
  for index in 0..<24: wire[index] = 0 # Complete flat/item/byte deposit words.
  decodeParameters(wire).value
proc program(foreignTarget = 0'u64, supervisor = 0'u64, panic = false,
    checkpoint = false, recreate = false): seq[byte] =
  ## Literal packed request and opcode boundaries invoke genuine allocation and account membership mutations.
  var payload = newSeq[byte](60)
  payload[32] = 1 # Code length one; hash and minimum gas are exactly zero.
  var code: seq[seq[byte]] = @[]
  if recreate:
    code.add(registerImmediate(7, 77))
    code.add(@[10'u8, 23]) # Genuine eligible eject precedes reserved registrar recreation.
  for instruction in @[registerImmediate(7, high(uint64)),
      registerImmediate(8, if recreate: 77'u64 else: high(uint64)), registerImmediate(9, 0),
      registerImmediate(10, 196608), @[10'u8, 20]]:
    code.add(instruction) # Successful new marks the actual payer and captures the actual child.
  if foreignTarget != 0:
    code.add(registerImmediate(7, foreignTarget))
    code.add(registerImmediate(8, supervisor))
    code.add(@[10'u8, 29]) # A matching prior supervisor records even a restored-equal foreign membership.
  if checkpoint: code.add(@[10'u8, 19]) # Real checkpoint retains creation before exceptional terminal selection.
  if panic: code.add(@[0'u8]) # Actual panic selects the exceptional context.
  code.add(@[50'u8, 0])
  guestEnvelope(code, writable = payload)
proc put(fixture: var BatchFixture, entry: StateEntry) =
  ## Author complete prior rows before either outcome captures their ownership.
  assert fixture.state.apply([StateWrite(key: entry.key, kind: StateWriteKind.Put,
    value: entry.value)]).error == StateStoreError.None, "genuine complete prior amendment"
proc supervisor(fixture: var BatchFixture, service, owner: uint32) =
  ## Seed exact prior incarnation without changing any runtime decision.
  let key = chapterServiceKey(StateChapter(255), ServiceIndex(service))
  var metadata = decodeServiceMetadata(fixture.state.snapshot.value.lookup(key).value.bytes,
    ByteLimit(ServiceMetadataBytes)).value.metadata
  metadata.supervisor = ServiceIndex(owner)
  fixture.put(serviceMetadataEntry(ServiceIndex(service), metadata, ByteLimit(
      ServiceMetadataBytes)).value)
proc source(cancelA = false, cancelB = false, panic = false, checkpoint = false,
    disabled = false, reverse = false, collision = false,
        recreate = false): PreparedAccumulationAnnulment =
  ## Real common-frame executions are the only source of selected creation/cancellation facts.
  var fixture = batchFixture(incoming = false,
    firstEnvelope = program(if cancelB: 99'u64 else: 0'u64, 42, panic, checkpoint, recreate),
    secondEnvelope = program(if cancelA: 42'u64 else: 0'u64, 99))
  fixture.supervisor(42, if cancelA: 99'u32 else: 42'u32)
  fixture.supervisor(99, if cancelB: 42'u32 else: 99'u32)
  if recreate:
    fixture.put(serviceMetadataEntry(ServiceIndex(77), ServiceMetadata(supervisor: ServiceIndex(42)),
      ByteLimit(ServiceMetadataBytes)).value) # Existing empty, old junior is genuinely ejectable.
    let roles = PrivilegeState(manager: ServiceIndex(0), registrar: ServiceIndex(42),
      assigners: @[ServiceIndex(0), ServiceIndex(0)])
    fixture.put(privilegeStateEntry(roles, PrivilegeConfig(cores: CoreCount(2),
      maxAlways: ElementLimit(0), maxBytes: ByteLimit(21))).value) # Original registrar may explicitly recreate77.
  if collision:
    # Independently frozen BLAKE2b truncation collision: compact95434/115583, entropy zero, slot128.
    for index in 0..<2:
      let old = ServiceIndex(if index == 0: 42 else: 99)
      let target = ServiceIndex(if index == 0: 95434 else: 115583)
      let metadata = decodeServiceMetadata(fixture.state.snapshot.value.lookup(
        chapterServiceKey(StateChapter(255), old)).value.bytes, ByteLimit(
            ServiceMetadataBytes)).value.metadata
      let hash = ServicePreimageHash(array[32, byte](metadata.codeHash))
      let key = servicePreimageKey(old, hash, ByteLimit(32)).value
      let bytes = fixture.state.snapshot.value.lookup(key).value.bytes
      fixture.put(serviceMetadataEntry(target, metadata, ByteLimit(ServiceMetadataBytes)).value)
      fixture.put(servicePreimageEntry(target, hash, bytes, ServiceEntryLimits(keyBytes: ByteLimit(32),
        valueBytes: ByteLimit(bytes.len))).value) # Both real invokers have the same ordinary ready-code proof.
    fixture.inputs = prepareAccumulationInputs(fixture.inputs.invocationOperands.value, [],
      [AlwaysAccumulate(service: ServiceIndex(95434), gas: PrivilegeGas(100000)),
       AlwaysAccumulate(service: ServiceIndex(115583), gas: PrivilegeGas(100000))],
      AccumulationInputConfig(inputs: ElementLimit(0), allowances: ElementLimit(2),
          services: ElementLimit(2))).value
  let capacity = ElementLimit(if disabled: 0'u64 else: 2'u64)
  let a = batchExecution(fixture, 0, parameters = profile(), copyLimit = MemoryByteLimit(60),
    createdAccounts = capacity, deletedAccounts = ElementLimit(1), modifiedAccounts = ElementLimit(8),
    serviceProbes = ServiceProbeLimit(1))
  let b = batchExecution(fixture, 1, parameters = profile(), copyLimit = MemoryByteLimit(60),
    createdAccounts = capacity, deletedAccounts = ElementLimit(1), modifiedAccounts = ElementLimit(8),
    serviceProbes = ServiceProbeLimit(1))
  assert a.error == AccumulationDispatchError.None, $a.error
  assert b.error == AccumulationDispatchError.None, $b.error
  if collision:
    assert uint64(machineInfo(a.value.machine).value.registers[7]) == 3226037778'u64
    assert uint64(machineInfo(b.value.machine).value.registers[7]) == 3226037778'u64, "two real guests reproduce the same-frame collision"
  let first = normalizeAccumulationOutcome(a).value
  let second = normalizeAccumulationOutcome(b).value
  let original = if reverse: @[second, first] else: @[first, second]
  prepareAccumulationAnnulment(fixture.inputs, fixture.state.snapshot.value, original,
      annulmentPolicy()).value
proc policy(): AccumulationCreationLimits =
  ## Bound all source traversal, enabled facts, final rows and predicate comparisons explicitly.
  AccumulationCreationLimits(outcomes: ElementLimit(2), creations: ElementLimit(2),
    accounts: ElementLimit(2), checks: ElementLimit(128))
proc check(cancelA, cancelB: bool, reverse = false) =
  ## Genuine cancellations remove complete child contributions, never just raw fact counters.
  let original = source(cancelA, cancelB, reverse = reverse)
  assert original.annulmentInfo.value.annulled == int(cancelA)+int(cancelB)
  failHash(1)
  let plan = prepareAccumulationCreationUnion(original, policy()).value
  let facts = plan.creationUnionInfo.value
  let count = 2-int(cancelA)-int(cancelB)
  assert facts.accounts == count and facts.creations == count and facts.outcomes == 2
  assert plan.creationUnionSource.value.annulmentInfo.value.annulled == int(cancelA)+int(cancelB)
  var previous = 0'u32
  for index in 0..<count:
    let ordinal = AccumulationCreationIndex(uint64(index))
    let row = plan.createdAccountAt(ordinal).value
    assert uint32(row.service) > previous, "numeric service order is independent of original outcome order"
    previous = uint32(row.service)
    assert (uint32(row.producer) == 42 and not cancelA) or (uint32(row.producer) == 99 and not cancelB)
    let outcome = plan.createdAccountOutcomeAt(ordinal).value
    assert uint32(outcome.outcomeInfo.value.service) == uint32(row.producer), "retain exact actual contributing outcome"
    var metadata = plan.createdAccountMetadataAt(ordinal).value
    assert uint32(metadata.parent) == uint32(row.producer) and uint32(metadata.created) == 128
    assert uint32(metadata.storageItems) == 2 and uint64(metadata.storageBytes) == 82
    metadata.balance = AccountBalance(99)
    assert uint64(plan.createdAccountMetadataAt(ordinal).value.balance) == 0, "copied metadata cannot mutate retained values"
    let snapshot = plan.createdAccountSnapshotAt(ordinal).value
    let key = chapterServiceKey(StateChapter(255), row.service)
    assert snapshot.lookup(key).value.byteLength == ServiceMetadataBytes, "selected final snapshot belongs to same logical child"
    assert original.annulmentPrior.value.lookup(key).error == StateStoreError.MissingKey, "n contains only prior-absent IDs"
  let invalid = plan.createdAccountAt(AccumulationCreationIndex(high(uint64)))
  assert invalid.error == AccumulationCreationError.InvalidIndex
  var exact = policy()
  exact.checks = ElementLimit(facts.checks)
  exact.creations = ElementLimit(count)
  exact.accounts = ElementLimit(count)
  assert prepareAccumulationCreationUnion(original, exact).error == AccumulationCreationError.None
  for kind in 0..<4:
    var short = exact
    if kind == 0: short.outcomes = ElementLimit(1) # Canceled original outcomes still consume traversal.
    if kind == 1: short.checks = ElementLimit(facts.checks-1) # Exact charged predicates remain independent.
    if kind == 2:
      if count == 0: continue # Zero selected facts fit an explicit zero ceiling.
      short.creations = ElementLimit(count-1)
    if kind == 3:
      if count == 0: continue # Empty canonical union needs no descriptors.
      short.accounts = ElementLimit(count-1)
    assert prepareAccumulationCreationUnion(original, short).error ==
        AccumulationCreationError.LimitExceeded
  assert hashCalls() == 0, "logical union preparation and extraction compute no state hashes"
  failHash(0)
for a in [false, true]:
  for b in [false, true]:
    check(a, b) # Every original cancellation combination, including mutual cancellation.
check(false, false, reverse = true)
check(true, true, reverse = true)
for checkpoint in [false, true]:
  let original = source(panic = true, checkpoint = checkpoint)
  let plan = prepareAccumulationCreationUnion(original, policy()).value
  assert plan.creationUnionInfo.value.accounts == (if checkpoint: 2 else: 1), "actual exceptional selection retains only checkpointed child maps"
for reverse in [false, true]:
  let original = source(collision = true, reverse = reverse)
  failHash(1)
  assert prepareAccumulationCreationUnion(original, policy()).error ==
      AccumulationCreationError.Collision,
    "distinct original producers may not contribute the same new ID"
  assert hashCalls() == 0
  failHash(0)
let recreated = source(recreate = true)
let recreatedPlan = prepareAccumulationCreationUnion(recreated, policy()).value
assert recreatedPlan.creationUnionInfo.value.creations == 2 and
    recreatedPlan.creationUnionInfo.value.accounts == 1,
  "genuine prior-ID recreation is inspected but excluded from n"
assert uint32(recreatedPlan.createdAccountAt(AccumulationCreationIndex(0)).value.producer) == 99
let disabled = source(disabled = true)
assert prepareAccumulationCreationUnion(disabled, policy()).error ==
    AccumulationCreationError.IncompleteFacts
let canceledDisabled = source(cancelA = true, cancelB = true, disabled = true)
assert prepareAccumulationCreationUnion(canceledDisabled, policy(
  )).value.creationUnionInfo.value.accounts == 0,
  "N needs no raw creation proof from discarded contexts"
let invalid = prepareAccumulationCreationUnion(default(PreparedAccumulationAnnulment), policy())
assert invalid.error == AccumulationCreationError.InvalidSource
let absent = default(PreparedAccumulationCreationUnion)
assert absent.creationUnionInfo.error == AccumulationCreationError.Uninitialized
assert absent.creationUnionSource.error == AccumulationCreationError.Uninitialized
let original = source()
let empty = prepareAccumulationAnnulment(original.annulmentInputs.value,
    original.annulmentPrior.value, [],
  default(AccumulationAnnulmentLimits)).value
assert prepareAccumulationCreationUnion(empty, default(
    AccumulationCreationLimits)).value.creationUnionInfo.value.accounts == 0
let before = getOccupiedMem()
for iteration in 0..<1000:
  let local = prepareAccumulationCreationUnion(original, policy()).value
  assert local.creationUnionInfo.value.accounts == 2
  discard local.createdAccountOutcomeAt(AccumulationCreationIndex(
      0)).value # Retained source owners release with copied metadata rows.
let after = getOccupiedMem()
assert before == after, "creation union owners release"
recordArcRelease("pvm_annulled_creation_union", 1000, before, after)
echo "PVM annulled creation union passed"
echo "ARC_RELEASE cycles=1000 unchanged"
