# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Evaluate all fetch selectors for configured parameters and explicitly captured invocation inputs.
## Exposes FetchContext capture, bounded accumulation/package/input attachment and selector responses.
## FetchResult separates local refusals from completed Continue, Panic and OutOfGas responses.
## Capture owns bounded immutable context; responses own memory copies. See spec/pvm-fetch-context.md.

import ../[machine, step]
import ../../chain/parameters
import ../../codec/work/package as work_package
import ../../codec/[fixed_unsigned, c2_records, bounded, natural]

type
  FetchEntropy* = distinct array[32, byte] ## Invocation entropy is one nominal 32-byte value, distinct from arbitrary trace bytes.
  FetchError* {.pure.} = enum ## Local misuse and resource policy are not guest-visible host exits.
    Uninitialized, None, UnsupportedSelector, InvalidMemory, LimitExceeded, InvalidContext
  FetchResult* = object ## Private tagged alternatives prevent reading a response after a local refusal.
    case status: FetchError
    of None:
      # The response retains immutable memory and copies registers; no borrowed input escapes.
      completed: HostResponse
    else:
      # Failure carries no partly charged response or partial copy.
      discard

type
  FetchPresence* {.pure.} = enum ## Explicit presence distinguishes an absent trace from a present zero-byte trace.
    Absent, Present
  FetchTraceLimit* = distinct uint64 ## Local cap on variable trace snapshot bytes; the fixed entropy field is always constant-size.
  FetchPackageLimit* = distinct uint64 ## Local cap on configuration, token and all item payload bytes captured together.
  FetchEncodingLimit* = distinct uint64 ## Separate local cap on the complete canonical package encoding, including framing and manifests.
  FetchItemIndex* = distinct uint64 ## Index of the invocation's current work item, separate from guest-supplied register indices.
  FetchSegment* = distinct array[4104, byte] ## GP 0.8.0 data segments have exactly 4104 bytes, unlike arbitrary extrinsic preimages.
  FetchInputLimit* = distinct uint64 ## Aggregate selected extrinsic and import bytes; metadata has separate fixed protocol bounds.
  FetchInputs* = object ## Borrowed capture description. Absent fields are ignored; present tables preserve item order.
 ## Caller must supply authenticated preimages/segments matching the invocation's manifests.
    extrinsicsPresence*: FetchPresence
    importsPresence*: FetchPresence
    currentPresence*: FetchPresence
    current*: FetchItemIndex
    extrinsics*: seq[seq[seq[byte]]]
    imports*: seq[seq[FetchSegment]]
  # Private acyclic snapshot owns deep copies; no reference to the mutable capture description escapes.
  FetchInputData = ref object
    values: FetchInputs
  # Private package snapshot owns raw blobs and fixed bounded encoded metadata.
  # The fixed item table is bounded by the validated C.2 package limit of sixteen items.
  FetchPackageData = ref object
    encoded: seq[byte]
    configuration: seq[byte]
    authorization: seq[byte]
    payloads: array[16, seq[byte]]
    itemCount: int
    context: array[425, byte]
    contextLength: int
    summaries: array[993, byte]
  # Private acyclic owner retains only selected input values and has no references to caller storage.
  FetchContextData = ref object
    entropyPresence: FetchPresence
    entropy: FetchEntropy
    tracePresence: FetchPresence
    trace: seq[byte]
  FetchAccumulationLimits* = object ## Independent local limits bound descriptors, complete list bytes and each C.2 input record.
    items*: ElementLimit
    bytes*: ByteLimit
    operand*: OperandLimits
  # One immutable slice selects a record in the single canonical list buffer.
  FetchAccumulationSpan = object
    start, length: int
  # Private acyclic owner stores list framing once, without duplicating each record's bytes.
  FetchAccumulationData = ref object
    bytes: seq[byte]
    spans: seq[FetchAccumulationSpan]
  # Fixed parameter encoding is captured once from the configured chain snapshot.
  FetchParameterData = ref object
    bytes: array[ParameterBytes, byte]
  FetchContext* = object ## Public immutable handle; default is invalid, while explicit all-absent capture is valid.
    data: nil FetchContextData
    packageData: nil FetchPackageData
    inputData: nil FetchInputData
    parameterData: nil FetchParameterData
    accumulationData: nil FetchAccumulationData
  FetchContextResult* = object ## Capture failures carry only the local reason, never a partial owner or borrowed input span.
    case status: FetchError
    of None:
      # Extracted handles share an immutable snapshot with no writable storage accessor.
      completed: FetchContext
    else:
      # Uninitialized and refused captures expose no snapshot.
      discard

