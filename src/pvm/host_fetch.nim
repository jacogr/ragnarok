# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Evaluate fetch for optional entropy, trace and raw package blobs, or directly borrowed values.
## Exposes FetchContext capture, bounded withFetchPackage attachment and selector responses.
## FetchResult separates local refusals from completed Continue, Panic and OutOfGas responses.
## Capture owns bounded immutable context; responses own memory copies. See spec/pvm-fetch-context.md.

import ./[machine, step]
import ../codec/work_package

type
  # Invocation entropy is one nominal 32-byte value, distinct from arbitrary trace bytes.
  FetchEntropy* = distinct array[32, byte]
  # Local misuse and resource policy are not guest-visible host exits.
  FetchError* {.pure.} = enum
    Uninitialized, None, UnsupportedSelector, InvalidMemory, LimitExceeded, InvalidContext
  # Private tagged alternatives prevent reading a response after a local refusal.
  FetchResult* = object
    case status: FetchError
    of None:
      # The response retains immutable memory and copies registers; no borrowed input escapes.
      completed: HostResponse
    else:
      # Failure carries no partly charged response or partial copy.
      discard

type
  # Explicit presence distinguishes an absent trace from a present zero-byte trace.
  FetchPresence* {.pure.} = enum
    Absent, Present
  # Local cap on variable trace snapshot bytes; the fixed entropy field is always constant-size.
  FetchTraceLimit* = distinct uint64
  # Local cap on configuration, token and all item payload bytes captured together.
  FetchPackageLimit* = distinct uint64
  # Private package snapshot keeps only the raw blobs this fetch selector family needs.
  # The fixed item table is bounded by the validated C.2 package limit of sixteen items.
  FetchPackageData = ref object
    configuration: seq[byte]
    authorization: seq[byte]
    payloads: array[16, seq[byte]]
    itemCount: int
  # Private acyclic owner retains only selected input values and has no references to caller storage.
  FetchContextData = ref object
    entropyPresence: FetchPresence
    entropy: FetchEntropy
    tracePresence: FetchPresence
    trace: seq[byte]
  # Public immutable handle; default is invalid, while explicit all-absent capture is valid.
  FetchContext* = object
    data: nil FetchContextData
    packageData: nil FetchPackageData
  # Capture failures carry only the local reason, never a partial owner or borrowed input span.
  FetchContextResult* = object
    case status: FetchError
    of None:
      # Extracted handles share an immutable snapshot with no writable storage accessor.
      completed: FetchContext
    else:
      # Uninitialized and refused captures expose no snapshot.
      discard

# Inspect capture status without allowing result retagging.
func error*(r: FetchContextResult): FetchError = r.status
# Select the captured immutable context only after checking success.
func value*(r: FetchContextResult): FetchContext
    {.requires: r.status == FetchError.None.} = r.completed

# Capture entropy and trace presence independently; borrow caller inputs only until this call returns.
# Absent payload arguments are ignored and not copied. A present trace is bounded before allocation;
# its length is already representable as int because the input is a valid openArray.
proc captureFetchContext*(entropyPresence: FetchPresence, entropy: FetchEntropy,
    tracePresence: FetchPresence, trace: openArray[byte],
        limit: FetchTraceLimit): FetchContextResult =
  if tracePresence == FetchPresence.Present and uint64(trace.len) > uint64(limit):
    # A local capture cap cannot silently truncate a protocol value or turn it into absence.
    return FetchContextResult(status: FetchError.LimitExceeded)
  var copied = newSeq[byte](0)
  if tracePresence == FetchPresence.Present:
    # Allocate only the selected trace after checking the complete input length.
    copied = newSeq[byte](trace.len)
    for i in 0..<trace.len:
      # Independent storage prevents caller mutation from changing later fetch responses.
      copied[i] = trace[i]
  let selectedEntropy = (if entropyPresence == FetchPresence.Present: entropy
    else: FetchEntropy(default(array[32, byte])))
  let owner = FetchContextData(entropyPresence: entropyPresence, entropy: selectedEntropy,
    tracePresence: tracePresence, trace: copied)
  FetchContextResult(status: FetchError.None, completed: FetchContext(data: owner,
      packageData: nil))

