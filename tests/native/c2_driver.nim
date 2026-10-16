## Independent source construction and copied-field observations for the remaining C.2 records.
import std/[os, strutils]
import ../../src/codec/[c2_records, bounded, composite, work_digest, work_report, assurances]

# Require complete success before reading any fixed fields, owner or consumed/written extent.
proc checked[T](parsed: RecordResult[T]): T =
  doAssert parsed.error == RecordError.None
  parsed.value

# Trusted fixture hex becomes mutable caller-owned bytes that can be destroyed after decoding.
proc unhex(text: string): seq[byte] =
  # Preserve empty blobs as a single transport token.
  if text == "-": return @[]
  doAssert text.len mod 2 == 0 and text.len <= 2*1024*1024
  result = newSeq[byte](text.len div 2)
  # Each source octet has an independently owned mutable lifetime.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Read exactly one trusted fixed identity without silently padding or dropping fields.
proc fixed[N: static int](text: string): array[N, byte] =
  let bytes = unhex(text)
  doAssert bytes.len == N
  # Fixed field sources are independently named values, never native decoded parent bytes.
  for i in 0..<N: result[i] = bytes[i]

# Exact field observations preserve byte order and leading zeroes without interpreting cryptographic validity.
proc hex(bytes: openArray[byte]): string =
  # Empty payloads remain visible to the independent oracle.
  if bytes.len == 0: return "-"
  # Each fixed identity/payload is copied into textual observation storage.
  for value in bytes: result.add(toHex(value, 2).toLowerAscii())

# Parse explicit uint64 fixture domains before intentional narrowing into trusted typed source fields.
proc number(text: string): uint64 = uint64(parseBiggestUInt(text))

# Decoder and encoder record policies share four explicitly named resource ceilings.
proc limits(parts: seq[string]): OperandLimits =
  OperandLimits(outputBytes: ByteLimit(number(parts[3])), authBytes: ByteLimit(number(parts[4])),
    totalBlobBytes: ByteLimit(number(parts[5])), maxBytes: ByteLimit(number(parts[6])))

# Every destination begins with canaries so whole-output failure and spare suffix preservation are checked.
proc output(capacity: int): seq[byte] =
  doAssert capacity in 0..2097152
  result = newSeq[byte](capacity)
  # Canary initialization includes bytes beyond the eventual successful prefix.
  for i in 0..<capacity: result[i] = 0xA5

# Failure contains a reason only; success prints exact independently expected bytes and preserves spare capacity.
proc emitted(parsed: RecordResult[int], bytes: openArray[byte]) =
  # No failed preflight may write an earlier tag, hash or memo field.
  if parsed.error != RecordError.None:
    # Verify the entire supplied destination, not just the successful-prefix capacity.
    for value in bytes: doAssert value == 0xA5
    echo ($parsed.error).toLowerAscii()
  else:
    # The completed frame cannot overwrite unrelated suffix capacity.
    for i in parsed.value..<bytes.len: doAssert bytes[i] == 0xA5
    echo hex(bytes.toOpenArray(0, parsed.value-1))

# Copy all availability roles to independent field tokens rather than relying on a same-codec wire round trip.
proc fields(value: AvailabilitySpec): string =
  hex(value.packageHash.bytes) & " " & $uint32(value.bundleLength) & " " & hex(
      value.erasureRoot.bytes) &
    " " & $uint16(value.erasureShards) & " " & hex(value.segmentRoot.bytes) & " " & $uint16(
        value.segmentCount)

# Complete fixed transfer observations retain both service roles, unsigned balance, every memo byte and E8 gas.
proc fields(value: DeferredTransfer): string =
  $uint32(value.source) & " " & $uint32(value.destination) & " " & $uint64(value.amount) &
    " " & hex(array[128, byte](value.memo)) & " " & $uint64(value.gas)

