# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native initial partialstate/I witnesses: chapter identity, limits, paired dimensions and signed provenance.
## Hastur entry point verifies retained immutable child views and complete ARC release without execution.

# @@Verification={"arc": "accumulation_context_arc_release"}

import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_context as state_accumulation_context
import ../../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../../src/state/accumulation_service as state_accumulation_service
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_operands as state_accumulation_operands
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_authorization as codec_state_authorization
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_privileges as codec_state_privileges
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/c2_records as codec_c2_records
import ../../../src/crypto/primitives as crypto_primitives
import ../../support/state_report_context
import ../../support/state_report_admission_context
import ../../support/testing_arc_evidence

## Refuse provider hashing after fixture construction to prove initialization performs no state writes/hashing.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## All queue inputs use finite tiny-profile budgets, retaining the shared genuinely signed fixture semantics.
proc queueConfig(): AccumulationQueueConfig =
  AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(12),
    perSlot: ElementLimit(100), totalItems: ElementLimit(100), perDependencies: ElementLimit(100),
    totalDependencies: ElementLimit(1000), reportBytes: ByteLimit(100000), maxBytes: ByteLimit(
        1000000)),
    items: ElementLimit(100), dependencies: ElementLimit(1000))

## Reuse independent operand/input ceilings for both service-only and signed report-driven preparations.
proc roundConfig(): AccumulationRoundConfig =
  AccumulationRoundConfig(blockGas: Gas(100), reportGas: Gas(0),
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(10),
        maxBytes: ByteLimit(1000)),
    operands: AccumulationOperandConfig(reports: ElementLimit(10), operands: ElementLimit(100),
        services: ElementLimit(100),
      totalBytes: ByteLimit(1000000), totalBlobBytes: ByteLimit(1000000),
      operand: OperandLimits(outputBytes: ByteLimit(100000), authBytes: ByteLimit(100000),
        totalBlobBytes: ByteLimit(200000), maxBytes: ByteLimit(1000000))),
    inputs: AccumulationInputConfig(inputs: ElementLimit(100), allowances: ElementLimit(10),
        services: ElementLimit(100)))

## Exact tiny-profile policy: two queues, six staging validators and one allowance.
proc contextConfig(): AccumulationContextConfig =
  AccumulationContextConfig(validators: ValidatorCount(6),
    queues: AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
        maxBytes: ByteLimit(5120)),
    staging: ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
        maxBytes: ByteLimit(2017)),
    privileges: PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(1),
        maxBytes: ByteLimit(33)),
    totalBytes: ByteLimit(7170))

## Give every core/position/record/role distinguishable contents, retaining protocol ordering.
proc components(seed = 0): seq[StateEntry] =
  let cfg = contextConfig()
  var rows = newSeq[AuthorizerRow](2)
  # Ordered queues preserve repeated hashes and every byte, including the final queue position.
  for core in 0..<2:
    rows[core] = newSeq[AuthorizerHash](80)
    for position in 0..<80:
      var bytes = default(array[32, byte])
      for i in 0..<32: bytes[i] = byte((seed+core*80+position+i) mod 256) # Distinguish all positions.
      rows[core][position] = AuthorizerHash(bytes: bytes)
  var validators = newSeq[StateValidator](6)
  # Independently patterned fields expose record/field/byte swaps in the retained staging owner.
  for index in 0..<6:
    var bs = default(array[32, byte])
    var ed = default(array[32, byte])
    var bls = default(array[144, byte])
    var meta = default(array[128, byte])
    for i in 0..<32: bs[i] = byte((seed+index+i) mod 256); ed[i] = byte((
        seed+index+i+1) mod 256) # Separate key roles.
    for i in 0..<144: bls[i] = byte((seed+index+i+2) mod 256) # Preserve the full BLS width.
    for i in 0..<128: meta[i] = byte((seed+index+i+3) mod 256) # Preserve opaque metadata too.
    validators[index] = StateValidator(bandersnatch: StateBsKey(bs), ed25519: StateEdKey(ed),
      bls: StateBlsKey(bls), metadata: StateValidatorMetadata(meta))
  let roles = PrivilegeState(manager: ServiceIndex(7), delegator: ServiceIndex(8),
      registrar: ServiceIndex(9),
    assigners: @[ServiceIndex(11), ServiceIndex(12)],
    always: @[AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(17))])
  @[authorizationEntry(AuthorizationKind.Queues, rows, cfg.queues).value,
    validatorEntry(ValidatorChapter.Staging, validators, cfg.staging).value,
    privilegeStateEntry(roles, cfg.privileges).value]