# Attach raw package blobs to a new context without changing the original entropy/trace snapshot.
# Present input must be a validated codec owner. Preflight aggregate byte lengths before allocating;
# copying happens once at capture, never once per guest fetch. Absence ignores the package argument.
proc withFetchPackage*(context: FetchContext, presence: FetchPresence,
    package: OwnedWorkPackage, limit: FetchPackageLimit): FetchContextResult =
  if context.data == nil:
    # An invalid base must not be converted into a valid context by attaching package data.
    return FetchContextResult(status: FetchError.InvalidContext)
  if presence == FetchPresence.Absent:
    # Clearing only the package selection preserves the original immutable entropy/trace owner.
    return FetchContextResult(status: FetchError.None,
      completed: FetchContext(data: context.data, packageData: nil))
  let described = workPackageInfo(package)
  if described.error != PackageError.None:
    # Default codec handles are local misuse, not an absent protocol package.
    return FetchContextResult(status: FetchError.InvalidContext)
  let info = described.value
  if info.items < 1 or info.items > 16:
    # The codec guarantees this bound; retain a guard before indexing the fixed capture tables.
    return FetchContextResult(status: FetchError.InvalidContext)
  var remaining = uint64(limit)
  for length in [info.configurationBytes, info.authorizationBytes]:
    # Subtract after comparison to bound the aggregate without overflowing a size sum.
    if uint64(length) > remaining:
      return FetchContextResult(status: FetchError.LimitExceeded)
    remaining -= uint64(length)
  var items = default(array[16, OwnedWorkItem])
  var lengths = default(array[16, int])
  for i in 0..<info.items:
    # Owner-bound item metadata validates every selected extent before any payload allocation.
    let selected = workItemAt(package, i)
    if selected.error != PackageError.None:
      # Retained item selection must succeed for every validated package index.
      return FetchContextResult(status: FetchError.InvalidContext)
    items[i] = selected.value
    let item = workItemInfo(items[i])
    if item.error != PackageError.None:
      # Never allocate from metadata when the bound child lookup refused.
      return FetchContextResult(status: FetchError.InvalidContext)
    lengths[i] = item.value.payloadBytes
    if uint64(lengths[i]) > remaining:
      # A late item over budget refuses the entire capture, not just the final payload.
      return FetchContextResult(status: FetchError.LimitExceeded)
    remaining -= uint64(lengths[i])
  let captured = FetchPackageData(configuration: newSeq[byte](info.configurationBytes),
    authorization: newSeq[byte](info.authorizationBytes), payloads: default(array[16, seq[byte]]),
    itemCount: info.items)
  if copyPackageBlob(package, PackageBlob.Configuration, captured.configuration).error !=
      PackageError.None:
    # The codec checks the complete output span; no unfinished owner escapes an unexpected refusal.
    return FetchContextResult(status: FetchError.InvalidContext)
  if copyPackageBlob(package, PackageBlob.Authorization, captured.authorization).error !=
      PackageError.None:
    # Token extraction is distinct from configuration despite both being byte sequences.
    return FetchContextResult(status: FetchError.InvalidContext)
  for i in 0..<info.items:
    # Each payload has independent storage; empty present payloads remain distinguishable from absence.
    captured.payloads[i] = newSeq[byte](lengths[i])
    if copyItemPayload(items[i], captured.payloads[i]).error != PackageError.None:
      # The unpublished owner and all earlier copied bytes are released on refusal.
      return FetchContextResult(status: FetchError.InvalidContext)
  FetchContextResult(status: FetchError.None,
    completed: FetchContext(data: context.data, packageData: captured))

# Inspect a result without exposing mutable variant storage.
func error*(r: FetchResult): FetchError = r.status
# Select a completed protocol outcome only after checking success.
func value*(r: FetchResult): HostResponse {.requires: r.status == FetchError.None.} = r.completed

# Apply a selected value or absence after the wrapper chooses its selector and fixed prices.
# Caller bytes must remain stable during this synchronous call; the source memory is immutable.
proc fetchValue(gas: MachineGas, registers: RegisterFile, memory: Memory,
    bytes: openArray[byte], present: bool, selector, base, rate: uint64,
        limit: MemoryByteLimit): FetchResult =
  if uint64(registers[10]) != selector:
    # A known but unimplemented selector must never become an unknown/absent-value response.
    return FetchResult(status: FetchError.UnsupportedSelector)
  if pageImage(memory, PageIndex(0)).error != MachineError.None:
    # Reject default owners even when gas is insufficient or the clipped copy would be empty.
    return FetchResult(status: FetchError.InvalidMemory)
  let requested = uint64(registers[9])
  # Splitting before multiplication computes ceil(rate*z/1024) for all uint64 z without overflow.
  # Private callers use rate <= 96 and base <= 103, so the total and any deficit fit signed 64 bits.
  let cost = base + (requested div 1024) * rate + ((requested mod 1024) * rate + 1023) div 1024
  if uint64(gas) < cost:
    # General-host underfunding takes precedence over guest memory and local copy-size checks.
    return FetchResult(status: FetchError.None, completed: HostResponse(
      action: HostAction.OutOfGas, gas: MachineGas(0), gasDeficit: GasDeficit(cost - uint64(gas)),
      registers: registers, memory: memory))
  var response = HostResponse(action: HostAction.Continue, gas: MachineGas(uint64(gas) - cost),
    gasDeficit: GasDeficit(0), registers: registers, memory: memory)
  if not present:
    # GP notation defines |none| = 0: the copy interval is empty for every destination pointer.
    # Requested-length charging above still applies; absence returns NONE, not zero-length success.
    response.registers[7] = RegisterValue(high(uint64))
    return FetchResult(status: FetchError.None, completed: response)
  let offset = min(uint64(registers[8]), uint64(bytes.len))
  let count = min(requested, uint64(bytes.len) - offset)
  # Clipping to the existing borrowed span proves both conversions and the inclusive end safe.
  var written = default(MachineResult[Memory])
  if count == 0:
    # Empty natural intervals permit every pointer; avoid constructing an inverted borrowed slice.
    written = writeBytes(memory, MemoryAddress(uint64(registers[7])), [], limit)
  else:
    # writeBytes preflights the whole destination and never exposes a writable partial prefix.
    written = writeBytes(memory, MemoryAddress(uint64(registers[7])),
      bytes.toOpenArray(int(offset), int(offset + count - 1)), limit)
  case written.error
  of MachineError.None:
    # Return the complete selected value length, not the requested or copied length.
    response.memory = written.value
    response.registers[7] = RegisterValue(uint64(bytes.len))
  of MachineError.Fault, MachineError.InvalidRange:
    # The fetch table maps unwritable natural ranges to Panic, retaining r7 and all memory.
    response.action = HostAction.Panic
  of MachineError.LimitExceeded:
    # Local copy policy cannot manufacture a protocol panic; no response escapes this refusal.
    return FetchResult(status: FetchError.LimitExceeded)
  else:
    # Valid owner/range inputs cannot produce another memory failure; retain an explicit local guard.
    return FetchResult(status: FetchError.InvalidMemory)
  FetchResult(status: FetchError.None, completed: response)

