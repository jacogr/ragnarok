# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted bounded fixture adapter for independent guarantee fields and immutable owner checks.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/[guarantees, report_owned, owned, bounded, assurances]

# Decode trusted bounded public fixture text; a dash preserves an empty field token.
proc unhex(text: string): seq[byte] {.raises.} =
  # Empty tokens have no byte pair to inspect.
  if text == "-": return @[]
  assert text.len mod 2 == 0 and text.len <= 4*1024*1024
  result = newSeq[byte](text.len div 2)
  # Parse complete pairs into independently owned adapter input bytes.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Validate the complete trusted hex alphabet before checked conversion.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

# Render public exact wire fields without using the guarantee encoder as a semantic oracle.
proc hex(bytes: openArray[byte]): string =
  # Whitespace protocols need a real token for an empty field.
  if bytes.len == 0: return "-"
  result = ""
  # Each exact identity byte becomes two lowercase hexadecimal digits.
  for value in bytes: result.add(toHex(int(value), 2).toLowerAscii())

# Parse unsigned fixture numbers without narrowing their complete uint64 domain through signed int.
proc unsigned(text: string): uint64 =
  var value: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, value) == text.len
  value

# Construct the caller's explicit chain domains and retained-byte ceiling.
proc config(parts: seq[string]): GuaranteeConfig =
  GuaranteeConfig(cores: CoreCount(unsigned(parts[1])),
    validators: ValidatorCount(unsigned(parts[2])), maxBytes: ByteLimit(unsigned(parts[3])))

# Build typed sources independently from the new wrapper decoder; child report ownership is an existing API.
proc records(parts: seq[string]): seq[Guarantee] {.raises.} =
  let count = parseInt(parts[5])
  assert count >= 0 and count <= 342
  result = newSeq[Guarantee](count)
  var cursor = 6
  # All wrapper fields are explicit source tokens rather than decoded guarantees.
  for i in 0..<count:
    let wire = unhex(parts[cursor]); inc cursor
    let captured = decodeOwnedReport(wire, 341)
    assert captured.error == OwnershipError.None
    result[i].report = captured.value
    let slot = unsigned(parts[cursor]); inc cursor
    assert slot <= uint64(high(uint32))
    result[i].slot = GuaranteeSlot(slot)
    let credentials = parseInt(parts[cursor]); inc cursor
    assert credentials in 0..4
    result[i].credentialCount = credentials
    # Four-field sources intentionally test the encoder's count rejection without indexing its fixed three slots.
    for j in 0..<credentials:
      let validator = parseInt(parts[cursor]); inc cursor
      let signature = unhex(parts[cursor]); inc cursor
      assert validator in 0..65535 and signature.len == 64
      if j < 3:
        # Only representable slots are copied; preflight must reject a declared fourth credential.
        result[i].credentials[j].validator = GuarantorIndex(validator)
        var fixed: array[64, byte] = default(array[64, byte])
        for k in 0..<64: fixed[k] = signature[k] # Owned exact-width credential construction.
        result[i].credentials[j].signature = GuaranteeSignature(fixed)
  assert cursor == parts.len

# Observe every wrapper field plus immutable child bytes, independently from wrapper re-encoding.
proc fields(owner: OwnedGuarantees, count: int): string =
  result = $count
  # Getter results copy fixed arrays and retain only private immutable report handles.
  for i in 0..<count:
    let selected = guaranteeAt(owner, i)
    assert selected.error == GuaranteeError.None
    var value = selected.value
    let info = ownedReportInfo(value.report)
    assert info.error == OwnershipError.None
    var report = newSeq[byte](info.value.consumed)
    assert encodeOwnedReport(value.report, report).error == OwnershipError.None
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
    assert uint32(again.value.slot) == uint32(oldSlot)
    assert array[64, byte](again.value.credentials[0].signature) == array[64, byte](oldSignature)

# Observe a standalone copied record's exact child bytes and fixed credential fields.
proc standaloneFields(value: Guarantee): string =
  let info = ownedReportInfo(value.report)
  assert info.error == OwnershipError.None
  var report = newSeq[byte](info.value.consumed)
  assert encodeOwnedReport(value.report, report).error == OwnershipError.None
  result = hex(report) & " " & $uint32(value.slot) & " " & $value.credentialCount
  # Observe every signature octet independently of standalone wrapper encoding.
  for i in 0..<value.credentialCount:
    result.add(" " & $uint16(value.credentials[i].validator) & " " &
        hex(array[64, byte](value.credentials[i].signature)))

