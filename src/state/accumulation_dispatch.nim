# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute a prepared accumulation CPU with its own fetch environment and implemented host calls.
## Guarded results separate guest outcomes, engine refusals and unavailable host functionality.
## Retains storage/checkpoint/yield/provide implications beside guest outcomes.
## Outcome normalization and state publication are separate operations.

import ../chain/parameters
import ../pvm/[machine, step, gas, host_gas, host_fetch]
import ../codec/[state_outputs, composite, state_layout, state_accounts, state_service_values, bounded]
import ./[accumulation_machine, accumulation_fetch, accumulation_context, accumulation_effects, store]

type
  AccumulationDispatchError* {.pure.} = enum ## Local preparation/host refusals never impersonate guest panic, NONE or WHAT.
    Uninitialized, None, InvalidMachine, InvalidParameters, LimitExceeded, InvalidContext,
    UnsupportedHostCall, ExecutionFailure, MalformedState, BackendFailure, GasRangeExceeded
  AccumulationDispatchResult* = object ## Success alone retains a CPU outcome; engine failure carries only its enum-valued reason.
    case status: AccumulationDispatchError
    of None:
      completed: StepOutcome                # Immutable successor; no reference back to this result.
      completedEffects: AccumulationEffects # Both dimensions belong to this exact execution.
    of ExecutionFailure:
      reason: StepError                     # No partial machine or progress is exposed on refusal.
    else:
      discard                               # Other failures contain only the outer reason.
  ## Callback-local immutable fetch ownership cannot be substituted by the guest or caller.
  DispatchContext = object
    parameters: Parameters
    fetch: FetchContext
    copyLimit: MemoryByteLimit
    effects: AccumulationEffects
    provisionLimits: AccumulationProvisionLimits

func error*(outcome: AccumulationDispatchResult): AccumulationDispatchError =
  ## Inspect the selected alternative without granting mutable access to its discriminator.
  outcome.status
func value*(outcome: AccumulationDispatchResult): StepOutcome {.inline,
    requires: outcome.status == AccumulationDispatchError.None.} =
  ## Retain a completed guest outcome independently of all preparation handles.
  outcome.completed
func effects*(outcome: AccumulationDispatchResult): AccumulationEffects {.inline,
    requires: outcome.status == AccumulationDispatchError.None.} =
  ## Retain both current implication dimensions only after complete guest execution succeeds.
  ## A guest panic/OOG is a completed outcome; local engine/host refusals expose neither dimension.
  outcome.completedEffects
func executionError*(outcome: AccumulationDispatchResult): StepError {.inline,
    requires: outcome.status == AccumulationDispatchError.ExecutionFailure.} =
  ## Inspect the original execution-budget or instruction refusal without a fabricated guest result.
  outcome.reason

## Charge checkpoint/yield before reading memory or changing implications; debt preserves exact magnitude.
## Effects are callback-local immutable versions, discarded if later execution refuses locally.
proc effectResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory,
    checkpoint: bool): HostResult[AccumulationDispatchError] {.raises: [].} =
  let cost = (if checkpoint: 103'u64 else: 98'u64) # GP definitions.tex M_C and M_Taurus.
  let available = uint64(cpu.gas)
  var response = HostResponse(action: HostAction.Continue, gas: MachineGas(0),
    gasDeficit: GasDeficit(0), registers: cpu.registers, memory: memory)
  if available < cost:
    # General affordability failure precedes all row-specific mutations, including checkpoint's assignment.
    response.action = HostAction.OutOfGas
    response.gasDeficit = GasDeficit(cost-available)
    return hostSuccess[AccumulationDispatchError](response)
  response.gas = MachineGas(available-cost)
  if checkpoint:
    # Y'=X retains the complete supported current context; r7 reports post-charge gas.
    let changed = checkpointAccumulationEffects(context.effects)
    if changed.error != AccumulationEffectError.None:
      return hostFailure(AccumulationDispatchError.InvalidContext) # No fabricated implication owner.
    context.effects = changed.value
    response.registers[7] = RegisterValue(available-cost)
  else:
    # Yield reads a natural 32-byte guest interval; full-width pointers never wrap into accessible RAM.
    let copied = readBytes(memory, MemoryAddress(uint64(cpu.registers[7])), MemoryLength(32),
      context.copyLimit)
    case copied.error
    of MachineError.None:
      var bytes = default(array[32, byte])
      for i in 0..<32:
        bytes[i] = copied.value[i] # A complete successful read supplies every commitment byte.
      let changed = recordAccumulationYield(context.effects, OutputCommitment(bytes))
      if changed.error != AccumulationEffectError.None:
        return hostFailure(AccumulationDispatchError.InvalidContext) # No partial effect publication.
      context.effects = changed.value
      response.registers[7] = RegisterValue(0) # OK, including an all-zero present commitment.
    of MachineError.Fault, MachineError.InvalidRange:
      response.action = HostAction.Panic # Charged panic preserves r7 and both implication versions.
    of MachineError.LimitExceeded:
      return hostFailure(AccumulationDispatchError.LimitExceeded) # Local copy policy is not guest panic.
    else:
      return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory is a local invariant refusal.
  hostSuccess[AccumulationDispatchError](response)

