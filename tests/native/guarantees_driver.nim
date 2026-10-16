## Trusted bounded fixture adapter for independent guarantee fields and immutable owner checks.
import std/[os, strutils]
import ../../src/codec/[guarantees, report_owned, owned, bounded, assurances]

# Decode trusted bounded public fixture text; a dash preserves an empty field token.
proc unhex(text: string): seq[byte] =
  # Empty tokens have no byte pair to inspect.
  if text == "-": return @[]
  doAssert text.len mod 2 == 0 and text.len <= 4*1024*1024
  result = newSeq[byte](text.len div 2)
  # Parse complete pairs into independently owned adapter input bytes.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

# Render public exact wire fields without using the guarantee encoder as a semantic oracle.
proc hex(bytes: openArray[byte]): string =
  # Whitespace protocols need a real token for an empty field.
  if bytes.len == 0: return "-"
  # Each exact identity byte becomes two lowercase hexadecimal digits.
  for value in bytes: result.add(toHex(value, 2).toLowerAscii())

# Construct the caller's explicit chain domains and retained-byte ceiling.
proc config(parts: seq[string]): GuaranteeConfig =
  GuaranteeConfig(cores: CoreCount(parseBiggestUInt(parts[1])),
    validators: ValidatorCount(parseBiggestUInt(parts[2])), maxBytes: ByteLimit(parseBiggestUInt(
        parts[3])))

# Build typed sources independently from the new wrapper decoder; child report ownership is an existing API.
proc records(parts: seq[string]): seq[Guarantee] =
  let count = parseInt(parts[5])
  doAssert count >= 0 and count <= 342
  result = newSeq[Guarantee](count)
  var cursor = 6
  # All wrapper fields are explicit source tokens rather than decoded guarantees.
  for i in 0..<count:
    let wire = unhex(parts[cursor]); inc cursor
    let captured = decodeOwnedReport(wire, 341)
    doAssert captured.error == OwnershipError.None
    result[i].report = captured.value
    let slot = parseBiggestUInt(parts[cursor]); inc cursor
    doAssert slot <= uint64(high(uint32))
    result[i].slot = GuaranteeSlot(slot)
    let credentials = parseInt(parts[cursor]); inc cursor
    doAssert credentials in 0..4
    result[i].credentialCount = credentials
    # Four-field sources intentionally test the encoder's count rejection without indexing its fixed three slots.
    for j in 0..<credentials:
      let validator = parseInt(parts[cursor]); inc cursor
      let signature = unhex(parts[cursor]); inc cursor
      doAssert validator in 0..65535 and signature.len == 64
      if j < 3:
        # Only representable slots are copied; preflight must reject a declared fourth credential.
        result[i].credentials[j].validator = GuarantorIndex(validator)
        var fixed: array[64, byte]
        for k in 0..<64: fixed[k] = signature[k] # Owned exact-width credential construction.
        result[i].credentials[j].signature = GuaranteeSignature(fixed)
  doAssert cursor == parts.len

# Observe every wrapper field plus immutable child bytes, independently from wrapper re-encoding.
proc fields(owner: OwnedGuarantees, count: int): string =
  result = $count
  # Getter results copy fixed arrays and retain only private immutable report handles.
  for i in 0..<count:
    let selected = guaranteeAt(owner, i)
    doAssert selected.error == GuaranteeError.None
    var value = selected.value
    let info = ownedReportInfo(value.report)
    doAssert info.error == OwnershipError.None
    var report = newSeq[byte](info.value.consumed)
    doAssert encodeOwnedReport(value.report, report).error == OwnershipError.None
    result.add(" " & hex(report) & " " & $uint32(value.slot) & " " & $value.credentialCount)
    # Print nominal indices and every opaque signature octet directly from copied fields.
    for j in 0..<value.credentialCount:
      result.add(" " & $uint16(value.credentials[j].validator) & " " &
        hex(array[64, byte](value.credentials[j].signature)))
    let oldSlot = value.slot
    let oldSignature = value.credentials[0].signature
    value.slot = GuaranteeSlot(0)
    value.credentials[0].signature = GuaranteeSignature(default(array[64, byte]))
    let again = guaranteeAt(owner, i)
    # Mutating a copied getter result cannot change retained validated metadata.
    doAssert uint32(again.value.slot) == uint32(oldSlot)
    doAssert array[64, byte](again.value.credentials[0].signature) == array[64, byte](oldSignature)

# Exercise one request with full failure-atomicity and source-lifetime assertions.
proc request(line: string) =
  let parts = line.splitWhitespace()
  doAssert parts.len >= 5
  let limits = config(parts)
  # Encoder sources are constructed field by field rather than through the new decoder.
  if parts[0] == "E":
    let capacity = parseInt(parts[4]); doAssert capacity in 0..4194304
    let values = records(parts)
    var output = newSeq[byte](capacity)
    for i in 0..<output.len: output[i] = 0xA5 # Whole-buffer sentinels detect late partial writes.
    let encoded = encodeGuarantees(values, limits, output)
    if encoded.error != GuaranteeError.None:
      # Every failure preserves the entire caller byte destination.
      for value in output: doAssert value == 0xA5
      echo ($encoded.error).toLowerAscii()
    else:
      # Unused output suffix is not part of the successful wire prefix.
      for i in encoded.value..<output.len: doAssert output[i] == 0xA5
      echo hex(output.toOpenArray(0, encoded.value-1))
  else:
    doAssert parts[0] == "D" and parts.len == 5
    var input = unhex(parts[4])
    let parsed = decodeGuarantees(input, limits)
    if parsed.error != GuaranteeError.None:
      # Failure-only results must not expose a partial owner, count or source cursor.
      echo ($parsed.error).toLowerAscii()
    else:
      let count = parsed.value.count
      let consumed = parsed.value.consumed
      let owner = parsed.value.owner
      # Retained guarantees must survive destruction/mutation of every caller source byte, including trailing input.
      for i in 0..<input.len: input[i] = 0
      doAssert guaranteeAt(owner, -1).error == GuaranteeError.InvalidIndex
      doAssert guaranteeAt(owner, count).error == GuaranteeError.InvalidIndex
      let observed = fields(owner, count)
      var wire = newSeq[byte](consumed+7)
      for i in 0..<wire.len: wire[i] = 0xA5 # Extra output capacity must remain untouched.
      let written = encodeOwnedGuarantees(owner, wire)
      doAssert written.error == GuaranteeError.None and written.value == consumed
      for i in consumed..<wire.len: doAssert wire[i] == 0xA5 # Prefix consumption is exact.
      echo $count & " " & $consumed & " " & observed

# Every request shares one process but retains no state or wire ownership from another request.
for line in lines(paramStr(1)):
  # Empty physical lines contain no trusted test request.
  if line.len > 0: request(line)
