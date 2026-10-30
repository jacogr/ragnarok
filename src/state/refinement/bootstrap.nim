# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Resolve refinement code commitments and build exact package-bound arguments and entry-zero CPU.
## Ready owners supply their own CPU/state/package/heap to host capture; block/input authentication is separate.

import ../../codec/[bounded, natural, composite]
import ../../codec/work/[package as work_package, digest as work_digest, report as work_report]
import ../../codec/state/service_values as state_service_values
import ../../crypto/primitives
import ../../chain/parameters
import ../../pvm/[machine, program, initialize]
import ../../pvm/host/fetch as host_fetch
import ../../pvm/refinement_exports
import ../store
import ./[lookup as refinement_lookup, dispatch as refinement_dispatch]

type
  RefinementCodeStatus* {.pure.} = enum ## Protocol eligibility selections precede CPU initialization and guest gas use.
    Bad, Big, Ready
  RefinementBootstrapError* {.pure.} = enum ## Local refusals carry no bootstrap, partial arguments or machine.
    Uninitialized, None, InvalidSelection, InvalidParameters, InvalidState, MalformedState,
    LimitExceeded, BackendFailure, MalformedCode, InvalidEnvelope, InvalidProgram, NotReady,
    InvalidInputs, InvalidContext
  RefinementBootstrapLimits* = object ## Independent local budgets never replace the fixed protocol code-size gate.
    preimage*, package*, arguments*: ByteLimit
    initialization*: InitializationLimits
  RefinementBootstrapInfo* = object ## Copied selection facts grant no authority to substitute code, arguments or source owners.
    status*: RefinementCodeStatus
    core*: CoreIndex
    item*: FetchItemIndex
    service*: ServiceIndex
    anchor*: LookupSlot
    gas*: MachineGas ## Selected allowance, not gas consumed by BAD/BIG or a later run.
    preimageBytes*: uint64
  ReadyData = ref object ## Immutable ready-only storage has no back-reference to its enclosing bootstrap owner.
    machine: Machine
    arguments: seq[byte]
    hash: PackageHash
    heap: RefinementHeapBounds
  BootstrapData = ref object ## Original complete map/package/parameters remain beside the selected code and CPU.
    info: RefinementBootstrapInfo
    state: StateStoreSnapshot
    package: OwnedWorkPackage
    parameters: Parameters
    ready: nil ReadyData
  PreparedRefinementBootstrap* = object ## Default is invalid; BAD/BIG are explicit selections without executable payloads.
    data: nil BootstrapData
  RefinementBootstrapResult*[T] = object ## Success-guarded private alternatives prevent default/refused payload extraction.
    case status: RefinementBootstrapError
    of None:
      completed: T
    else:
      discard # No partially selected code or fake machine accompanies failure.

func error*[T](outcome: RefinementBootstrapResult[T]): RefinementBootstrapError =
  ## Inspect a selected reason without writable tag access.
  outcome.status

func value*[T](outcome: RefinementBootstrapResult[T]): T
    {.requires: outcome.status == RefinementBootstrapError.None.} =
  ## Extract only a complete selected value.
  outcome.completed

proc bootstrapInfo*(prepared: PreparedRefinementBootstrap): RefinementBootstrapResult[
    RefinementBootstrapInfo] =
  ## Inspect BAD/BIG/Ready facts without exposing replaceable source handles.
  let data = prepared.data
  if data == nil: return RefinementBootstrapResult[RefinementBootstrapInfo](
      status: RefinementBootstrapError.Uninitialized)
  RefinementBootstrapResult[RefinementBootstrapInfo](status: RefinementBootstrapError.None,
      completed: data.info)

proc bootstrapMachine*(prepared: PreparedRefinementBootstrap): RefinementBootstrapResult[Machine] =
  ## Retain only the original initialized CPU; eligibility failures cannot fabricate an empty machine.
  let data = prepared.data
  if data == nil: return RefinementBootstrapResult[Machine](
      status: RefinementBootstrapError.Uninitialized)
  let ready = data.ready
  if ready == nil: return RefinementBootstrapResult[Machine](
      status: RefinementBootstrapError.NotReady)
  RefinementBootstrapResult[Machine](status: RefinementBootstrapError.None,
      completed: ready.machine)

proc bootstrapArguments*(prepared: PreparedRefinementBootstrap): RefinementBootstrapResult[seq[byte]] =
  ## Return an independent argument copy, never a mutable view of the retained ready owner.
  let data = prepared.data
  if data == nil: return RefinementBootstrapResult[seq[byte]](
      status: RefinementBootstrapError.Uninitialized)
  let ready = data.ready
  if ready == nil: return RefinementBootstrapResult[seq[byte]](
      status: RefinementBootstrapError.NotReady)
  var bytes = newSeq[byte](ready.arguments.len)
  for index in 0..<bytes.len: bytes[index] = ready.arguments[index] # Extraction cannot mutate future runs.
  RefinementBootstrapResult[seq[byte]](status: RefinementBootstrapError.None, completed: bytes)