# Fetch selector 1 with present 32-byte entropy: fixed cost 103, independent of requested length.
# Dispatcher supplies the invocation's entropy and host identifier 2; absence is outside this API.
proc fetchEntropyResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory,
    entropy: FetchEntropy, limit: MemoryByteLimit): FetchResult =
  fetchValue(gas, registers, memory, array[32, byte](entropy), true, 1, 103, 0, limit)

# Fetch selector 2 with a present trace (including empty): cost 80 + ceil(96*r9/1024).
# This does not select invocation context. A local failure must be propagated by the dispatcher,
# never converted to HostAction.Panic. Fallible executeWithHost callbacks can return hostFailure(error).
proc fetchTraceResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory,
    trace: openArray[byte], limit: MemoryByteLimit): FetchResult =
  fetchValue(gas, registers, memory, trace, true, 2, 80, 96, limit)

# Select entropy, trace or package blobs for host identifier 2; other known selectors remain local refusals.
# Values >= 16 are protocol-unknown selectors (cost 80, NONE), not unknown host identifiers.
# Invalid context/memory and local copy caps remain typed failures for fallible host dispatch.
proc fetchContextResponse*(context: FetchContext, gas: MachineGas, registers: RegisterFile,
    memory: Memory, limit: MemoryByteLimit): FetchResult =
  let owner = context.data
  if owner == nil:
    # Default handles cannot masquerade as a valid invocation with both values absent.
    return FetchResult(status: FetchError.InvalidContext)
  let selector = uint64(registers[10])
  case selector
  of 1:
    # Entropy is exactly 32 bytes when present; absence retains selector 1's fixed charge.
    fetchValue(gas, registers, memory, array[32, byte](owner.entropy),
      owner.entropyPresence == FetchPresence.Present, 1, 103, 0, limit)
  of 2:
    # Trace absence still charges the requested length at selector 2's rate.
    fetchValue(gas, registers, memory, owner.trace,
      owner.tracePresence == FetchPresence.Present, 2, 80, 96, limit)
  of 8, 9, 13:
    # All three raw-blob selectors share presence, bounds, charging and atomic-copy semantics.
    let package = context.packageData
    let base = (if selector == 8: 84'u64 elif selector == 9: 88'u64 else: 95'u64)
    let rate = (if selector == 13: 96'u64 else: 0'u64)
    if package == nil:
      # Missing package retains the selected price, including payload's requested-length charge.
      return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
    if selector == 8:
      # Configuration bytes are returned raw, without their C.2 variable-length prefix.
      return fetchValue(gas, registers, memory, package.configuration, true, selector, base, rate, limit)
    if selector == 9:
      # Authorization token is independent of the authorizer configuration and ignores item registers.
      return fetchValue(gas, registers, memory, package.authorization, true, selector, base, rate, limit)
    let index = uint64(registers[11])
    if index >= uint64(package.itemCount):
      # Compare the full register width before narrowing, so huge indices cannot wrap onto an item.
      return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
    fetchValue(gas, registers, memory, package.payloads[int(index)], true, selector, base, rate, limit)
  else:
    # Known selectors need their own context and encoding implementation, never a fabricated NONE.
    if selector < 16:
      return FetchResult(status: FetchError.UnsupportedSelector)
    # The table's otherwise branch uses c = none and a zero-sized absent value.
    fetchValue(gas, registers, memory, [], false, selector, 80, 0, limit)
