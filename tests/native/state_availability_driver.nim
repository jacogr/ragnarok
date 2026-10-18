# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted independent typed-source and retained-child observer for chapter 10.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/[state_availability, guarantees, report_owned, owned, state_trie, bounded, assurances]

## Preserve empty malformed report/input tokens without inventing protocol bytes.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty input remains expressible independently from absent slots.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Fixed signatures and report snapshots preserve exact source octets.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Trusted transport supplies complete lowercase hex byte tokens.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Observe full bytes with leading zeroes, rather than reinterpreting signatures as integers.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # One token is needed for an empty logical byte sequence.
  result = ""
  # Render each opaque octet independently.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii()) # Preserve octet order and width.

## Parse a complete trusted decimal token using the non-throwing interface.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number
## Trusted source sequence counts must fit native indexing before conversion.
proc integer(text: string): int =
  let number = unsigned(text)
  assert number <= uint64(high(int))
  int(number)

## Trusted chain, child-byte, present-count and complete-parent ceilings retain separate domains.
proc config(parts: seq[string]): AvailabilityConfig =
  AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(unsigned(parts[1])),
    validators: ValidatorCount(unsigned(parts[2])), maxBytes: ByteLimit(unsigned(
        parts[3]))),
    maxPresent: ElementLimit(unsigned(parts[4])), maxBytes: ByteLimit(unsigned(
        parts[5])))

## Construct guarantees from independent report/slot/credential fields, without using the new guarantee decoder.
proc source(parts: seq[string]): seq[AvailabilityAssignment] =
  result = newSeq[AvailabilityAssignment](integer(parts[6]))
  var cursor = 7
  # Each core position is represented explicitly, including every absent slot.
  for i in 0..<result.len:
    let present = parts[cursor] == "1"
    inc cursor
    if present:
      let registered = AssignmentSlot(unsigned(parts[cursor]))
      let report = decodeOwnedReport(unhex(parts[cursor+1]), 341)
      var value = Guarantee(slot: GuaranteeSlot(unsigned(parts[cursor+2])),
          credentialCount: integer(parts[cursor+3]))
      if report.error == OwnershipError.None: value.report = report.value # Invalid raw report sources retain a default owner for rejection tests.
      cursor += 4
      # Consume even oversized source credentials while keeping the fixed array's accesses bounded.
      for j in 0..<value.credentialCount:
        let index = GuarantorIndex(unsigned(parts[cursor]))
        let signature = unhex(parts[cursor+1])
        assert signature.len == 64
        if j < 3:
          var bytes = default(array[64, byte])
          for k in 0..<64: bytes[k] = signature[k] # Independent exact signature source bytes.
          value.credentials[j] = GuaranteeCredential(validator: index,
              signature: GuaranteeSignature(bytes))
        cursor += 2
      result[i] = presentAssignment(value, registered)
    else:
      result[i] = absentAssignment() # Absence has no report or timestamps to parse.
  assert cursor == parts.len

## Observe exact child report bytes through its retained immutable owner and fixed guarantee fields separately.
proc observed(value: AvailabilityAssignment): string =
  if not value.present: return "0" # No inactive guarantee/timestamp access on absence.
  let info = ownedReportInfo(value.guarantee.report)
  assert info.error == OwnershipError.None
  var report = newSeq[byte](info.value.consumed)
  assert encodeOwnedReport(value.guarantee.report, report).error == OwnershipError.None
  result = "1 " & $uint32(value.registered) & " " & hex(report) & " " & $uint32(
      value.guarantee.slot) & " " & $value.guarantee.credentialCount
  # Credential order, E2 indices and every opaque signature octet remain visible independently.
  for i in 0..<value.guarantee.credentialCount:
    let credential = value.guarantee.credentials[i]
    result.add(" " & $uint16(credential.validator) & " " & hex(array[64, byte](
        credential.signature)))

## Execute one independent source/root or prefix-decoding observation with failure-only output.
proc request(parts: seq[string]) =
  let policy = config(parts)
  case parts[0]
  of "V", "R":
    # Input report owners are captured with the broad profile so stricter source-policy checks remain testable.
    var values = source(parts)
    let encoded = availabilityStateEntry(values, policy)
    if encoded.error != AvailabilityError.None:
      echo ($encoded.error).toLowerAscii() # No partial entry or child after a late failure.
    else:
      # Destroy source values before observing encoded bytes or their partial mapping commitment.
      for i in 0..<values.len: values[i] = absentAssignment()
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        # A C(10)-only commitment is not a full JAM state root.
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(1)))
        assert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))
  of "D":
    # Child report snapshots must survive destruction of the original complete parent wire.
    var input = unhex(parts[6])
    let decoded = decodeAvailabilityState(input, policy)
    if decoded.error != AvailabilityError.None:
      echo ($decoded.error).toLowerAscii() # Failure publishes no earlier owner or consumed progress.
    else:
      for i in 0..<input.len: input[i] = 0 # Subsequent observations require private parent/child storage.
      let info = availabilityInfo(decoded.value.snapshot)
      assert info.error == AvailabilityError.None
      var output = $decoded.value.consumed & " " & $info.value.cores & " " & $info.value.present
      # Each copied optional value is extracted through its original retained core owner.
      for i in 0..<info.value.cores:
        let item = availabilityAt(decoded.value.snapshot, AssignmentCoreIndex(i))
        assert item.error == AvailabilityError.None
        output.add(" " & observed(item.value))
      echo output
  else: assert false # Unknown trusted operations cannot select another schema.

# Each request releases independent source/snapshot lifetimes after all observations.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Blank transport lines have no protocol operation.