func error*(r: FetchContextResult): FetchError =
  ## Inspect capture status without allowing result retagging.
  r.status

func value*(r: FetchContextResult): FetchContext
    {.requires: r.status == FetchError.None.} =
  ## Select the captured immutable context only after checking success.
  r.completed

proc captureFetchContext*(entropyPresence: FetchPresence, entropy: FetchEntropy,
    tracePresence: FetchPresence, trace: openArray[byte],
        limit: FetchTraceLimit): FetchContextResult =
  ## Capture entropy and trace presence independently; borrow caller inputs only until this call returns.
  ## Absent payload arguments are ignored and not copied. A present trace is bounded before allocation;
  ## its length is already representable as int because the input is a valid openArray.
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
      packageData: nil, inputData: nil, parameterData: nil, accumulationData: nil))

proc withFetchAccumulation*(context: FetchContext, presence: FetchPresence,
    inputs: openArray[AccumulationSource], limits: FetchAccumulationLimits): FetchContextResult =
  ## Capture the caller's ordered accumulation inputs using the existing C.2 encoder.
  ## Caller sources must remain stable until return. Invocation assembly supplies the correct ordering;
  ## this operation neither sorts inputs nor authenticates their provenance. Absence ignores sources/caps.
  if context.data == nil:
    # Missing base context cannot become valid through an absent or present attachment.
    return FetchContextResult(status: FetchError.InvalidContext)
  if presence == FetchPresence.Absent:
    # Clearing this family preserves all unrelated immutable invocation selections.
    var cleared = context
    cleared.accumulationData = nil
    return FetchContextResult(status: FetchError.None, completed: cleared)
  if uint64(inputs.len) > uint64(limits.items):
    # Bound metadata traversal and allocation even when many records have small payloads.
    return FetchContextResult(status: FetchError.LimitExceeded)
  let prefix = natural.encode(JamNatural(uint64(inputs.len)))
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  var total = uint64(prefix.len)
  if total > maximum:
    # Even the present empty list needs its one-byte compact zero count.
    return FetchContextResult(status: FetchError.LimitExceeded)
  for input in inputs:
    # Reuse the codec's allocation-free preflight for both tagged record alternatives.
    let measured = accumulationInputSize(input, limits.operand)
    if measured.error != RecordError.None:
      # Local record policy refusal must not masquerade as protocol absence or a partial capture.
      let reason = (if measured.error == RecordError.LimitExceeded or
        measured.error == RecordError.LengthOverflow: FetchError.LimitExceeded else: FetchError.InvalidContext)
      return FetchContextResult(status: reason)
    if uint64(measured.value) > maximum - total:
      # Subtraction after the initial bound prevents overflow before the final host-int conversion.
      return FetchContextResult(status: FetchError.LimitExceeded)
    total += uint64(measured.value)
  # Each record occupies at least 132 bytes, so the byte bound also bounds span-storage arithmetic.
  let owner = FetchAccumulationData(bytes: newSeq[byte](int(total)),
    spans: newSeq[FetchAccumulationSpan](inputs.len))
  for i in 0..<prefix.len:
    # The list prefix counts inputs, not encoded bytes, and is never repeated per member.
    owner.bytes[i] = prefix.bytes[i]
  var cursor = int(prefix.len)
  for i in 0..<inputs.len:
    # Encode into the remaining buffer only after the entire source passed preflight.
    let encoded = encodeAccumulationInput(inputs[i], limits.operand,
      owner.bytes.toOpenArray(cursor, owner.bytes.len - 1))
    if encoded.error != RecordError.None:
      # A failed codec commit cannot publish the private partial owner.
      return FetchContextResult(status: FetchError.InvalidContext)
    owner.spans[i] = FetchAccumulationSpan(start: cursor, length: encoded.value)
    cursor += encoded.value
  if cursor != owner.bytes.len:
    # Preflight and encoder must agree exactly; no trailing padding or incomplete list is exposed.
    return FetchContextResult(status: FetchError.InvalidContext)
  var captured = context
  captured.accumulationData = owner
  FetchContextResult(status: FetchError.None, completed: captured)