# Observe complete operand metadata and payload copies after destroying the original input buffer.
proc fields(owner: OwnedOperand): string =
  let info = checked(operandInfo(owner))
  var payload = "-"
  # Only success work results authorize a payload length or extraction call.
  if info.output.kind == WorkKind.Success:
    var bytes = output(info.output.length+3)
    doAssert checked(copyOperandOutput(owner, bytes)) == info.output.length
    # Payload extraction preserves spare suffix capacity.
    for i in info.output.length..<bytes.len: doAssert bytes[i] == 0xA5
    payload = hex(bytes.toOpenArray(0, info.output.length-1))
    # Mutation of an extracted copy cannot change the retained private snapshot.
    for i in 0..<info.output.length: bytes[i] = 0
    doAssert checked(copyOperandOutput(owner, bytes)) == info.output.length
    doAssert hex(bytes.toOpenArray(0, info.output.length-1)) == payload
  else:
    # An error is a valid output alternative, but never a fabricated empty success payload.
    var empty: seq[byte]
    doAssert copyOperandOutput(owner, empty).error == RecordError.NoPayload
  var trace = output(info.authBytes+3)
  doAssert checked(copyOperandTrace(owner, trace)) == info.authBytes
  # The trace extractor must also preserve all unrelated destination capacity.
  for i in info.authBytes..<trace.len: doAssert trace[i] == 0xA5
  result = hex(info.packageHash.bytes) & " " & hex(info.segmentRoot.bytes) & " " & hex(
      info.authorizer.bytes) &
    " " & hex(array[32, byte](info.payloadHash)) & " " & $uint64(info.gas) & " " & $ord(
        info.output.kind) &
      " " & payload & " " & hex(trace.toOpenArray(0, info.authBytes-1))
  var bytes = output(info.consumed+3)
  let broad = OperandLimits(outputBytes: ByteLimit(high(uint64)), authBytes: ByteLimit(high(uint64)),
    totalBlobBytes: ByteLimit(high(uint64)), maxBytes: ByteLimit(high(uint64)))
  doAssert checked(encodeOwnedOperand(owner, broad, bytes)) == info.consumed
  result.add(" " & hex(bytes.toOpenArray(0, info.consumed-1)))
  # Re-emission is supplementary to independent field observations and must preserve suffix capacity.
  for i in info.consumed..<bytes.len: doAssert bytes[i] == 0xA5

# Capture a complete record, destroy its original bytes, then print only independently observable fields/progress.
proc decodeRequest(parts: seq[string]) =
  let policy = limits(parts)
  let config = AvailabilityConfig(cores: CoreCount(number(parts[2])), maxBytes: policy.maxBytes)
  var input = unhex(parts[7])
  case parts[1]
  of "A":
    # Standalone availability must consume only 104 bytes even when a report context follows.
    let parsed = decodeAvailability(input, config)
    if parsed.error != RecordError.None: echo ($parsed.error).toLowerAscii() # No copied fields exist on failure.
    else:
      # Fixed fields must outlive arbitrary caller-buffer mutation.
      for i in 0..<input.len: input[i] = 0
      echo $parsed.value.consumed & " " & fields(parsed.value.value)
  of "T":
    # Standalone transfer retains its own required outer tag one and complete fixed memo.
    let parsed = decodeTransfer(input, policy.maxBytes)
    if parsed.error != RecordError.None: echo ($parsed.error).toLowerAscii() # No partial memo or service identity escapes.
    else:
      # The entire transfer is copied by value, without a heap snapshot requirement.
      for i in 0..<input.len: input[i] = 0
      echo $parsed.value.consumed & " " & fields(parsed.value.value)
  of "O":
    # Operand ownership is granted only after its final trace and all resource policies pass.
    let parsed = decodeOperand(input, policy)
    if parsed.error != RecordError.None: echo ($parsed.error).toLowerAscii() # No partial owner/cursor is accessible.
    else:
      # Retained coordinates must bind to private bytes rather than these overwritten caller bytes.
      for i in 0..<input.len: input[i] = 0
      echo $parsed.value.consumed & " " & fields(parsed.value.owner)
  of "I":
    # Union decoding uses the existing outer tags, with no extra serialized wrapper.
    let parsed = decodeAccumulationInput(input, policy)
    if parsed.error != RecordError.None: echo ($parsed.error).toLowerAscii() # Failure cannot select either application value.
    else:
      # Both selected alternatives must retain independent lifetimes after original input mutation.
      for i in 0..<input.len: input[i] = 0
      case parsed.value.value.kind
      of AccumulationKind.Operand: echo "0 " & $parsed.value.consumed & " " & fields(
          parsed.value.value.operand) # Selected owner only.
      of AccumulationKind.Transfer: echo "1 " & $parsed.value.consumed & " " & fields(
          parsed.value.value.transfer) # Selected fixed copy only.
  else: doAssert false # Unknown trusted request schemas must not choose a production decoder implicitly.

