# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute a prepared accumulation CPU with its own fetch environment and implemented host calls.
## Guarded results separate guest outcomes, engine refusals and unavailable host functionality.
## Retains storage/queue/staging/privilege/checkpoint/yield/provide implications beside guest outcomes.
## Outcome normalization and state publication are separate operations.

import ../chain/parameters
import ../pvm/[machine, step, gas, host_gas, host_fetch]
import ../codec/[state_outputs, composite, state_layout, state_accounts, state_service_values,
    state_requests, state_privileges, state_authorization, work_report, state_safrole, assurances,
    c2_records, bounded]
import ./[accumulation_machine, accumulation_fetch, accumulation_context, accumulation_effects,
    accumulation_invocation, store]

type
  AccumulationDispatchError* {.pure.} = enum ## Local preparation/host refusals never impersonate guest panic, NONE or WHAT.
    Uninitialized, None, InvalidMachine, InvalidParameters, LimitExceeded, InvalidContext,
    UnsupportedHostCall, ExecutionFailure, MalformedState, BackendFailure, GasRangeExceeded,
    AmbiguousPrivileges ## Conflicting allowance values for one service require a specification decision.
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
    staging: ValidatorStateConfig
    queues: AuthorizationConfig
    privileges: PrivilegeConfig
    fetch: FetchContext
    copyLimit: MemoryByteLimit
    effects: AccumulationEffects
    provisionLimits: AccumulationProvisionLimits
    transferLimit: ElementLimit
    serviceProbes: ServiceProbeLimit

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

## Charge account info before lookup, then publish only the clipped atomic guest-memory write.
proc infoResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  var response = chargedResponse(cpu, memory, 703, 0).value # Fixed cost always has representable debt.
  if response.action == HostAction.OutOfGas:
    return hostSuccess[AccumulationDispatchError](response) # No lookup or memory work before affordability.
  let current = context.effects.effectContext(AccumulationDimension.Regular).value
  let raw = uint64(cpu.registers[7])
  var target = current.effectInfo.value.service
  if raw != high(uint64):
    if raw > uint64(high(uint32)):
      response.registers[7] = RegisterValue(high(uint64)) # Full-width absent target cannot alias low service bits.
      return hostSuccess[AccumulationDispatchError](response)
    target = ServiceIndex(uint32(raw)) # Validate the complete domain before narrowing.
  let encoded = current.effectAccountInfo(target, context.parameters)
  case encoded.error
  of AccumulationEffectError.None:
    discard # The fixed complete record is owned by value, independently of the account map.
  of AccumulationEffectError.UnknownService:
    response.registers[7] = RegisterValue(high(uint64)) # NONE has an empty output interval, valid at every pointer.
    return hostSuccess[AccumulationDispatchError](response)
  of AccumulationEffectError.MalformedState:
    return hostFailure(AccumulationDispatchError.MalformedState) # No truncated or saturated dependent fields.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid private owners expose no partial execution.
  let first = min(uint64(cpu.registers[9]), uint64(AccumulationAccountInfoBytes))
  let count = min(uint64(cpu.registers[10]), uint64(AccumulationAccountInfoBytes)-first)
  if count > uint64(context.copyLimit):
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Policy bounds the selected bytes, not the fixed record size.
  var slice = newSeq[byte](int(count)) # count<=96 proves native extent and every subsequent index.
  let bytes = encoded.value
  for i in 0..<slice.len:
    slice[i] = bytes[int(first)+i] # Clip before addition; no full-width offset narrowing can wrap.
  let written = writeBytes(memory, MemoryAddress(uint64(cpu.registers[8])), slice,
      context.copyLimit)
  case written.error
  of MachineError.None:
    response.memory = written.value # All effective pages were writable before any successor was published.
    response.registers[7] = RegisterValue(AccumulationAccountInfoBytes)
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # Preserve r7 and all guest bytes on any inaccessible output byte.
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Local budget is never guest panic.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid owners cannot authorize a fabricated write.
  hostSuccess[AccumulationDispatchError](response)