# Exercise one request with full failure-atomicity and source-lifetime assertions.
proc request(line: string) {.raises.} =
  let parts = line.splitWhitespace()
  assert parts.len >= 5
  let limits = config(parts)
  # Encoder sources are constructed field by field rather than through the new decoder.
  if parts[0] in ["E", "V", "M"]:
    let capacity = parseInt(parts[4]); assert capacity in 0..4194304
    let values = records(parts)
    # Standalone source construction shares explicit fields, never the wrapper decoder.
    if parts[0] == "V" or parts[0] == "M":
      assert values.len == 1
      if parts[0] == "V":
        # The fresh byte result has no external destination capacity or alias contract.
        let encoded = encodeGuaranteeValue(values[0], limits)
        if encoded.error == GuaranteeError.None: echo hex(encoded.value) # Exact standalone bytes.
        else: echo ($encoded.error).toLowerAscii() # Full preflight precedes allocation.
      else:
        # Measurement returns only a validated complete standalone extent.
        let measured = measureGuarantee(values[0], limits)
        if measured.error == GuaranteeError.None: echo measured.value # Successful byte count.
        else: echo ($measured.error).toLowerAscii() # No size after source failure.
      return
    var output = newSeq[byte](capacity)
    for i in 0..<output.len: output[i] = 0xA5 # Whole-buffer sentinels detect late partial writes.
    let encoded = encodeGuarantees(values, limits, output)
    if encoded.error != GuaranteeError.None:
      # Every failure preserves the entire caller byte destination.
      for value in output: assert value == 0xA5
      echo ($encoded.error).toLowerAscii()
    else:
      # Unused output suffix is not part of the successful wire prefix.
      for i in encoded.value..<output.len: assert output[i] == 0xA5
      echo hex(output.toOpenArray(0, encoded.value-1))
  elif parts[0] == "I":
    # Parent framing can inspect without materializing report owners.
    let scanned = inspectGuarantees(unhex(parts[4]), limits)
    if scanned.error == GuaranteeError.None: echo $scanned.value.count & " " &
        $scanned.value.consumed
    else: echo ($scanned.error).toLowerAscii() # Failed scans expose no progress.
  elif parts[0] == "S" or parts[0] == "J":
    var input = unhex(parts[4])
    if parts[0] == "J":
      # Standalone inspection has no outer count and exposes its nominal report core.
      let scanned = inspectGuarantee(input, limits)
      if scanned.error == GuaranteeError.None: echo $uint64(scanned.value.core) & " " &
          $scanned.value.consumed
      else: echo ($scanned.error).toLowerAscii() # No core or extent from failed framing.
    else:
      # Successful standalone records retain their child after all caller bytes change.
      let parsed = decodeGuarantee(input, limits)
      if parsed.error == GuaranteeError.None:
        for octet in input.mitems: octet = 0 # Erase the entire original and trailing prefix.
        echo $parsed.value.consumed & " " & standaloneFields(parsed.value.value)
      else: echo ($parsed.error).toLowerAscii() # No partially captured child after failure.
  else:
    assert parts[0] == "D" and parts.len == 5
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
      assert guaranteeAt(owner, -1).error == GuaranteeError.InvalidIndex
      assert guaranteeAt(owner, count).error == GuaranteeError.InvalidIndex
      let observed = fields(owner, count)
      var wire = newSeq[byte](consumed+7)
      for i in 0..<wire.len: wire[i] = 0xA5 # Extra output capacity must remain untouched.
      let written = encodeOwnedGuarantees(owner, wire)
      assert written.error == GuaranteeError.None and written.value == consumed
      for i in consumed..<wire.len: assert wire[i] == 0xA5 # Prefix consumption is exact.
      echo $count & " " & $consumed & " " & observed

# Every request shares one process but retains no state or wire ownership from another request.
try:
  # Batch-file allocation is confined to this trusted fixture adapter.
  for line in readFile(paramStr(1)).splitLines():
    # Empty physical lines contain no trusted test request.
    if line.len > 0: request(line)
except:
  # Fixture I/O or malformed trusted text must fail rather than skip a request.
  quit 2