proc withFetchParameters*(context: FetchContext, parameters: Parameters): FetchContextResult =
  ## Attach the configured chain parameters while preserving all invocation-specific selections.
  ## Missing/default parameters are local configuration errors, never an absent protocol value.
  if context.data == nil or not parameters.valid:
    # Reject uninitialized context or parameters before allocating the fixed-size snapshot.
    return FetchContextResult(status: FetchError.InvalidContext)
  FetchContextResult(status: FetchError.None, completed: FetchContext(data: context.data,
    packageData: context.packageData, inputData: context.inputData,
    parameterData: FetchParameterData(bytes: encodeParameters(parameters)),
    accumulationData: context.accumulationData))

proc withFetchInputs*(context: FetchContext, source: FetchInputs,
    limit: FetchInputLimit): FetchContextResult =
  ## Replace both external-input selections while retaining package, entropy and trace snapshots.
  ## Preflight all counts, current-item indices and aggregate bytes before any variable allocation.
  ## The caller keeps source storage stable until return; absent table arguments are never inspected.
  if context.data == nil:
    # A default base cannot be repaired by attaching external inputs.
    return FetchContextResult(status: FetchError.InvalidContext)
  var remaining = uint64(limit)
  var extrinsicCount = 0
  var importCount = 0
  if source.extrinsicsPresence == FetchPresence.Present:
    # A package contains at most sixteen work items, even when every row is empty.
    if source.extrinsics.len > 16:
      return FetchContextResult(status: FetchError.LimitExceeded)
    if source.currentPresence == FetchPresence.Present and
        uint64(source.current) >= uint64(source.extrinsics.len):
      # Invocation indices must be valid before the current-item selector can be evaluated.
      return FetchContextResult(status: FetchError.InvalidContext)
    for row in source.extrinsics:
      # The package-wide commitment cap bounds metadata for zero-byte preimages as well.
      if row.len > 128 - extrinsicCount:
        return FetchContextResult(status: FetchError.LimitExceeded)
      extrinsicCount += row.len
      for blob in row:
        # Subtract only after comparison, avoiding overflow in aggregate length arithmetic.
        if uint64(blob.len) > remaining:
          return FetchContextResult(status: FetchError.LimitExceeded)
        remaining -= uint64(blob.len)
  if source.importsPresence == FetchPresence.Present:
    # Independently selected import tables have the same work-item bound.
    if source.imports.len > 16:
      return FetchContextResult(status: FetchError.LimitExceeded)
    if source.currentPresence == FetchPresence.Present and
        uint64(source.current) >= uint64(source.imports.len):
      # Do not silently turn an invalid caller-supplied current item into protocol absence.
      return FetchContextResult(status: FetchError.InvalidContext)
    for row in source.imports:
      # Fixed segment width makes the byte product safe after the package-wide count check.
      if row.len > 3072 - importCount:
        return FetchContextResult(status: FetchError.LimitExceeded)
      importCount += row.len
      let bytes = uint64(row.len) * 4104
      if bytes > remaining:
        return FetchContextResult(status: FetchError.LimitExceeded)
      remaining -= bytes
  var copied = FetchInputs(extrinsicsPresence: source.extrinsicsPresence,
    importsPresence: source.importsPresence, currentPresence: source.currentPresence,
    current: source.current)
  if source.extrinsicsPresence == FetchPresence.Present:
    # Deep-copy each descriptor and blob only after the entire capture passed its resource checks.
    copied.extrinsics = newSeq[seq[seq[byte]]](source.extrinsics.len)
    for i in 0..<source.extrinsics.len:
      # Empty rows are retained to preserve work-item indices.
      copied.extrinsics[i] = newSeq[seq[byte]](source.extrinsics[i].len)
      for j in 0..<source.extrinsics[i].len:
        # Empty blobs remain present values, distinct from missing rows or indices.
        copied.extrinsics[i][j] = newSeq[byte](source.extrinsics[i][j].len)
        for k in 0..<source.extrinsics[i][j].len:
          # No mutable source byte storage is retained in the private owner.
          copied.extrinsics[i][j][k] = source.extrinsics[i][j][k]
  if source.importsPresence == FetchPresence.Present:
    # Segment arrays copy by value, while both descriptor levels require independent storage.
    copied.imports = newSeq[seq[FetchSegment]](source.imports.len)
    for i in 0..<source.imports.len:
      # Preserve even empty rows without allocating any segment bytes for them.
      copied.imports[i] = newSeq[FetchSegment](source.imports[i].len)
      for j in 0..<source.imports[i].len:
        # Fixed arrays cannot retain references into caller-owned sequences.
        copied.imports[i][j] = source.imports[i][j]
  FetchContextResult(status: FetchError.None, completed: FetchContext(data: context.data,
    packageData: context.packageData, inputData: FetchInputData(values: copied),
        parameterData: context.parameterData, accumulationData: context.accumulationData))