# Decode a completely captured fixed E4/E8 guest field without narrowing high role bits.
func privilegeNumber(bytes: seq[byte], offset, width: int): uint64 =
  result = 0
  for i in 0..<width:
    result = result or (uint64(bytes[offset+i]) shl (8*i)) # Callers prove each complete four/eight-byte field.

# Charge bless's complete 69-bit item cost before memory, authorization and role validation.
proc blessResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let count = uint64(cpu.registers[12])
  let lowProduct = (count and 0xffffffff'u64)*20+422 # Below 2^37; retain its carry into the upper product.
  let highProduct = (count shr 32)*20+(lowProduct shr 32) # Below 2^37, preserving the complete item charge.
  let low = ((highProduct and 0xffffffff'u64) shl 32) or (lowProduct and 0xffffffff'u64)
  let charged = chargedResponse(cpu, memory, low, highProduct shr 32)
  if charged.kind != HostResultKind.Response:
    return charged # Unrepresentable signed debt remains a local refusal.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # No input capture or manager lookup before affordability.
  let cores = context.parameters.get(coreCount)
  if cores != uint64(context.privileges.cores):
    return hostFailure(AccumulationDispatchError.InvalidContext) # Protocol core count must match prepared privilege layout.
  let assigners = readBytes(memory, MemoryAddress(uint64(cpu.registers[8])), MemoryLength(4*cores),
      context.copyLimit)
  case assigners.error
  of MachineError.None:
    discard # The complete positional core array is captured before authorization.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # Invalid core-array memory precedes HUH and WHO.
    return hostSuccess[AccumulationDispatchError](response)
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Local capture bounds are not guest codes.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # No invalid memory owner authorizes roles.
  if count > uint64(context.privileges.maxAlways) or count > uint64(high(int) div sizeof(
      AlwaysAccumulate)):
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Bound input record work before reading/sorting.
  # Funded 422+20*count<=UINT64_MAX proves 12*count fits uint64 before forming the guest byte extent.
  let pairs = readBytes(memory, MemoryAddress(uint64(cpu.registers[11])), MemoryLength(12*count),
      context.copyLimit)
  case pairs.error
  of MachineError.None:
    discard # All record bytes are captured before authority or role-domain checks.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # Empty record arrays accept every pointer, including UINT64_MAX.
    return hostSuccess[AccumulationDispatchError](response)
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # No partial execution on capture policy failure.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # No fabricated successful input.
  let current = context.effects.effectContext(AccumulationDimension.Regular).value
  if uint32(current.effectInfo.value.service) != uint32(
      current.effectPrivileges.value.privilegeInfo.value.manager):
    response.registers[7] = RegisterValue(high(uint64)-8) # HUH precedes all proposed role-domain checks.
    return hostSuccess[AccumulationDispatchError](response)
  for index in [7, 9, 10]:
    if uint64(cpu.registers[index]) > uint64(high(uint32)):
      response.registers[7] = RegisterValue(high(uint64)-3) # WHO; no self sentinel or low-bit truncation exists here.
      return hostSuccess[AccumulationDispatchError](response)
  var roles = PrivilegeState(manager: ServiceIndex(uint32(uint64(cpu.registers[7]))),
    delegator: ServiceIndex(uint32(uint64(cpu.registers[9]))), registrar: ServiceIndex(uint32(
        uint64(cpu.registers[10]))),
    assigners: newSeq[ServiceIndex](int(cores)), always: newSeq[AlwaysAccumulate](int(count)))
  for i in 0..<roles.assigners.len:
    roles.assigners[i] = ServiceIndex(uint32(privilegeNumber(assigners.value, i*4, 4))) # Complete E4 domain.
  for i in 0..<roles.always.len:
    roles.always[i] = AlwaysAccumulate(service: ServiceIndex(uint32(privilegeNumber(pairs.value,
        i*12, 4))),
      gas: PrivilegeGas(privilegeNumber(pairs.value, i*12+4,
          8))) # Proven captured extents bound every field index.
  let changed = recordAccumulationBless(context.effects, roles, context.privileges)
  case changed.error
  of AccumulationEffectError.None:
    context.effects = changed.value # Both typed roles and serialized C(12) become one immutable successor.
    response.registers[7] = RegisterValue(0) # OK, including handoff to another manager.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # No fabricated protocol resource code.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # No partial roles on failed Merklization.
  of AccumulationEffectError.AmbiguousPrivileges:
    return hostFailure(AccumulationDispatchError.AmbiguousPrivileges) # Preserve the conflicting-dictionary specification gate.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # No inconsistent state/authority may publish.
  hostSuccess[AccumulationDispatchError](response)

# Assign captures its entire ordered queue before core, authority and proposed-ID checks.
proc assignResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let charged = chargedResponse(cpu, memory, 1818, 0)
  if charged.kind != HostResultKind.Response:
    return charged # Preserve the general charge helper's explicit representation refusal.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # Affordability precedes all input and state work.
  if context.parameters.get(coreCount) != uint64(context.queues.cores) or
      context.parameters.get(coreCount) != uint64(context.privileges.cores) or
      context.parameters.get(authQueueLen) != 80:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Prepared and protocol profiles must agree.
  let captured = readBytes(memory, MemoryAddress(uint64(cpu.registers[8])), MemoryLength(2560),
      context.copyLimit)
  case captured.error
  of MachineError.None:
    discard # Every hash byte is readable before any guest-visible validation.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # Preserve original registers and both implication versions.
    return hostSuccess[AccumulationDispatchError](response)
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Local work limits are not guest panic.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid owners grant no memory.
  let core = uint64(cpu.registers[7])
  if core >= context.parameters.get(coreCount):
    response.registers[7] = RegisterValue(high(uint64)-5) # CORE precedes authority and proposed-ID checks.
    return hostSuccess[AccumulationDispatchError](response)
  let current = context.effects.effectContext(AccumulationDimension.Regular).value
  let assigner = current.effectPrivileges.value.privilegeAssignerAt(PrivilegeCoreIndex(core)).value
  if uint32(current.effectInfo.value.service) != uint32(assigner):
    response.registers[7] = RegisterValue(high(uint64)-8) # HUH precedes proposed assigner validation.
    return hostSuccess[AccumulationDispatchError](response)
  if uint64(cpu.registers[9]) > uint64(high(uint32)):
    response.registers[7] = RegisterValue(high(uint64)-3) # WHO rejects every out-of-domain high bit.
    return hostSuccess[AccumulationDispatchError](response)
  var queue = default(array[80, AuthorizerHash])
  for i in 0..<80:
    var hash = default(array[32, byte])
    for j in 0..<32:
      hash[j] = captured.value[i*32+j] # Fixed captured extent proves every source index.
    queue[i] = AuthorizerHash(bytes: hash)
  let changed = recordAccumulationAssign(context.effects, AuthorizationCoreIndex(core), queue,
    ServiceIndex(uint32(uint64(cpu.registers[9]))), context.queues, context.privileges)
  case changed.error
  of AccumulationEffectError.None:
    context.effects = changed.value # Queue and assigner publish as one immutable version.
    response.registers[7] = RegisterValue(0) # OK, even for zero hashes or an absent proposed service.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Preserve explicit component/store refusal.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # Never expose one updated chapter.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Repeated state-boundary validation must agree.
  hostSuccess[AccumulationDispatchError](response)

# Designate charges the full item cost before capturing records or checking current authority.
proc designateResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let count = uint64(cpu.registers[8])
  let lowProduct = (count and 0xffffffff'u64)*302+1100 # Below 2^41; retain its exact carry.
  let highProduct = (count shr 32)*302+(lowProduct shr 32) # Below 2^41, including all high count bits.
  let low = ((highProduct and 0xffffffff'u64) shl 32) or (lowProduct and 0xffffffff'u64)
  let charged = chargedResponse(cpu, memory, low, highProduct shr 32)
  if charged.kind != HostResultKind.Response:
    return charged # Preserve the existing signed-negative gas representation refusal.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # No memory/profile/count/authority work before affordability.
  let cores = context.parameters.get(coreCount)
  if cores != uint64(context.staging.cores):
    return hostFailure(AccumulationDispatchError.InvalidContext) # Prepared and protocol population domains must agree.
  if count > 0x100000000'u64 div 336:
    response.action = HostAction.Panic # The natural interval cannot fit physical RAM; prove before multiplying.
    return hostSuccess[AccumulationDispatchError](response)
  let captured = readBytes(memory, MemoryAddress(uint64(cpu.registers[7])), MemoryLength(336*count),
      context.copyLimit)
  case captured.error
  of MachineError.None:
    discard # All raw record bytes, without a count prefix, precede protocol refusal checks.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # Preserve r7 and both effect versions even for a known invalid count.
    return hostSuccess[AccumulationDispatchError](response)
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Local capture policy is not a guest verdict.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory owners grant no records.
  let current = context.effects.effectContext(AccumulationDimension.Regular).value
  if count < 6 or count mod 3 != 0 or count div 3 > cores or
      uint32(current.effectInfo.value.service) != uint32(
          current.effectPrivileges.value.privilegeInfo.value.delegator):
    response.registers[7] = RegisterValue(high(uint64)-8) # HUH covers both bad population and current authority.
    return hostSuccess[AccumulationDispatchError](response)
  let extent = stateValidatorSize(ValidatorCount(count), context.staging)
  if extent.error in {StateComponentError.LimitExceeded, StateComponentError.LengthOverflow}:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Preflight component/native typed extents before allocation.
  if extent.error != StateComponentError.None:
    return hostFailure(AccumulationDispatchError.InvalidContext) # A validated protocol count must agree with codec policy.
  var validators = newSeq[StateValidator](int(count))
  for i in 0..<validators.len:
    var bs = default(array[32, byte])
    var ed = default(array[32, byte])
    var bls = default(array[144, byte])
    var metadata = default(array[128, byte])
    for j in 0..<32:
      bs[j] = captured.value[i*336+j] # Complete raw record extent proves every fixed field access.
      ed[j] = captured.value[i*336+32+j]
    for j in 0..<144:
      bls[j] = captured.value[i*336+64+j] # Preserve the entire opaque BLS encoding without validation.
    for j in 0..<128:
      metadata[j] = captured.value[i*336+208+j] # Metadata finishes the exact 336-octet record.
    validators[i] = StateValidator(bandersnatch: StateBsKey(bs), ed25519: StateEdKey(ed),
      bls: StateBlsKey(bls), metadata: StateValidatorMetadata(metadata))
  let changed = recordAccumulationDesignate(context.effects, validators, context.staging)
  case changed.error
  of AccumulationEffectError.None:
    context.effects = changed.value # Serialized C(7) and its typed owner publish together.
    response.registers[7] = RegisterValue(0) # OK, preserving record order and duplicate/zero entries.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # No fabricated protocol resource code.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # No partial state on Merklization refusal.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # State-boundary validation must agree with the host.
  hostSuccess[AccumulationDispatchError](response)

# New captures its code hash and length before current authority, funding and reserved-ID checks.
proc newResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let charged = chargedResponse(cpu, memory, 3855, 0)
  if charged.kind != HostResultKind.Response:
    return charged # Preserve the general exact gas-charge contract.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # No input capture or state work before affordability.
  if uint64(cpu.registers[8]) > uint64(high(uint32)):
    response.action = HostAction.Panic # Code request length must fit E4; never truncate high bits.
    return hostSuccess[AccumulationDispatchError](response)
  let captured = readBytes(memory, MemoryAddress(uint64(cpu.registers[7])), MemoryLength(32),
      context.copyLimit)
  case captured.error
  of MachineError.None:
    discard # A full raw offered hash is captured before all row refusals.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # Preserve full-width pointer and both implication dimensions.
    return hostSuccess[AccumulationDispatchError](response)
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Local copy policy is not guest panic.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory owners grant no hash.
  var hash = default(array[32, byte])
  for i in 0..<32:
    hash[i] = captured.value[i] # Successful fixed capture proves every index.
  let proposal = AccumulationNewService(codeHash: CodeHash(hash),
    length: RequestLength(uint32(uint64(cpu.registers[8]))),
    accumulationGas: Gas(uint64(cpu.registers[9])), transferGas: Gas(uint64(cpu.registers[10])),
    gratis: AccountBalance(uint64(cpu.registers[11])), desired: AccumulationDesiredService(uint64(
        cpu.registers[12])))
  let changed = recordAccumulationNew(context.effects, proposal, context.parameters,
      context.serviceProbes)
  case changed.error
  of AccumulationEffectError.None:
    context.effects = changed.value.effects # Account batch and next-ID cursor advance as one version.
    response.registers[7] = RegisterValue(uint32(changed.value.service)) # Actual reserved or automatic ID.
  of AccumulationEffectError.NotManager:
    response.registers[7] = RegisterValue(high(uint64)-8) # HUH precedes funding and reserved collisions.
  of AccumulationEffectError.InsufficientCash:
    response.registers[7] = RegisterValue(high(uint64)-6) # CASH precedes registrar FULL.
  of AccumulationEffectError.ServiceExists:
    response.registers[7] = RegisterValue(high(uint64)-4) # FULL applies only to occupied reserved IDs.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Probe/store policy never fabricates a guest error code.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # No account, request or cursor on hash refusal.
  of AccumulationEffectError.MalformedState:
    return hostFailure(AccumulationDispatchError.MalformedState) # Existing self metadata must be canonical.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # No partial state on other invariant failures.
  hostSuccess[AccumulationDispatchError](response)

# Upgrade changes future service metadata while this invocation continues executing its original code.
proc upgradeResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let charged = chargedResponse(cpu, memory, 1028, 0)
  if charged.kind != HostResultKind.Response:
    return charged # Preserve exact charge/debt handling from the common host boundary.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # Affordability precedes memory capture and all state changes.
  let captured = readBytes(memory, MemoryAddress(uint64(cpu.registers[7])), MemoryLength(32),
      context.copyLimit)
  case captured.error
  of MachineError.None:
    discard # The complete raw hash is readable before any successor may publish.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # Preserve full-width pointer and both implication versions.
    return hostSuccess[AccumulationDispatchError](response)
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Local capture policy is not guest panic.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory owners grant no code hash.
  var hash = default(array[32, byte])
  for i in 0..<32:
    hash[i] = captured.value[i] # Exact fixed capture proves every source index.
  let changed = recordAccumulationUpgrade(context.effects, CodeHash(hash),
    Gas(uint64(cpu.registers[8])), Gas(uint64(cpu.registers[9])))
  case changed.error
  of AccumulationEffectError.None:
    context.effects = changed.value # One complete current account version owns all three metadata changes.
    response.registers[7] = RegisterValue(0) # OK even for zero hash or zero/full-width minimum gas.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Inherited store policy remains an explicit local refusal.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # No partially upgraded metadata survives Merklization failure.
  of AccumulationEffectError.MalformedState:
    return hostFailure(AccumulationDispatchError.MalformedState) # Self metadata cannot be silently reconstructed.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Other invariant failures publish no effects.
  hostSuccess[AccumulationDispatchError](response)

# Transfer quotes the conditional fee from pure row validation before charging or publishing any debit.
proc transferResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  if context.parameters.get(transferMemoSize) != 128:
    return hostFailure(AccumulationDispatchError.InvalidContext) # The fixed C.2 memo type must match the protocol profile.
  var planned = default(PreparedAccumulationTransfer)
  var action = HostAction.Continue
  var code = 0'u64
  var deferredGas = 0'u64
  let captured = readBytes(memory, MemoryAddress(uint64(cpu.registers[10])), MemoryLength(128),
      context.copyLimit)
  case captured.error
  of MachineError.None:
    var memo = default(array[128, byte])
    for i in 0..<128:
      memo[i] = captured.value[i] # Complete fixed input capture precedes WHO/LOW/CASH checks.
    let prepared = prepareAccumulationTransfer(context.effects,
      AccumulationTransferDestination(uint64(cpu.registers[7])), TransferBalance(uint64(
          cpu.registers[8])),
      Gas(uint64(cpu.registers[9])), TransferMemo(memo), context.parameters)
    case prepared.error
    of AccumulationEffectError.None:
      planned = prepared.value # This exact source version supplies the debit after full affordability.
      deferredGas = uint64(cpu.registers[9])
    of AccumulationEffectError.UnknownService:
      code = high(uint64)-3 # WHO pays only the base fee.
    of AccumulationEffectError.TransferGasLow:
      code = high(uint64)-7 # LOW precedes CASH and pays only the base fee.
    of AccumulationEffectError.InsufficientCash:
      code = high(uint64)-6 # CASH pays no deferred gas.
    of AccumulationEffectError.MalformedState:
      return hostFailure(AccumulationDispatchError.MalformedState) # No fabricated guest verdict for corrupt metadata.
    else:
      return hostFailure(AccumulationDispatchError.InvalidContext) # No invalid plan can quote a successful fee.
  of MachineError.Fault, MachineError.InvalidRange:
    action = HostAction.Panic # Memory failure quotes base-only gas and preserves the original destination register.
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Explicit local capture policy may refuse pure fee evaluation.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory owners grant no memo.
  var low = 0'u64
  var upper = 0'u64
  if deferredGas > high(uint64)-575:
    upper = 1
    low = deferredGas-(high(uint64)-575)-1 # Exact carry without forming an overflowing sum.
  else:
    low = deferredGas+575 # Proven representable; refusals have deferredGas zero.
  let charged = chargedResponse(cpu, memory, low, upper)
  if charged.kind != HostResultKind.Response:
    return charged # Preserve exact signed-debt representation refusals.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # OOG wins over the row verdict and never commits a prepared debit.
  response.action = action
  if action == HostAction.Panic:
    return hostSuccess[AccumulationDispatchError](
        response) # Charged panic leaves r7 and both dimensions unchanged.
  if code != 0:
    response.registers[7] = RegisterValue(code)
    return hostSuccess[AccumulationDispatchError](
        response) # Funded WHO/LOW/CASH have no account or outgoing mutation.
  let changed = commitAccumulationTransfer(planned, context.transferLimit)
  case changed.error
  of AccumulationEffectError.None:
    context.effects = changed.value # Creator debit and append publish as one current version.
    response.registers[7] = RegisterValue(0) # OK, including zero-value and self transfers.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Capacity refusal is not protocol FULL or CASH.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # No append survives failed creator Merklization.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # No invalid commit may publish.
  hostSuccess[AccumulationDispatchError](response)

# Charge the fixed eject fee before memory capture or current-account validation/publication.
proc ejectResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let charged = chargedResponse(cpu, memory, 458, 0)
  if charged.kind != HostResultKind.Response:
    return charged # Preserve exact debt representation failures.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # No memory, hash, account or store work occurs without full base affordability.
  let captured = readBytes(memory, MemoryAddress(uint64(cpu.registers[8])), MemoryLength(32),
      context.copyLimit)
  case captured.error
  of MachineError.None:
    discard # A complete fixed hash precedes every row eligibility check.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic
    return hostSuccess[AccumulationDispatchError](
        response) # Preserve r7 and implications after charged memory panic.
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Explicit local copy policy cannot impersonate panic.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory owners grant no hash.
  var hash = default(array[32, byte])
  for i in 0..<32:
    hash[i] = captured.value[i] # Fixed independent value; no borrowed memory enters an effect owner.
  let changed = recordAccumulationEject(context.effects, AccumulationEjectTarget(uint64(
      cpu.registers[7])),
    ServicePreimageHash(hash), context.parameters)
  case changed.error
  of AccumulationEffectError.None:
    context.effects = changed.value
    response.registers[7] = RegisterValue(0) # OK publishes deletion and credit together.
  of AccumulationEffectError.UnknownService:
    response.registers[7] = RegisterValue(high(uint64)-3) # WHO precedes HUH.
  of AccumulationEffectError.NotRequested:
    response.registers[7] = RegisterValue(high(uint64)-8) # HUH covers footprint, request shape and insufficient age.
  of AccumulationEffectError.MalformedState:
    return hostFailure(AccumulationDispatchError.MalformedState) # Corrupt canonical state has no guest verdict.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Store policy leaves all prior versions valid.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # Hashing refusal cannot delete or credit any partial candidate.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid state includes unrepresentable balance addition.
  hostSuccess[AccumulationDispatchError](response)

# Query charges first, then validates full-width length before memory or exact current-self lookup.
proc queryResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let charged = chargedResponse(cpu, memory, 643, 0)
  if charged.kind != HostResultKind.Response:
    return charged # Preserve the shared debt representation contract.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # No row validation, input copy or namespace hashing before affordability.
  let length = uint64(cpu.registers[8])
  if length > uint64(high(uint32)):
    response.registers[7] = RegisterValue(high(uint64)-8)
    return hostSuccess[AccumulationDispatchError](response) # HUH preserves r8 and precedes memory/copy policy.
  let captured = readBytes(memory, MemoryAddress(uint64(cpu.registers[7])), MemoryLength(32),
      context.copyLimit)
  case captured.error
  of MachineError.None:
    discard # Only a complete hash authorizes lookup of the exact pair.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic
    return hostSuccess[AccumulationDispatchError](
        response) # Charged panic preserves both input registers and effects.
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Local capture ceilings do not become guest panic or NONE.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory owners grant no hash.
  var hash = default(array[32, byte])
  for i in 0..<32:
    hash[i] = captured.value[i] # Fixed copied hash cannot alias mutable guest memory.
  let current = context.effects.effectContext(AccumulationDimension.Regular).value
  let found = current.effectRequestHistory(ServicePreimageHash(hash), RequestLength(uint32(length)))
  case found.error
  of AccumulationEffectError.NotRequested:
    response.registers[7] = RegisterValue(high(uint64))
    response.registers[8] = RegisterValue(0)
    return hostSuccess[AccumulationDispatchError](response) # NONE differs from a present empty history.
  of AccumulationEffectError.None:
    discard # Fixed tagged history grants only its selected timestamp fields.
  of AccumulationEffectError.MalformedState:
    return hostFailure(AccumulationDispatchError.MalformedState) # Corrupt state has no fabricated guest shape.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # Failed namespace hashing cannot fabricate absence.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Only an initialized current owner can supply history.
  let history = found.value
  response.registers[8] = RegisterValue(0)
  case history.state
  of RequestState.Requested:
    response.registers[7] = RegisterValue(0) # Present empty request returns two zero registers.
  of RequestState.Available:
    response.registers[7] = RegisterValue(1'u64 or (uint64(uint32(
        history.since)) shl 32)) # E4 time occupies the high word.
  of RequestState.Unavailable:
    response.registers[7] = RegisterValue(2'u64 or (uint64(uint32(history.availableFrom)) shl 32))
    response.registers[8] = RegisterValue(uint64(uint32(
        history.unavailableFrom))) # Preserve the original second position.
  of RequestState.Reavailable:
    response.registers[7] = RegisterValue(3'u64 or (uint64(uint32(history.originalFrom)) shl 32))
    response.registers[8] = RegisterValue(uint64(uint32(history.removedAt)) or
      (uint64(uint32(history.restoredAt)) shl 32)) # Two complete E4 times fill one E8 register without arithmetic carry.
  hostSuccess[AccumulationDispatchError](response)

# Solicit charges first and validates length before hash capture and atomic current-self mutation.
proc solicitResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory):
    HostResult[AccumulationDispatchError] {.raises: [].} =
  let charged = chargedResponse(cpu, memory, 2193, 0)
  if charged.kind != HostResultKind.Response:
    return charged # Preserve the shared signed-debt representation contract.
  var response = charged.value
  if response.action == HostAction.OutOfGas:
    return charged # No length, memory, namespace or funding work before affordability.
  let length = uint64(cpu.registers[8])
  if length > uint64(high(uint32)):
    response.registers[7] = RegisterValue(high(uint64)-8)
    return hostSuccess[AccumulationDispatchError](
        response) # HUH precedes memory/local copy policy and preserves r8.
  let captured = readBytes(memory, MemoryAddress(uint64(cpu.registers[7])), MemoryLength(32),
      context.copyLimit)
  case captured.error
  of MachineError.None:
    discard # Only a complete fixed hash authorizes a current-self request.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic
    return hostSuccess[AccumulationDispatchError](
        response) # Charged memory panic preserves both original registers and effects.
  of MachineError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Explicit copy policy cannot become panic or FULL.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory owners supply no hash.
  var hash = default(array[32, byte])
  for i in 0..<32:
    hash[i] = captured.value[i] # Copied fixed input cannot alias guest memory in a published successor.
  let changed = recordAccumulationSolicit(context.effects, ServicePreimageHash(hash), RequestLength(
      uint32(length)), context.parameters)
  case changed.error
  of AccumulationEffectError.None:
    context.effects = changed.value
    response.registers[7] = RegisterValue(0) # OK publishes the complete new/restored request.
  of AccumulationEffectError.NotRequested:
    response.registers[7] = RegisterValue(high(uint64)-8) # HUH rejects all other existing history shapes.
  of AccumulationEffectError.StorageFull:
    response.registers[7] = RegisterValue(high(uint64)-4) # FULL preserves all prior state and effects.
  of AccumulationEffectError.MalformedState:
    return hostFailure(AccumulationDispatchError.MalformedState) # Malformed canonical state has no fabricated guest verdict.
  of AccumulationEffectError.LimitExceeded:
    return hostFailure(AccumulationDispatchError.LimitExceeded) # Inherited store ceilings remain local policy.
  of AccumulationEffectError.BackendFailure:
    return hostFailure(AccumulationDispatchError.BackendFailure) # No partially solicited request survives hashing refusal.
  else:
    return hostFailure(AccumulationDispatchError.InvalidContext) # Includes nonrepresentable footprint counters.
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
  of 6:
    infoResponse(context, cpu, memory) # Fixed account facts observe the current regular map.
  of 15:
    blessResponse(context, cpu, memory) # Manager-authorized immutable role and allowance replacement.
  of 16:
    assignResponse(context, cpu, memory) # Current assigner replaces its ordered queue and authority together.
  of 17:
    designateResponse(context, cpu, memory) # Current delegator replaces the ordered staging roster.
  of 18, 26:
    effectResponse(context, cpu, memory, uint64(stopped.hostCall) == 18) # Exact accumulation-only IDs.
  of 19:
    newResponse(context, cpu, memory) # Atomic account creation and versioned allocation cursor.
  of 20:
    upgradeResponse(context, cpu, memory) # Replace self metadata while retaining current code execution.
  of 21:
    transferResponse(context, cpu, memory) # Conditional fee and atomic deferred transfer publication.
  of 22:
    ejectResponse(context, cpu, memory) # Reclaim an eligible other account with one atomic credit/deletion.
  of 23:
    queryResponse(context, cpu, memory) # Exact current-self request history packed into two registers.
  of 24:
    solicitResponse(context, cpu, memory) # Create or restore a funded request under exact current invocation provenance.
  of 27:
    provideResponse(context, cpu, memory) # Requested provisions belong only to accumulation.
  of 1, 25:
    # These calls belong to accumulation's F but are not implemented by this adapter yet.
    hostFailure(AccumulationDispatchError.UnsupportedHostCall)
  else:
    # Refine-only IDs 7..14 and all other full-width IDs take accumulation's unknown branch.
    hostSuccess[AccumulationDispatchError](unknownHostResponse(cpu.gas, cpu.registers, memory))

proc executeAccumulationMachine*(prepared: PreparedAccumulationMachine, parameters: Parameters,
    fetchLimits: FetchAccumulationLimits, copyLimit: MemoryByteLimit,
    steps: ExecutionStepLimit, calls: HostCallLimit,
    cycles: GasCycleLimit, contextConfig: AccumulationContextConfig,
    provisionLimits = default(AccumulationProvisionLimits),
    serviceProbes = ServiceProbeLimit(0), transferLimit = ElementLimit(
        0)): AccumulationDispatchResult =
  ## Execute only the supplied prepared machine, with entropy and inputs derived from its bootstrap.
  ## Capture limits apply before execution; copy, provision and engine budgets are independent local policies.
  ## Omitted transferLimit permits no outgoing append; protocol refusals and OOG require no capacity.
  ## Omitted serviceProbes permits no automatic successor probing; reserved creation needs no probes.
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
  var context = DispatchContext(parameters: parameters, staging: contextConfig.staging,
      queues: contextConfig.queues, privileges: contextConfig.privileges, fetch: captured.value,
          copyLimit: copyLimit,

effects: initialized.value, provisionLimits: provisionLimits, serviceProbes: serviceProbes,
      transferLimit: transferLimit)
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