## Subtract a complete two-limb host cost without overflow or loss of negative gas magnitude.
proc chargedResponse(cpu: MachineInfo, memory: Memory, low, upper: uint64):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let available = uint64(cpu.gas)
  var response = HostResponse(action: HostAction.Continue, gas: MachineGas(0),
    gasDeficit: GasDeficit(0), registers: cpu.registers, memory: memory)
  if upper == 0 and available >= low:
    response.gas = MachineGas(available-low) # A funded cost is representable and subtraction cannot underflow.
    return hostSuccess[AccumulationDispatchError](response)
  var debtHigh = upper
  var debtLow = 0'u64
  if low >= available:
    debtLow = low-available # No low-limb borrow; upper cost limbs remain unchanged.
  else:
    # Underfunding with a smaller low limb implies upper>0, so borrowing one upper unit is valid.
    debtHigh = upper-1
    debtLow = high(uint64)-available+low+1 # available>low proves each addition remains representable.
  if debtHigh != 0 or debtLow > 0x8000000000000000'u64:
    return hostFailure(AccumulationDispatchError.GasRangeExceeded) # Preserve the signed-gas gate, never clamp debt.
  response.action = HostAction.OutOfGas
  response.gasDeficit = GasDeficit(debtLow)
  hostSuccess[AccumulationDispatchError](response)