## Retain a real service bootstrap over the supplied complete state, with unrelated account/storage records.
proc bootstrap(chapters: seq[StateEntry], credit = false): PreparedAccumulationInvocation =
  let queue = planAccumulationQueues([], newSeq[byte](12), newSeq[byte](12), HeaderSlot(0),
      queueConfig()).value
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(0), roundConfig().operands).value
  let transfers = if credit: @[DeferredTransfer(destination: ServiceIndex(42),
      amount: TransferBalance(7)),
    DeferredTransfer(destination: ServiceIndex(42), amount: TransferBalance(13))]
  else: @[] # Existing transfer-free witnesses keep their original metadata expectations.
  let inputs = prepareAccumulationInputs(operands, transfers, [AlwaysAccumulate(
      service: ServiceIndex(42))], roundConfig().inputs).value
  let raw = @[0'u8]
  let hash = array[32, byte](blake2b256(raw).value)
  var entries = @[serviceMetadataEntry(ServiceIndex(42), ServiceMetadata(codeHash: CodeHash(hash),
    balance: AccountBalance(99)), ByteLimit(ServiceMetadataBytes)).value,
    servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), raw,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value,
    serviceMetadataEntry(ServiceIndex(99), ServiceMetadata(balance: AccountBalance(123)), ByteLimit(
        ServiceMetadataBytes)).value,
    servicePreimageEntry(ServiceIndex(99), default(ServicePreimageHash), [9'u8, 8, 7],
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(3))).value]
  for entry in chapters: entries.add(entry) # Complete source retains every supplied component.
  let state = newStateStore(entries, limits()).value.snapshot.value
  let service = prepareAccumulationService(inputs, InvocationServiceIndex(0), state, HeaderSlot(128),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(0), preimageBytes: ByteLimit(1))).value
  prepareAccumulationInvocation(service, default(StateEntropyWord), ServiceProbeLimit(1)).value

## Incoming transfers credit both initial dimensions once, with matching copied self and complete account backing.
proc creditedContexts() =
  let invocation = bootstrap(components(), true)
  assert uint64(invocation.bootstrapInfo.value.inputs) == 2
  let prepared = prepareAccumulationContexts(invocation, contextConfig()).value
  # Both initial dimensions start at the same post-transfer I, with no outgoing effects.
  for dimension in [AccumulationDimension.Regular, AccumulationDimension.Exceptional]:
    let context = prepared.initialContext(dimension).value
    assert uint64(context.contextSelf.value.balance) == 119
    let account = context.contextAccounts.value.lookup(chapterServiceKey(StateChapter(255),
        ServiceIndex(42))).value
    assert uint64(decodeServiceMetadata(account.bytes, ByteLimit(
        ServiceMetadataBytes)).value.metadata.balance) == 119
    assert context.contextInfo.value.transfers == 0
    let prior = invocation.bootstrapService.value.servicePriorState.value.lookup(chapterServiceKey(
      StateChapter(255), ServiceIndex(42))).value
    assert uint64(decodeServiceMetadata(prior.bytes, ByteLimit(
        ServiceMetadataBytes)).value.metadata.balance) == 99