proc summaryField(output: var openArray[byte], offset, width: int, value: uint64): bool =
  ## Write one bounded fixed-width summary field using the canonical scalar codec.
  ## Private callers pass disjoint fields inside a fixed 62-byte summary; failure publishes no owner.
  let encoded = encodeFixed(FixedUnsigned(value), ByteWidth(width))
  if not encoded.ok:
    # Retain a checked narrowing boundary even for validated codec metadata.
    return false
  for i in 0..<width:
    # Field extents are constants selected by encodeSummary below.
    output[offset + i] = encoded.encoded.bytes[i]
  true

proc encodeSummary(item: ItemInfo, output: var openArray[byte]): bool =
  ## Encode GP fetch S(w), which differs from C.2 work-item serialization and omits all blob contents.
  ## The caller owns exactly 62 bytes; each count/length is checked by the fixed-width codec.
  if output.len != 62:
    # Prevent private caller mistakes from exposing an incomplete summary.
    return false
  if not summaryField(output, 0, 4, uint64(item.service)) or
      not summaryField(output, 36, 8, uint64(item.refineGas)) or
      not summaryField(output, 44, 8, uint64(item.accumulateGas)) or
      not summaryField(output, 52, 2, uint64(item.exports)) or
      not summaryField(output, 54, 2, uint64(item.imports)) or
      not summaryField(output, 56, 2, uint64(item.extrinsics)) or
      not summaryField(output, 58, 4, uint64(item.payloadBytes)):
    # Any unrepresentable field refuses capture before allocating raw blobs.
    return false
  let hash = array[32, byte](item.codeHash)
  for i in 0..<32:
    # Hash bytes retain their original order, unlike the little-endian scalar fields.
    output[4 + i] = hash[i]
  true