## Compute the full 66-bit provide cost using bounded base-2^32 limbs, then subtract gas exactly.
## Only debt outside the machine's existing signed-negative domain is a local representation refusal.
proc provideCharge(cpu: MachineInfo, memory: Memory): HostResult[
    AccumulationDispatchError] {.raises: [].} =
  let size = uint64(cpu.registers[9])
  let units = size div 1024
  let tail = 3980'u64 + ((size mod 1024)*2264+1023) div 1024
  let lowProduct = (units and 0xffffffff'u64)*2264+tail # Below 2^44+6244, proven before multiplication.
  let highProduct = (units shr 32)*2264+(lowProduct shr 32) # Below 2^35; includes the low-limb carry.
  let low = ((highProduct and 0xffffffff'u64) shl 32) or (lowProduct and 0xffffffff'u64)
  let upper = highProduct shr 32 # Complete cost is upper*2^64+low, with upper at most two.
  chargedResponse(cpu, memory, low, upper)

## Read and retain requested preimage bytes under the exact provide-row ordering after affordability.
## Neither protocol refusal nor local failure changes the callback's prior effect pair.
proc provideResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let charged = provideCharge(cpu, memory)
  if charged.kind != HostResultKind.Response:
    return charged # A representation refusal has no response or partially charged CPU.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # Affordability precedes length, guest memory, target lookup and local copy policy.
  let size = uint64(cpu.registers[9])
  if size > uint64(high(uint32)):
    response.registers[7] = RegisterValue(high(uint64)-8) # Invalid protocol length is HUH before any memory read.
    return hostSuccess[AccumulationDispatchError](response)
  let copied = readBytes(memory, MemoryAddress(uint64(cpu.registers[8])), MemoryLength(size),
    MemoryByteLimit(min(uint64(context.copyLimit), uint64(context.provisionLimits.perBlob))))
  case copied.error
  of MachineError.None:
    discard # A successful preflight owns the complete borrowed guest interval, including an empty interval.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # Charged panic precedes even an unknown target; r7 is unchanged.
    return hostSuccess[AccumulationDispatchError](response)
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Local policy cannot masquerade as a protocol code.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory owners are local invariants.
  let rawTarget = uint64(cpu.registers[7])
  var target = ServiceIndex(0)
  if rawTarget == high(uint64):
    target = context.effects.effectContext(AccumulationDimension.Regular).value.effectInfo.value.service # Exact self sentinel.
  elif rawTarget <= uint64(high(uint32)):
    target = ServiceIndex(uint32(rawTarget)) # Full-width validation precedes nominal uint32 conversion.
  else:
    response.registers[7] = RegisterValue(high(uint64)-3) # Out-of-domain service cannot alias its low bits.
    return hostSuccess[AccumulationDispatchError](response)
  let retained = recordAccumulationProvision(context.effects, target, copied.value,
      context.provisionLimits)
  case retained.error
  of AccumulationEffectError.None:
    context.effects = retained.value # Only complete success publishes the new immutable regular version.
    response.registers[7] = RegisterValue(0) # OK; account/preimage storage remains unchanged.
  of AccumulationEffectError.UnknownService:
    response.registers[7] = RegisterValue(high(uint64)-3) # WHO, after memory accessibility was established.
  of AccumulationEffectError.NotRequested, AccumulationEffectError.AlreadyProvided,
      AccumulationEffectError.InvalidLength:
    response.registers[7] = RegisterValue(high(uint64)-8) # HUH, retaining both prior dimensions.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # No partial capture or machine escapes local refusal.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # Failed hashes never become unrequested verdicts.
  of AccumulationEffectError.MalformedState:
    return hostFailure(AccumulationDispatchError.MalformedState) # Corrupt metadata/history remains an explicit local refusal.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Corrupt account/request state is not WHO or HUH.
  hostSuccess[AccumulationDispatchError](response)

## Compute both independently rounded read/write terms in bounded base-2^32 limbs.
## The key rate exceeds 1024, so a full-width cost must retain its upper limb.
proc storageCharge(cpu: MachineInfo, memory: Memory, writing: bool): HostResult[
    AccumulationDispatchError] {.raises: [].} =
  let size = uint64(cpu.registers[if writing: 8 else: 9])
  let requested = uint64(cpu.registers[if writing: 10 else: 12])
  let keyRate = (if writing: 3358'u64 else: 1736'u64)
  let valueRate = (if writing: 216'u64 else: 248'u64)
  let base = (if writing: 2442'u64 else: 2407'u64)
  let units = size div 1024
  let valueCost = (requested div 1024)*valueRate+((requested mod 1024)*valueRate+1023) div 1024
  let tail = base+((size mod 1024)*keyRate+1023) div 1024
  let lowProduct = (units and 0xffffffff'u64)*keyRate+tail+(valueCost and 0xffffffff'u64)
  # Each product is below 2^44; adding the bounded low value limb and base cannot overflow uint64.
  let highProduct = (units shr 32)*keyRate+(lowProduct shr 32)+(valueCost shr 32)
  # The complete high product is below 2^34, including both carries; retain all bits above uint64.
  let low = ((highProduct and 0xffffffff'u64) shl 32) or (lowProduct and 0xffffffff'u64)
  chargedResponse(cpu, memory, low, highProduct shr 32)

## Apply Omega_L/Omega_R to current accounts with captured keys and bounded, atomic suffix writes.
## Lookup fixes the hash extent at 32; read bounds its variable raw key independently of the output.
proc accountReadResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory,
    storage: bool):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let requested = uint64(cpu.registers[if storage: 12 else: 11])
  var charged = hostFailure(AccumulationDispatchError.Uninitialized)
  if storage:
    charged = storageCharge(cpu, memory, false) # Both full-width read extents contribute before accessibility checks.
  else:
    # Lookup's rate<1024 proves the full cost fits below 2^63 for every uint64 request.
    let cost = 600'u64+(requested div 1024)*248+((requested mod 1024)*248+1023) div 1024
    charged = chargedResponse(cpu, memory, cost, 0)
  if charged.kind != HostResultKind.Response:
    return charged # No partial response on unrepresentable signed debt.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # Affordability precedes key reads, target selection and local copy policy.
  let keyLength = (if storage: uint64(cpu.registers[9]) else: 32'u64)
  let keyLimit = (if storage: context.copyLimit else: MemoryByteLimit(32))
  let keyBytes = readBytes(memory, MemoryAddress(uint64(cpu.registers[8])),
      MemoryLength(keyLength), keyLimit)
  case keyBytes.error
  of MachineError.None:
    discard # Capture the entire key before an overlapping guest write.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # A bad key pointer takes precedence over an absent account.
    return hostSuccess[AccumulationDispatchError](response)
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Variable key policy is a local refusal.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory owners cannot fabricate absence.
  let initial = context.effects.effectContext(AccumulationDimension.Regular).value.effectInitialContext.value
  let self = initial.contextInfo.value.service
  let rawTarget = uint64(cpu.registers[7])
  var target = self
  if rawTarget != high(uint64):
    if rawTarget > uint64(high(uint32)):
      response.registers[7] = RegisterValue(high(uint64)) # NONE; an out-of-domain service cannot alias its low bits.
      return hostSuccess[AccumulationDispatchError](response)
    target = ServiceIndex(uint32(rawTarget)) # An explicit self ID follows the same current complete-map backing.
  let state = context.effects.effectContext(AccumulationDimension.Regular).value.effectAccounts.value
  let account = state.lookup(chapterServiceKey(StateChapter(255), target))
  if account.error == StateStoreError.MissingKey:
    response.registers[7] = RegisterValue(high(uint64)) # NONE has zero cardinality; the output interval is empty.
    return hostSuccess[AccumulationDispatchError](response)
  if account.error != StateStoreError.None:
    return hostFailure(AccumulationDispatchError.InvalidContext) # No invalid map may fabricate absence.
  if account.value.byteLength != ServiceMetadataBytes:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Prove the fixed account extent before its copy.
  if decodeServiceMetadata(account.value.bytes, ByteLimit(ServiceMetadataBytes)).error !=
      ServiceMetadataError.None:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Malformed metadata is never an absent account.
  var key = default(ServiceValueResult[StateKey])
  if storage:
    # Read uses the raw storage namespace with its fixed prefix excluded from the logical key ceiling.
    key = serviceStorageKey(target, keyBytes.value, ByteLimit(uint64(context.copyLimit)))
  else:
    # Lookup retains its fixed 32-byte identity and distinct preimage namespace.
    var hash = default(array[32, byte])
    for i in 0..<32:
      hash[i] = keyBytes.value[i] # Lookup identities remain raw supplied hashes.
    key = servicePreimageKey(target, ServicePreimageHash(hash), ByteLimit(32))
  if key.error != ServiceValueError.None:
    return hostFailure(AccumulationDispatchError.BackendFailure) # Canonical namespace derivation cannot fall back to another key.
  let found = state.lookup(key.value)
  if found.error == StateStoreError.MissingKey:
    response.registers[7] = RegisterValue(high(uint64)) # Missing and present-empty remain different protocol values.
    return hostSuccess[AccumulationDispatchError](response)
  if found.error != StateStoreError.None:
    return hostFailure(AccumulationDispatchError.InvalidContext) # No partial lookup owner escapes a corrupt map.
  let size = uint64(found.value.byteLength)
  let offset = min(uint64(cpu.registers[if storage: 11 else: 10]), size)
  let length = min(requested, size-offset) # Subtraction is proved by the clipped offset, before any additions/narrowing.
  let copied = found.value.copySlice(offset, length, ByteLimit(uint64(context.copyLimit)))
  if copied.error == StateStoreError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Bound only the selected bytes, independent of full value length.
  if copied.error != StateStoreError.None:
    return hostFailure(AccumulationDispatchError.InvalidContext) # The checked owner/range must authorize the complete slice.
  let written = writeBytes(memory, MemoryAddress(uint64(cpu.registers[if storage: 10 else: 9])),
      copied.value, context.copyLimit)
  case written.error
  of MachineError.None:
    response.memory = written.value # Every page was preflighted before publishing the immutable memory successor.
    response.registers[7] = RegisterValue(size)
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # Preserve all bytes/r7 when any effective output byte is unwritable.
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # A local bound is not a guest panic or NONE.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory ownership cannot become a protocol response.
  hostSuccess[AccumulationDispatchError](response)

## Charge and capture write inputs before planning any private account change.
proc writeResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let charged = storageCharge(cpu, memory, true)
  if charged.kind != HostResultKind.Response:
    return charged # Preserve unrepresentable signed debt as a local refusal.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # No memory checks or storage hashing before affordability.
  let key = readBytes(memory, MemoryAddress(uint64(cpu.registers[7])),
    MemoryLength(uint64(cpu.registers[8])), context.copyLimit)
  if key.error in {MachineError.Fault, MachineError.InvalidRange}:
    response.action = HostAction.Panic # Charged panic preserves r7 and all prior account versions.
    return hostSuccess[AccumulationDispatchError](response)
  if key.error == MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Local capture budget is not guest panic.
  if key.error != MachineError.None:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Require authentic readable memory.
  let value = readBytes(memory, MemoryAddress(uint64(cpu.registers[9])),
    MemoryLength(uint64(cpu.registers[10])), context.copyLimit)
  if value.error in {MachineError.Fault, MachineError.InvalidRange}:
    response.action = HostAction.Panic # Zero length accepts every pointer; nonempty invalid ranges panic.
    return hostSuccess[AccumulationDispatchError](response)
  if value.error == MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # No state change on partial capture.
  if value.error != MachineError.None:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid owners never authorize state writes.
  let changed = recordAccumulationStorage(context.effects, key.value, value.value,
    context.parameters, ByteLimit(uint64(context.copyLimit)))
  case changed.error
  of AccumulationEffectError.None:
    context.effects = changed.value.effects # Publish only a complete metadata/storage successor.
    response.registers[7] = RegisterValue(if changed.value.hadValue:
      uint64(changed.value.previousBytes) else: high(uint64))
  of AccumulationEffectError.StorageFull:
    response.registers[7] = RegisterValue(high(uint64)-4) # FULL preserves the prior pair.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Store ceilings remain local refusals.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # No partial state on failed hashing.
  of AccumulationEffectError.MalformedState:
    return hostFailure(AccumulationDispatchError.MalformedState) # Corrupt footprint/metadata never becomes FULL.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid domains expose no successor.
  hostSuccess[AccumulationDispatchError](response)

## The execution engine calls this private handler only for validated ecalli suspensions.
proc dispatch(context: var DispatchContext, stopped: StepOutcome): HostResult[
    AccumulationDispatchError] {.raises: [].} =
  let cpu = machineInfo(stopped.machine).value
  let memory = memoryOf(stopped.machine).value
  case uint64(stopped.hostCall)
  of 0:
    # GP general gas call reports the credit after its own charge.
    hostSuccess[AccumulationDispatchError](gasHostResponse(cpu.gas, cpu.registers, memory))
  of 2:
    # All fetch sources were captured from this invocation before execution began.
    let fetched = fetchContextResponse(context.fetch, cpu.gas, cpu.registers, memory,
      context.copyLimit)
    case fetched.error
    of FetchError.None:
      hostSuccess[AccumulationDispatchError](fetched.value) # Includes charged panic and gas exhaustion.
    of FetchError.LimitExceeded:
      hostFailure(AccumulationDispatchError.LimitExceeded) # Local copy policy is not guest failure.
    else:
      hostFailure(AccumulationDispatchError.InvalidContext) # Never fabricate protocol absence.
  of 3:
    accountReadResponse(context, cpu, memory, false) # Account preimages remain separate from deferred provide effects.
  of 4:
    accountReadResponse(context, cpu, memory, true) # Storage keys use the distinct canonical raw-key namespace.
  of 5:
    writeResponse(context, cpu, memory) # Self-only storage changes retain private implication versions.
  of 18, 26:
    effectResponse(context, cpu, memory, uint64(stopped.hostCall) == 18) # Exact accumulation-only IDs.
  of 27:
    provideResponse(context, cpu, memory) # Requested provisions belong only to accumulation.
  of 1, 6, 15..17, 19..25:
    # These calls belong to accumulation's F but are not implemented by this adapter yet.
    hostFailure(AccumulationDispatchError.UnsupportedHostCall)
  else:
    # Refine-only IDs 7..14 and all other full-width IDs take accumulation's unknown branch.
    hostSuccess[AccumulationDispatchError](unknownHostResponse(cpu.gas, cpu.registers, memory))

proc executeAccumulationMachine*(prepared: PreparedAccumulationMachine, parameters: Parameters,
    fetchLimits: FetchAccumulationLimits, copyLimit: MemoryByteLimit,
    steps: ExecutionStepLimit, calls: HostCallLimit,
    cycles: GasCycleLimit, contextConfig: AccumulationContextConfig,
    provisionLimits = default(AccumulationProvisionLimits)): AccumulationDispatchResult =
  ## Execute only the supplied prepared machine, with entropy and inputs derived from its bootstrap.
  ## Capture limits apply before execution; copy, provision and engine budgets are independent local policies.
  ## Omitted provision limits give zero retained capacity; no default authorizes unbounded capture.
  ## Each call prepares I from this machine's own bootstrap and starts from its immutable initial CPU.
  ## No caller-supplied replacement effects, persistent writes or partial results escape.
  let captured = machineFetchContext(prepared, parameters, fetchLimits)
  case captured.error
  of InvocationFetchError.None:
    discard # Successful capture also proves the machine and invocation owners are initialized.
  of InvocationFetchError.InvalidMachine:
    # No default owner may authorize a synthetic invocation.
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidMachine)
  of InvocationFetchError.InvalidParameters:
    # Configuration must be valid before any guest instruction runs.
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidParameters)
  of InvocationFetchError.LimitExceeded:
    # Pre-execution capture policy remains a local refusal.
    return AccumulationDispatchResult(status: AccumulationDispatchError.LimitExceeded)
  else:
    # Failed input encoding or context construction exposes no partial environment.
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidContext)
  let initial = prepareAccumulationContexts(prepared.machineBootstrap.value, contextConfig)
  if initial.error == AccumulationContextError.LimitExceeded:
    return AccumulationDispatchResult(status: AccumulationDispatchError.LimitExceeded) # Bound chapter copies.
  if initial.error != AccumulationContextError.None:
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidContext) # Require exact initial I.
  let initialized = prepareAccumulationEffects(initial.value)
  if initialized.error != AccumulationEffectError.None:
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidContext) # No partial pair.
  var context = DispatchContext(parameters: parameters, fetch: captured.value, copyLimit: copyLimit,
      effects: initialized.value, provisionLimits: provisionLimits)
  let evaluated = executeWithHost(prepared.accumulationMachine.value, context, dispatch,
    steps, calls, cycles)
  case evaluated.error
  of HostExecutionError.None:
    # Preserve halt, panic, fault and gas outcomes without inventing a Psi_A transition.
    AccumulationDispatchResult(status: AccumulationDispatchError.None, completed: evaluated.value,
      completedEffects: context.effects)
  of HostExecutionError.ExecutionFailure:
    # Keep exact engine refusal, including separate step, host-call and gas-analysis budgets.
    AccumulationDispatchResult(status: AccumulationDispatchError.ExecutionFailure,
      reason: evaluated.executionError)
  of HostExecutionError.HostFailure:
    AccumulationDispatchResult(status: evaluated.hostError) # Failed callbacks publish no successor.
  else:
    AccumulationDispatchResult(status: AccumulationDispatchError.InvalidContext) # No default success.