# Construct typed sources directly from independent named fixture fields; never use the record decoder to prepare encoding.
proc encodeRequest(parts: seq[string]) =
  let policy = limits(parts)
  var bytes = output(parseInt(parts[7]))
  case parts[1]
  of "A":
    # Fixed availability source fields are independently named and retain separate nominal hash/root roles.
    let value = AvailabilitySpec(packageHash: PackageHash(bytes: fixed[32](parts[8])),
      bundleLength: BundleLength(number(parts[9])), erasureRoot: ErasureRoot(bytes: fixed[32](parts[
          10])),
      erasureShards: ErasureShards(number(parts[11])), segmentRoot: SegmentRoot(bytes: fixed[32](
          parts[12])),
      segmentCount: SegmentCount(number(parts[13])))
    emitted(encodeAvailability(value, AvailabilityConfig(cores: CoreCount(number(parts[2])),
        maxBytes: policy.maxBytes), bytes), bytes)
  of "T", "UT":
    # Transfer source fields have a fixed memo and no operand-only payload policy.
    let value = DeferredTransfer(source: ServiceIndex(number(parts[8])), destination: ServiceIndex(
        number(parts[9])),
      amount: TransferBalance(number(parts[10])), memo: TransferMemo(fixed[128](parts[11])),
          gas: Gas(number(parts[12])))
    if parts[1] == "T": emitted(encodeTransfer(value, policy.maxBytes, bytes),
        bytes) # Standalone tagged transfer encoding.
    else:
      # The union encoder emits exactly the same tagged transfer bytes.
      emitted(encodeAccumulationInput(AccumulationSource(kind: AccumulationKind.Transfer,
          transfer: value), policy, bytes), bytes)
  of "O", "UO":
    # All result/trace sources are separate logical sequences, independent of production spans/owners.
    let tag = parseInt(parts[13])
    doAssert tag in 0..6
    var work: OperandOutput
    if tag == 0: work = OperandOutput(kind: WorkKind.Success, payload: unhex(parts[
        14])) # Only success owns a source payload.
    else:
      # Work error alternatives contain their tag alone, never a default byte sequence.
      work = OperandOutput(kind: WorkKind(tag))
    let value = AccumulationOperand(packageHash: PackageHash(bytes: fixed[32](parts[8])),
      segmentRoot: SegmentRoot(bytes: fixed[32](parts[9])), authorizer: AuthorizerHash(bytes: fixed[
          32](parts[10])),
      payloadHash: PayloadHash(fixed[32](parts[11])), gas: Gas(number(parts[12])), output: work,
          authTrace: unhex(parts[15]))
    if parts[1] == "O": emitted(encodeOperand(value, policy, bytes),
        bytes) # Direct operand source encoding with one outer zero.
    else:
      # The union encoder adds no discriminator beyond that same operand tag zero.
      emitted(encodeAccumulationInput(AccumulationSource(kind: AccumulationKind.Operand,
          operand: value), policy, bytes), bytes)
  else: doAssert false # Unknown trusted source schemas cannot bypass nominal construction.

# Each request owns its temporary input/output and releases snapshots after the complete observation.
for line in lines(paramStr(1)):
  # Empty batch lines contain no record operation.
  if line.len > 0:
    let parts = line.splitWhitespace()
    if parts[0] == "D": decodeRequest(parts) # Untrusted record framing and copied-field observation.
    else: encodeRequest(parts) # Independent logical source construction and atomic output.