proc withFetchPackage*(context: FetchContext, presence: FetchPresence,
    package: OwnedWorkPackage, limit: FetchPackageLimit,
    encodingLimit: FetchEncodingLimit): FetchContextResult =
  ## Attach package blobs and encoded metadata while preserving the original entropy/trace snapshot.
  ## Present input must be a validated codec owner. Preflight aggregate byte lengths before allocating;
  ## The raw-blob cap and complete-encoding cap are independent and both checked before allocation.
  ## Copying happens once at capture, never once per guest fetch. Absence ignores package and both caps.
  if context.data == nil:
    # An invalid base must not be converted into a valid context by attaching package data.
    return FetchContextResult(status: FetchError.InvalidContext)
  if presence == FetchPresence.Absent:
    # Clearing only the package selection preserves the original immutable entropy/trace owner.
    return FetchContextResult(status: FetchError.None,
      completed: FetchContext(data: context.data, packageData: nil, inputData: context.inputData,
          parameterData: context.parameterData, accumulationData: context.accumulationData))
  let described = workPackageInfo(package)
  if described.error != PackageError.None:
    # Default codec handles are local misuse, not an absent protocol package.
    return FetchContextResult(status: FetchError.InvalidContext)
  let info = described.value
  if info.items < 1 or info.items > 16:
    # The codec guarantees this bound; retain a guard before indexing the fixed capture tables.
    return FetchContextResult(status: FetchError.InvalidContext)
  if info.consumed < 1:
    # A validated package always has a nonempty canonical prefix; reject invalid internal metadata.
    return FetchContextResult(status: FetchError.InvalidContext)
  if uint64(info.consumed) > uint64(encodingLimit):
    # Bound the extra complete encoding before allocating any capture storage.
    return FetchContextResult(status: FetchError.LimitExceeded)
  var remaining = uint64(limit)
  for length in [info.configurationBytes, info.authorizationBytes]:
    # Subtract after comparison to bound the aggregate without overflowing a size sum.
    if uint64(length) > remaining:
      return FetchContextResult(status: FetchError.LimitExceeded)
    remaining -= uint64(length)
  var contextBytes = default(array[425, byte])
  let contextEncoded = encodeRefinementContext(info.context, contextBytes)
  if contextEncoded.error != PackageError.None:
    # Eight prerequisites bound the canonical context encoding to 425 bytes.
    return FetchContextResult(status: FetchError.InvalidContext)
  var summaries = default(array[993, byte])
  # A validated count in 1..16 has a one-byte compact encoding; this prefix counts items, not bytes.
  summaries[0] = byte(info.items)
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
    if not encodeSummary(item.value, summaries.toOpenArray(1 + i * 62, (i + 1) * 62)):
      # Fixed metadata is prepared before allocating any variable-size snapshot blobs.
      return FetchContextResult(status: FetchError.InvalidContext)
    lengths[i] = item.value.payloadBytes
    if uint64(lengths[i]) > remaining:
      # A late item over budget refuses the entire capture, not just the final payload.
      return FetchContextResult(status: FetchError.LimitExceeded)
    remaining -= uint64(lengths[i])
  let captured = FetchPackageData(encoded: newSeq[byte](info.consumed), configuration: newSeq[byte](
      info.configurationBytes),
    authorization: newSeq[byte](info.authorizationBytes), payloads: default(array[16, seq[byte]]),
    itemCount: info.items, context: contextBytes, contextLength: contextEncoded.value,
    summaries: summaries)
  let encoded = encodeOwnedWorkPackage(package, captured.encoded)
  if encoded.error != PackageError.None:
    # Copy only the validated canonical package prefix, never unrelated trailing decoder input.
    return FetchContextResult(status: FetchError.InvalidContext)
  if encoded.value != info.consumed:
    # The captured owner must contain the entire measured encoding with no truncation or padding.
    return FetchContextResult(status: FetchError.InvalidContext)
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
    completed: FetchContext(data: context.data, packageData: captured,
        inputData: context.inputData, parameterData: context.parameterData,
        accumulationData: context.accumulationData))

func error*(r: FetchResult): FetchError =
  ## Inspect a result without exposing mutable variant storage.
  r.status

func value*(r: FetchResult): HostResponse {.requires: r.status == FetchError.None.} =
  ## Select a completed protocol outcome only after checking success.
  r.completed