## Both I dimensions preserve exact metadata/children and source ownership after locals disappear.
proc checkPair(pair: PreparedAccumulationContexts, seed = 0) =
  let expected = components(seed)
  # Selecting either dimension must expose identical initial I and independently retained children.
  for dimension in [AccumulationDimension.Regular, AccumulationDimension.Exceptional]:
    let current = pair.initialContext(dimension).value
    let info = current.contextInfo.value
    assert uint32(info.service) == 42 and info.transfers == 0 and info.provisions == 0 and
        not info.hasYield
    assert uint32(info.nextService) == uint32(current.contextInvocation.value.bootstrapInfo.value.nextService)
    assert uint64(current.contextSelf.value.balance) == 99
    let state = current.contextAccounts.value
    assert uint64(decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255),
        ServiceIndex(99))).value.bytes,
      ByteLimit(ServiceMetadataBytes)).value.metadata.balance) == 123
    assert state.lookup(servicePreimageKey(ServiceIndex(99), default(ServicePreimageHash),
        ByteLimit(32)).value).value.bytes == @[9'u8, 8, 7]
    # Compare every ordered hash against independently patterned scalar expectations.
    for core in 0..<2:
      assert current.contextQueues.value.authorizerCount(AuthorizationCoreIndex(core)).value == 80
      for position in 0..<80:
        let hash = current.contextQueues.value.authorizerAt(AuthorizationCoreIndex(core),
            AuthorizationIndex(position)).value
        for i in 0..<32: assert hash.bytes[i] == byte((
            seed+core*80+position+i) mod 256) # No core or queue reordering.
    # Check all fixed validator fields, rather than merely comparing population counts.
    for index in 0..<6:
      let record = current.contextStaging.value.validatorAt(StateValidatorIndex(index)).value
      for i in 0..<32:
        assert array[32, byte](record.bandersnatch)[i] == byte((seed+index+i) mod 256) # Exact BS role.
        assert array[32, byte](record.ed25519)[i] == byte((seed+index+i+1) mod 256) # Exact Ed role.
      for i in 0..<144: assert array[144, byte](record.bls)[i] == byte((seed+index+i+2) mod 256) # Full BLS value.
      for i in 0..<128: assert array[128, byte](record.metadata)[i] == byte((
          seed+index+i+3) mod 256) # Full metadata value.
    let roles = current.contextPrivileges.value
    let facts = roles.privilegeInfo.value
    assert uint32(facts.manager) == 7 and uint32(facts.delegator) == 8 and uint32(
        facts.registrar) == 9
    assert facts.cores == 2 and facts.always == 1
    assert uint32(roles.privilegeAssignerAt(PrivilegeCoreIndex(0)).value) == 11
    assert uint32(roles.privilegeAssignerAt(PrivilegeCoreIndex(1)).value) == 12
    assert uint32(roles.alwaysAccumulateAt(PrivilegeEntryIndex(0)).value.service) == 42
    assert uint64(roles.alwaysAccumulateAt(PrivilegeEntryIndex(0)).value.gas) == 17
    # Whole chapter lookups preserve the exact serialized source, not reserialized substitutions.
    for entry in expected: assert state.lookup(entry.key).value.bytes == entry.value
    var edited = state.lookup(expected[0].key).value.bytes
    edited[0] = edited[0] xor 255
    assert state.lookup(expected[0].key).value.bytes == expected[0].value

## Exercise exact and one-below policies, complete consumption, malformed encodings and coherent profiles.
proc boundaries(): PreparedAccumulationContexts =
  let cfg = contextConfig()
  let ready = bootstrap(components())
  result = prepareAccumulationContexts(ready, cfg).value
  checkPair(result)
  assert prepareAccumulationContexts(default(PreparedAccumulationInvocation), cfg).error ==
      AccumulationContextError.InvalidInvocation
  # Each independently enforced byte/hash/record/dictionary ceiling must reject one-below capacity.
  for mode in 0..<8:
    var small = cfg
    case mode
    of 0: small.totalBytes = ByteLimit(7169) # Aggregate copies include all complete chapters.
    of 1: small.queues.maxBytes = ByteLimit(5119) # Queue bytes are fixed per core.
    of 2: small.queues.maxHashes = ElementLimit(159) # Hash traversal has an independent ceiling.
    of 3: small.staging.maxBytes = ByteLimit(2016) # Canonical count prefix is charged too.
    of 4: small.staging.validators = ElementLimit(5) # Record allocation is independently bounded.
    of 5: small.privileges.maxBytes = ByteLimit(32) # All role/allowance framing is charged.
    of 6: small.privileges.maxAlways = ElementLimit(0) # Nonempty map cannot bypass work policy.
    else: small.totalBytes = ByteLimit(0) # Empty aggregate policy never underflows subtraction.
    assert prepareAccumulationContexts(ready, small).error == AccumulationContextError.LimitExceeded
  # Every mandatory chapter rejects absence, truncation and trailing garbage, including the final decoder.
  for index in 0..<3:
    var missing: seq[StateEntry] = @[]
    let entries = components()
    for i in 0..<3:
      if i != index: missing.add(entries[i]) # Only the selected mandatory chapter is absent.
    assert prepareAccumulationContexts(bootstrap(missing), cfg).error ==
        AccumulationContextError.MissingState
    for suffix in [false, true]:
      var broken = components()
      if suffix: broken[index].value.add(0) # Valid prefix followed by garbage must not be accepted.
      else: broken[index].value.setLen(broken[index].value.len-1) # Last-byte truncation cannot publish earlier components.
      var loose = cfg
      loose.totalBytes = ByteLimit(10000)
      loose.queues.maxBytes = ByteLimit(10000)
      loose.staging.maxBytes = ByteLimit(10000)
      loose.privileges.maxBytes = ByteLimit(10000)
      assert prepareAccumulationContexts(bootstrap(broken), loose).error ==
          AccumulationContextError.MalformedState
  # Structurally different chain profiles are refused, not silently substituted.
  for mode in 0..<4:
    var wrong = cfg
    case mode
    of 0: wrong.staging.cores = CoreCount(3) # Inconsistent component core counts.
    of 1: wrong.privileges.cores = CoreCount(3) # Inconsistent assigner domain.
    of 2: wrong.validators = ValidatorCount(5) # Invalid GP population.
    else: wrong.queues.cores = CoreCount(0) # No supported chain profile.
    assert prepareAccumulationContexts(ready, wrong).error == AccumulationContextError.InvalidConfig
  var other = cfg
  other.queues.cores = CoreCount(3)
  other.staging.cores = CoreCount(3)
  other.privileges.cores = CoreCount(3)
  other.validators = ValidatorCount(9)
  other.queues.maxBytes = ByteLimit(10000)
  other.queues.maxHashes = ElementLimit(240)
  other.totalBytes = ByteLimit(10000)
  assert prepareAccumulationContexts(ready, other).error == AccumulationContextError.MalformedState
  # A valid six-record staging roster is independent of the coherent nine-active-validator profile.
  var mismatched = components()
  mismatched[0] = authorizationEntry(AuthorizationKind.Queues, @[newSeq[AuthorizerHash](80),
    newSeq[AuthorizerHash](80), newSeq[AuthorizerHash](80)], other.queues).value
  mismatched[2] = privilegeStateEntry(PrivilegeState(assigners: newSeq[ServiceIndex](3)),
    PrivilegeConfig(cores: CoreCount(3), maxBytes: ByteLimit(100), maxAlways: ElementLimit(1))).value
  let sixStaging = prepareAccumulationContexts(bootstrap(mismatched), other)
  assert sixStaging.error == AccumulationContextError.None
  assert sixStaging.value.initialContext(AccumulationDimension.Regular).value.contextStaging.value.validatorCount.value == 6
  # Conversely capture a nine-record successor while retaining the six-active-validator profile.
  var grown = other
  grown.validators = ValidatorCount(6)
  grown.staging.validators = ElementLimit(9)
  grown.staging.maxBytes = ByteLimit(3025)
  grown.totalBytes = ByteLimit(10730) # Exact 7680-byte queues, 3025-byte C(7), and 25-byte C(12).
  mismatched[1] = validatorEntry(ValidatorChapter.Staging, newSeq[StateValidator](9),
      grown.staging).value
  let invocation = bootstrap(mismatched)
  failHash(1)
  let nineStaging = prepareAccumulationContexts(invocation, grown)
  assert nineStaging.error == AccumulationContextError.None
  assert nineStaging.value.initialContext(AccumulationDimension.Regular).value.contextStaging.value.validatorCount.value == 9
  for kind in 0..<3:
    var short = grown
    case kind
    of 0: short.staging.validators = ElementLimit(
        8) # Count ceiling still applies independently of active population.
    of 1: short.staging.maxBytes = ByteLimit(3024) # Complete canonical C(7) byte ceiling.
    else: short.totalBytes = ByteLimit(10729) # Aggregate source capture remains independently bounded.
    assert prepareAccumulationContexts(invocation, short).error ==
        AccumulationContextError.LimitExceeded
  failHash(0) # Capture and every quota refusal perform no hashing, even with unequal valid populations.
  # Reject invalid/overlong roster counts even when the remaining fixed record bytes are present.
  for first in [0'u8, 5, 128]:
    var invalid = components()
    invalid[1].value[0] = first
    assert prepareAccumulationContexts(bootstrap(invalid), cfg).error ==
        AccumulationContextError.MalformedState
  let empty = default(InitialAccumulationContext)
  assert empty.contextInfo.error == AccumulationContextError.Uninitialized
  assert empty.contextSelf.error == AccumulationContextError.Uninitialized
  assert empty.contextInvocation.error == AccumulationContextError.Uninitialized
  assert empty.contextAccounts.error == AccumulationContextError.Uninitialized
  assert empty.contextQueues.error == AccumulationContextError.Uninitialized
  assert empty.contextStaging.error == AccumulationContextError.Uninitialized
  assert empty.contextPrivileges.error == AccumulationContextError.Uninitialized
  assert default(PreparedAccumulationContexts).initialContext(
      AccumulationDimension.Regular).error == AccumulationContextError.Uninitialized
  assert result.initialContext(cast[AccumulationDimension](2)).error ==
      AccumulationContextError.InvalidDimension
  assert default(BlockAccumulationContexts).contextProjection.error ==
      AccumulationContextError.Uninitialized
  assert default(BlockAccumulationContexts).contextBlockInvocation.error ==
      AccumulationContextError.Uninitialized
  assert prepareBlockAccumulationContexts(default(BlockAccumulationInvocation), cfg).error ==
      AccumulationContextError.InvalidInvocation
  failHash(1)
  assert prepareAccumulationContexts(ready, cfg).error == AccumulationContextError.None
  failHash(0)

## Genuine signed block provenance ties parent components and posterior-entropy bootstrap to the same service.
proc boundCase(base: OwnedReport): BlockAccumulationContexts =
  let raw = @[0'u8]
  let hash = array[32, byte](blake2b256(raw).value)
  let code = servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(hash), raw,
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value
  let entries = components(7)
  # The shared authored fixture already includes C(7), so only missing C(2)/C(12) are added.
  var signedOptions0 = signedBlockFixtureConfig()
  signedOptions0.withAvailable = true
  signedOptions0.extra = @[entries[0], entries[2], code]
  signedOptions0.accountCode = raw
  let context = authored(base, signedOptions0)
  let admitted = planBlockReports(context.staged, context.older, config()).value
  let queue = planBlockAccumulationQueue(admitted, queueConfig()).value
  let round = planBlockInitialAccumulation(queue, roundConfig()).value
  # A pure projection can supply transfers beside real report operands without claiming a later-round certificate.
  let mixedInputs = prepareAccumulationInputs(round.roundProjection.value.roundInputs.value.invocationOperands.value,
    [DeferredTransfer(destination: ServiceIndex(42), amount: TransferBalance(7))], [], roundConfig().inputs).value
  let mixedService = prepareAccumulationService(mixedInputs, InvocationServiceIndex(0),
      context.original.snapshot.value,
    HeaderSlot(2), AccumulationServiceConfig(codeLimit: ServiceCodeLimit(0),
        preimageBytes: ByteLimit(1))).value
  assert mixedService.serviceInfo.value.transfers == 1 and mixedService.serviceInfo.value.operands > 0
  assert mixedService.serviceInputAt(InvocationInputIndex(0)).value.kind ==
      AccumulationKind.Transfer
  assert mixedService.serviceInputAt(InvocationInputIndex(1)).value.kind == AccumulationKind.Operand
  let mixed = prepareAccumulationInvocation(mixedService, default(StateEntropyWord),
      ServiceProbeLimit(1)).value
  assert uint64(mixed.bootstrapInfo.value.inputs) == uint64(
      mixedService.serviceInfo.value.operands)+1
  let credited = prepareAccumulationContexts(mixed, contextConfig()).value.initialContext(
      AccumulationDimension.Exceptional).value
  let original = context.original.snapshot.value.lookup(chapterServiceKey(StateChapter(255),
      ServiceIndex(42))).value
  assert uint64(credited.contextSelf.value.balance) == uint64(decodeServiceMetadata(original.bytes,
      ByteLimit(ServiceMetadataBytes)).value.metadata.balance)+7
  let service = prepareBlockAccumulationService(round, InvocationServiceIndex(0),
    AccumulationServiceConfig(codeLimit: ServiceCodeLimit(0), preimageBytes: ByteLimit(1))).value
  let invocation = prepareBlockAccumulationInvocation(service, ServiceProbeLimit(1)).value
  result = prepareBlockAccumulationContexts(invocation, contextConfig()).value
  let initial = result.contextProjection.value.initialContext(AccumulationDimension.Regular).value
  let source = context.original.snapshot.value
  # Compare all partial-state components against the certified parent, including its actual staging keys.
  for chapter in [2, 7, 12]:
    let key = chapterKey(StateChapter(chapter))
    assert initial.contextAccounts.value.lookup(key).value.bytes == source.lookup(key).value.bytes
  assert array[32, byte](initial.contextAccounts.value.commitment.root) == array[32, byte](
      source.commitment.root)
  let expectedRoster = decodeStateValidators(source.lookup(chapterKey(StateChapter(7))).value.bytes,
    contextConfig().staging).value.value
  # Decoded projections must agree with the genuine source, not merely retain an unrelated map handle.
  for i in 0..<6:
    assert array[32, byte](initial.contextStaging.value.validatorAt(StateValidatorIndex(
        i)).value.bandersnatch) ==
      array[32, byte](expectedRoster.validatorAt(StateValidatorIndex(i)).value.bandersnatch)
  assert initial.contextQueues.value.authorizerAt(AuthorizationCoreIndex(0), AuthorizationIndex(
      0)).value.bytes[0] == 7
  assert uint32(initial.contextPrivileges.value.privilegeInfo.value.manager) == 7
  assert initial.contextInvocation.value.bootstrapArguments.value == @[2'u8, 42, 1]
  assert result.contextBlockInvocation.value.bootstrapProjection.value.bootstrapInfo.error ==
      AccumulationInvocationError.None
  var replacement = context.original
  discard replacement.apply([StateWrite(key: chapterKey(StateChapter(2)), kind: StateWriteKind.Put,
    value: @[255'u8])]).value # A separately published map cannot mutate this retained initial state.
  assert array[32, byte](initial.contextAccounts.value.commitment.root) == array[32, byte](
      source.commitment.root)
  assert initial.contextAccounts.value.lookup(chapterKey(StateChapter(2))).value.bytes == entries[0].value
  assert initial.contextQueues.value.authorizerAt(AuthorizationCoreIndex(0), AuthorizationIndex(
      0)).value.bytes[0] == 7
  var wrong = contextConfig()
  wrong.validators = ValidatorCount(9)
  assert prepareBlockAccumulationContexts(invocation, wrong).error ==
      AccumulationContextError.InvalidConfig
  wrong = contextConfig()
  wrong.queues.cores = CoreCount(3)
  assert prepareBlockAccumulationContexts(invocation, wrong).error ==
      AccumulationContextError.InvalidConfig

## Repeated complete and refused initialization releases all immutable component storage.
proc lifetime() =
  let ready = bootstrap(components())
  let cfg = contextConfig()
  var refused = cfg
  refused.privileges.maxAlways = ElementLimit(0)
  discard prepareAccumulationContexts(ready, cfg)
  discard prepareAccumulationContexts(ready, refused)
  let before = getOccupiedMem()
  # The late dictionary refusal must release both already-decoded owners too.
  for i in 0..<1000:
    assert prepareAccumulationContexts(ready, cfg).error == AccumulationContextError.None
    assert prepareAccumulationContexts(ready, refused).error ==
        AccumulationContextError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_context", 1000, before, after)

## Run authored complete-state cases and retain every child after source locals leave scope.
proc main() {.raises.} =
  creditedContexts()
  let retained = boundaries()
  checkPair(retained)
  # Deterministic patterned cases test complete field contents without another production-language oracle.
  for seed in 0..<32: checkPair(prepareAccumulationContexts(bootstrap(components(seed)),
      contextConfig()).value, seed)
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i]) # Preserve exact binary fixture contents.
  let bound = boundCase(decodeOwnedReport(bytes, 2).value)
  assert bound.contextProjection.value.initialContext(
      AccumulationDimension.Exceptional).value.contextStaging.value.validatorCount.value == 6
  lifetime()
  echo "PASS accumulation contexts: complete initial state, paired dimensions, provenance and ARC"
try:
  main() # Execute the entire suite through Hastur.
except:
  quit(2) # Missing fixtures and unexpected exceptions remain failures.