proc bootstrapPackageHash*(prepared: PreparedRefinementBootstrap): RefinementBootstrapResult[PackageHash] =
  ## Select only a ready bootstrap's actual canonical package hash; BAD/BIG have no fabricated zero hash.
  let data = prepared.data
  if data == nil: return RefinementBootstrapResult[PackageHash](
      status: RefinementBootstrapError.Uninitialized)
  let ready = data.ready
  if ready == nil: return RefinementBootstrapResult[PackageHash](
      status: RefinementBootstrapError.NotReady)
  RefinementBootstrapResult[PackageHash](status: RefinementBootstrapError.None,
      completed: ready.hash)

proc prepareRefinementBootstrap*(state: StateStoreSnapshot, package: OwnedWorkPackage,
    item: FetchItemIndex, core: CoreIndex, parameters: Parameters,
    limits: RefinementBootstrapLimits): RefinementBootstrapResult[PreparedRefinementBootstrap] =
  ## Validate selection and historical code before allocating arguments or materializing a CPU.
  template fail(reason: RefinementBootstrapError) =
    return RefinementBootstrapResult[PreparedRefinementBootstrap](status: reason)
  if not parameters.valid: fail(RefinementBootstrapError.InvalidParameters)
  let described = package.workPackageInfo
  if described.error != PackageError.None: fail(RefinementBootstrapError.InvalidSelection)
  if uint64(item) >= uint64(described.value.items) or uint64(core) >= parameters.get(coreCount):
    fail(RefinementBootstrapError.InvalidSelection) # Compare full-width nominal indices before any narrowing.
  let selected = package.workItemAt(int(uint64(item))).value
  let info = selected.workItemInfo.value
  let context = captureHistoricalLookup(state, info.service, described.value.context.lookupSlot)
  if context.error != HistoricalLookupError.None: fail(RefinementBootstrapError.InvalidState)
  let code = historicalPreimage(context.value, info.service, ServicePreimageHash(array[32, byte](
      info.codeHash)))
  case code.error
  of HistoricalLookupError.None:
    discard # Optional absence is an ordinary BAD selection, distinct from local map/codec failure.
  of HistoricalLookupError.MalformedState:
    fail(RefinementBootstrapError.MalformedState)
  of HistoricalLookupError.BackendFailure:
    fail(RefinementBootstrapError.BackendFailure)
  of HistoricalLookupError.LimitExceeded:
    fail(RefinementBootstrapError.LimitExceeded)
  else:
    fail(RefinementBootstrapError.InvalidState)
  var facts = RefinementBootstrapInfo(status: RefinementCodeStatus.Bad, core: core, item: item,
    service: info.service, anchor: described.value.context.lookupSlot, gas: MachineGas(uint64(
        info.refineGas)))
  if code.value.present:
    facts.preimageBytes = uint64(code.value.value.byteLength) # Inspect length without copying a potentially oversized preimage.
    facts.status = if facts.preimageBytes > 4000000: RefinementCodeStatus.Big else: RefinementCodeStatus.Ready
  if facts.status != RefinementCodeStatus.Ready:
    return RefinementBootstrapResult[PreparedRefinementBootstrap](
      status: RefinementBootstrapError.None,
      completed: PreparedRefinementBootstrap(data: BootstrapData(info: facts, state: state,
        package: package, parameters: parameters, ready: nil))) # BAD/BIG expose no code, arguments or CPU.
  if facts.preimageBytes > uint64(limits.preimage): fail(RefinementBootstrapError.LimitExceeded)
  let raw = code.value.value.bytes
  let digest = blake2b256(raw)
  if digest.error != CryptoError.None: fail(RefinementBootstrapError.BackendFailure)
  if array[32, byte](digest.value) != array[32, byte](info.codeHash):
    fail(RefinementBootstrapError.InvalidState) # A synthetic map value cannot certify the item's code commitment.
  let metadata = decodeBytesBorrowed(raw, ByteLimit(raw.len))
  if metadata.error != ContainerError.None: fail(RefinementBootstrapError.MalformedCode)
  let start = metadata.consumed
  let codeBytes = raw.len-start # The canonical prefix decoder proves this subtraction and the suffix extent.
  if uint64(codeBytes) > uint64(limits.initialization.envelope): fail(
      RefinementBootstrapError.LimitExceeded)
  let prefix = [natural.encode(JamNatural(uint64(core))), natural.encode(JamNatural(uint64(item))),
    natural.encode(JamNatural(uint64(uint32(info.service)))), natural.encode(JamNatural(uint64(
        info.payloadBytes)))]
  var size = 32'u64
  for scalar in prefix: size += uint64(scalar.len) # Four encodings of at most nine bytes prove this fixed prefix sum.
  let maximum = min(uint64(limits.arguments), 16777216'u64)
  if size > maximum or uint64(info.payloadBytes) > maximum-size:
    fail(RefinementBootstrapError.LimitExceeded) # Bound all argument copies before allocating even the temporary payload.
  size += uint64(info.payloadBytes)
  if uint64(described.value.consumed) > uint64(limits.package): fail(
      RefinementBootstrapError.LimitExceeded)
  var encoded = newSeq[byte](described.value.consumed)
  if package.encodeOwnedWorkPackage(encoded).error != PackageError.None: fail(
      RefinementBootstrapError.InvalidSelection)
  let hashed = blake2b256(encoded)
  if hashed.error != CryptoError.None: fail(RefinementBootstrapError.BackendFailure)
  var arguments = newSeq[byte](int(size))
  var cursor = 0
  for scalar in prefix:
    for index in 0..<scalar.len:
      arguments[cursor] = scalar.bytes[index] # Each compact natural has only its canonical occupied bytes.
      inc cursor
  var payload = newSeq[byte](info.payloadBytes)
  if selected.copyItemPayload(payload).error != PackageError.None: fail(
      RefinementBootstrapError.InvalidSelection)
  for octet in payload:
    arguments[cursor] = octet
    inc cursor # Exact payload size was measured before allocating either buffer.
  let hash = array[32, byte](hashed.value)
  for octet in hash:
    arguments[cursor] = octet
    inc cursor # Append raw hash bytes, with no count prefix or domain token.
  var envelope = newSeq[byte](codeBytes)
  for index in 0..<codeBytes: envelope[index] = raw[
      start+index] # Copy only the authenticated suffix after metadata.
  let initialized = initializeMachine(envelope, arguments, CodeAddress(0), facts.gas,
      limits.initialization)
  case initialized.error
  of InitializationError.None:
    discard # Only a complete executable initializer can authorize Ready machine extraction.
  of InitializationError.InvalidEnvelope:
    fail(RefinementBootstrapError.InvalidEnvelope)
  of InitializationError.InvalidProgram:
    fail(RefinementBootstrapError.InvalidProgram)
  of InitializationError.LimitExceeded, InitializationError.ArgumentsTooLarge:
    fail(RefinementBootstrapError.LimitExceeded)
  else:
    fail(RefinementBootstrapError.InvalidState)
  var ro = 0'u64
  var stack = 0'u64
  for index in 0..<3:
    ro = ro or (uint64(envelope[index]) shl (index*8))
    stack = stack or (uint64(envelope[8+index]) shl (
        index*8)) # The validated initializer proves both E3 fields exist.
  # E3 fields are <=2^24-1, proving zone rounding, endpoint subtraction and page narrowing fit.
  let heap = RefinementHeapBounds(first: PageIndex(uint32(32+((ro+65535) div 65536)*16)),
    past: PageIndex(uint32((0xfefd0000'u64-((stack+65535) div 65536)*65536) div 4096)))
  RefinementBootstrapResult[PreparedRefinementBootstrap](status: RefinementBootstrapError.None,
    completed: PreparedRefinementBootstrap(data: BootstrapData(info: facts, state: state,
      package: package, parameters: parameters, ready: ReadyData(machine: initialized.value,
        arguments: arguments, hash: PackageHash(bytes: hash), heap: heap))))

proc bootstrapHosts*(prepared: PreparedRefinementBootstrap, trace: openArray[byte],
    inputs: RefinementInputs, offset: ExportOffset, limits: RefinementCaptureLimits):
    RefinementBootstrapResult[PreparedRefinementExecution] =
  ## Bind host capture to this bootstrap's exact initialized CPU, complete map and original package selection.
  let data = prepared.data
  if data == nil: return RefinementBootstrapResult[PreparedRefinementExecution](
      status: RefinementBootstrapError.Uninitialized)
  let ready = data.ready
  if ready == nil: return RefinementBootstrapResult[PreparedRefinementExecution](
      status: RefinementBootstrapError.NotReady)
  let captured = prepareRefinementExecution(ready.machine, data.state, data.package, data.info.item,
    data.parameters, trace, inputs, ready.heap, offset, limits)
  let reason = case captured.error
    of RefinementDispatchError.None: RefinementBootstrapError.None # Preserve only complete environment capture.
    of RefinementDispatchError.LimitExceeded: RefinementBootstrapError.LimitExceeded
    of RefinementDispatchError.InvalidInputs: RefinementBootstrapError.InvalidInputs
    else: RefinementBootstrapError.InvalidContext
  if reason != RefinementBootstrapError.None:
    return RefinementBootstrapResult[PreparedRefinementExecution](status: reason)
  RefinementBootstrapResult[PreparedRefinementExecution](status: RefinementBootstrapError.None,
      completed: captured.value)