proc fetchValue(gas: MachineGas, registers: RegisterFile, memory: Memory,
    bytes: openArray[byte], present: bool, selector, base, rate: uint64,
        limit: MemoryByteLimit): FetchResult =
  ## Apply a selected value or absence after the wrapper chooses its selector and fixed prices.
  ## Caller bytes must remain stable during this synchronous call; the source memory is immutable.
  if uint64(registers[10]) != selector:
    # A known but unimplemented selector must never become an unknown/absent-value response.
    return FetchResult(status: FetchError.UnsupportedSelector)
  if pageImage(memory, PageIndex(0)).error != MachineError.None:
    # Reject default owners even when gas is insufficient or the clipped copy would be empty.
    return FetchResult(status: FetchError.InvalidMemory)
  let requested = uint64(registers[9])
  # Splitting before multiplication computes ceil(rate*z/1024) for all uint64 z without overflow.
  # Private callers use rate <= 400 and base <= 390, so each complete cost fits uint64.
  let cost = base + (requested div 1024) * rate + ((requested mod 1024) * rate + 1023) div 1024
  if uint64(gas) < cost:
    # General-host underfunding takes precedence over guest memory and local copy-size checks.
    return FetchResult(status: FetchError.None, completed: HostResponse(
      action: HostAction.OutOfGas, gas: MachineGas(0), gasDeficit: GasDeficit(0),
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

proc fetchEntropyResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory,
    entropy: FetchEntropy, limit: MemoryByteLimit): FetchResult =
  ## Fetch selector 1 with present 32-byte entropy: fixed cost 103, independent of requested length.
  ## Dispatcher supplies the invocation's entropy and host identifier 2; absence is outside this API.
  fetchValue(gas, registers, memory, array[32, byte](entropy), true, 1, 103, 0, limit)

proc fetchTraceResponse*(gas: MachineGas, registers: RegisterFile, memory: Memory,
    trace: openArray[byte], limit: MemoryByteLimit): FetchResult =
  ## Fetch selector 2 with a present trace (including empty): cost 80 + ceil(96*r9/1024).
  ## This does not select invocation context. A local failure must be propagated by the dispatcher,
  ## never converted to HostAction.Panic. Fallible executeWithHost callbacks can return hostFailure(error).
  fetchValue(gas, registers, memory, trace, true, 2, 80, 96, limit)

proc fetchContextResponse*(context: FetchContext, gas: MachineGas, registers: RegisterFile,
    memory: Memory, limit: MemoryByteLimit): FetchResult =
  ## Select configured parameters and invocation values for host identifier 2; remaining selectors refuse.
  ## Values >= 16 are protocol-unknown selectors (cost 80, NONE), not unknown host identifiers.
  ## Invalid context/memory and local copy caps remain typed failures for fallible host dispatch.
  let owner = context.data
  if owner == nil:
    # Default handles cannot masquerade as a valid invocation with both values absent.
    return FetchResult(status: FetchError.InvalidContext)
  let selector = uint64(registers[10])
  case selector
  of 0:
    # Parameters are always present in a configured invocation; no NONE fallback is defined.
    let parameters = context.parameterData
    if parameters == nil:
      return FetchResult(status: FetchError.InvalidContext)
    fetchValue(gas, registers, memory, parameters.bytes, true, 0, 390, 0, limit)
  of 1:
    # Entropy is exactly 32 bytes when present; absence retains selector 1's fixed charge.
    fetchValue(gas, registers, memory, array[32, byte](owner.entropy),
      owner.entropyPresence == FetchPresence.Present, 1, 103, 0, limit)
  of 2:
    # Trace absence still charges the requested length at selector 2's rate.
    fetchValue(gas, registers, memory, owner.trace,
      owner.tracePresence == FetchPresence.Present, 2, 80, 96, limit)
  of 3, 4, 5, 6:
    # Any-item selectors use r11/r12; current-item selectors use the captured item and r11.
    let inputs = context.inputData
    let extrinsic = selector == 3 or selector == 4
    let current = selector == 4 or selector == 6
    let base = (if extrinsic: 85'u64 else: 171'u64)
    let rate = (if extrinsic: 96'u64 else: 0'u64)
    if inputs == nil:
      # No captured inputs is a valid absent invocation context, retaining the selected price.
      return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
    let presence = (if extrinsic: inputs.values.extrinsicsPresence else: inputs.values.importsPresence)
    if presence == FetchPresence.Absent or
        (current and inputs.values.currentPresence == FetchPresence.Absent):
      # Missing current-item identity affects only selectors 4/6, not arbitrary item selection.
      return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
    let item = (if current: uint64(inputs.values.current) else: uint64(registers[11]))
    let index = (if current: uint64(registers[11]) else: uint64(registers[12]))
    if extrinsic:
      # Compare both guest indices at full width before narrowing or accessing a nested descriptor.
      if item >= uint64(inputs.values.extrinsics.len):
        return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
      if index >= uint64(inputs.values.extrinsics[int(item)].len):
        return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
      return fetchValue(gas, registers, memory, inputs.values.extrinsics[int(item)][int(index)],
        true, selector, base, rate, limit)
    # Imported segments are returned raw, without their commitment, proof or a length prefix.
    if item >= uint64(inputs.values.imports.len):
      return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
    if index >= uint64(inputs.values.imports[int(item)].len):
      return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
    fetchValue(gas, registers, memory,
      array[4104, byte](inputs.values.imports[int(item)][int(index)]),
      true, selector, base, rate, limit)
  of 7:
    # The package is encoded once during capture; item registers do not select or alter it.
    let package = context.packageData
    if package == nil:
      # Absence retains the requested-length price even though no memory bytes will be copied.
      return fetchValue(gas, registers, memory, [], false, 7, 85, 96, limit)
    fetchValue(gas, registers, memory, package.encoded, true, 7, 85, 96, limit)
  of 10, 11, 12:
    # Metadata is encoded once at capture; requests borrow only the selected fixed-buffer extent.
    let package = context.packageData
    let base = (if selector == 10: 111'u64 elif selector == 11: 317'u64 else: 250'u64)
    if package == nil:
      # All metadata selectors retain their own fixed price when the package is absent.
      return fetchValue(gas, registers, memory, [], false, selector, base, 0, limit)
    if selector == 10:
      # Context uses the existing canonical C.2 codec and ignores both item registers.
      return fetchValue(gas, registers, memory,
        package.context.toOpenArray(0, package.contextLength - 1), true, selector, base, 0, limit)
    if selector == 11:
      # One count prefix precedes the ordered fixed-width summaries, without per-item framing.
      return fetchValue(gas, registers, memory,
        package.summaries.toOpenArray(0, package.itemCount * 62), true, selector, base, 0, limit)
    let index = uint64(registers[11])
    if index >= uint64(package.itemCount):
      # Test the full unsigned register before narrowing or multiplying the item index.
      return fetchValue(gas, registers, memory, [], false, selector, base, 0, limit)
    let start = 1 + int(index) * 62
    fetchValue(gas, registers, memory, package.summaries.toOpenArray(start, start + 61),
      true, selector, base, 0, limit)
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
  of 14, 15:
    # List and individual records share one encoding but retain distinct requested-length prices.
    let accumulation = context.accumulationData
    let base = (if selector == 14: 287'u64 else: 355'u64)
    let rate = (if selector == 14: 400'u64 else: 344'u64)
    if accumulation == nil:
      # Absence is charged even with invalid indices or pointers, using an empty natural interval.
      return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
    if selector == 14:
      # The complete compact-count-prefixed list ignores both item registers.
      return fetchValue(gas, registers, memory, accumulation.bytes, true, selector, base, rate, limit)
    let index = uint64(registers[11])
    if index >= uint64(accumulation.spans.len):
      # Full-width comparison precedes narrowing and slicing; r12 is unused.
      return fetchValue(gas, registers, memory, [], false, selector, base, rate, limit)
    let span = accumulation.spans[int(index)]
    fetchValue(gas, registers, memory,
      accumulation.bytes.toOpenArray(span.start, span.start + span.length - 1),
      true, selector, base, rate, limit)
  else:
    # All sixteen defined selectors are handled; remaining values use protocol-unknown absence.
    fetchValue(gas, registers, memory, [], false, selector, 80, 0, limit)
