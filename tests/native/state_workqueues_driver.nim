# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted independent source and immutable observation adapter for state chapters 14/15.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/[state_workqueues, report_owned, owned, state_trie, bounded]

## Empty transport tokens preserve malformed empty input or an empty source set without a fake byte.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Trusted empty token is not natural zero.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Exact byte values preserve set order without throwing trusted token parsers.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Trusted fixture transport uses two lowercase hex digits per byte.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Observe every output octet directly, retaining leading zeroes and exact child framing.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Empty fields still occupy one trusted token.
  result = ""
  # Display all supplied octets in source order.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii()) # Canonicality expectations come from Python, not this display.

## Copy trusted source hashes without sorting, deduplicating or converting them into a language set.
proc hashes(text: string): seq[PackageHash] =
  let bytes = unhex(text)
  assert bytes.len mod 32 == 0
  result = newSeq[PackageHash](bytes.len div 32)
  for i in 0..<result.len:
    for j in 0..<32: result[i].bytes[j] = bytes[i*32+j] # Preserve hostile source ordering and every fixed identity octet.

## Require a complete trusted uint64 token through the supported non-throwing interface.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number
## Trusted source cardinalities must fit native indexing before conversion or allocation.
proc integer(text: string): int =
  let number = unsigned(text)
  assert number <= uint64(high(int))
  int(number)

## Independent profile, item/dependency, child-byte and parent-byte ceilings retain separate nominal domains.
proc config(parts: seq[string]): WorkQueueConfig =
  WorkQueueConfig(epochSlots: EpochSlots(unsigned(parts[2])), cores: CoreCount(
      unsigned(parts[3])),
    perSlot: ElementLimit(unsigned(parts[4])), totalItems: ElementLimit(unsigned(
        parts[5])),
    perDependencies: ElementLimit(unsigned(parts[6])), totalDependencies: ElementLimit(
        unsigned(parts[7])),
    reportBytes: ByteLimit(unsigned(parts[8])), maxBytes: ByteLimit(unsigned(parts[9])))

## Captured child bytes remain private; re-emission observes the selected report's complete immutable prefix.
proc reportBytes(owner: OwnedReport): string =
  let info = ownedReportInfo(owner)
  assert info.error == OwnershipError.None
  var bytes = newSeq[byte](info.value.consumed)
  assert encodeOwnedReport(owner, bytes).error == OwnershipError.None
  hex(bytes)

## Compare complete independent entry bytes or one C(14/15)-only trie root, without full-state claims.
proc encoded(value: WorkQueueResult[StateEntry], root: bool) =
  if value.error != WorkQueueError.None:
    echo ($value.error).toLowerAscii() # Failure has neither default bytes nor a partial key.
  elif root:
    let result = stateTrieRoot([value.value], StateTrieLimits(items: ElementLimit(1),
        perValue: ByteLimit(high(uint64)),
      totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(1))) # Commit this component alone.
    assert result.error == StateTrieError.None
    echo hex(array[32, byte](result.value.root))
  else:
    echo hex(array[31, byte](value.value.key)) & " " & hex(
        value.value.value) # Exact source output survives caller mutation.

## Dispatch trusted source fields or hostile raw wire, publishing only complete owner observations.
proc request(parts: seq[string]) =
  let policy = config(parts)
  if parts[0] == "V" or parts[0] == "R":
    if parts[1] == "Q":
      var rows = newSeq[ReadyRow](integer(parts[10]))
      var cursor = 11
      for slot in 0..<rows.len:
        let count = integer(parts[cursor])
        inc cursor
        rows[slot] = newSeq[ReadyItem](count)
        for i in 0..<count:
          let owner = decodeOwnedReport(unhex(parts[cursor]),
              341) # Independent broad-profile source capture, not parent decoding.
          if owner.error == OwnershipError.None: rows[slot][
              i].report = owner.value # Malformed report sources retain default handles for rejection tests.
          rows[slot][i].dependencies = hashes(parts[cursor+1])
          cursor += 2
      assert cursor == parts.len
      let value = readyStateEntry(rows, policy)
      for slot in 0..<rows.len:
        for i in 0..<rows[slot].len:
          rows[slot][i].report = default(OwnedReport) # Returned output cannot alias mutable source fields.
          for j in 0..<rows[slot][i].dependencies.len: rows[slot][i].dependencies[j] = default(PackageHash)
      encoded(value, parts[0] == "R")
    else:
      assert parts[1] == "A" # Trusted component selector cannot silently select a different schema.
      var rows = newSeq[AccumulatedRow](integer(parts[10]))
      assert parts.len == rows.len+11
      for slot in 0..<rows.len: rows[slot] = hashes(parts[
          11+slot]) # Deliberately hostile set order remains unchanged.
      let value = accumulatedStateEntry(rows, policy)
      for slot in 0..<rows.len:
        for i in 0..<rows[slot].len: rows[slot][i] = default(PackageHash) # Entry payload is an independent copy.
      encoded(value, parts[0] == "R")
  else:
    assert parts[0] == "D" # Unknown trusted operations cannot become protocol input.
    var bytes = unhex(parts[10])
    if parts[1] == "Q":
      let parsed = decodeReadyState(bytes, policy)
      if parsed.error != WorkQueueError.None:
        echo ($parsed.error).toLowerAscii() # No retained partial earlier rows or cursor on failure.
      else:
        for i in 0..<bytes.len: bytes[i] = 0 # Whole-input destruction precedes every owner observation.
        let owner = parsed.value.snapshot
        let info = readyInfo(owner).value
        var output = $parsed.value.consumed & " " & $info.slots & " " & $info.items & " " &
            $info.dependencies
        for slot in 0..<info.slots:
          let count = readySlotCount(owner, WorkQueueSlot(slot)).value
          output.add(" " & $count)
          for i in 0..<count:
            let item = readyItemAt(owner, WorkQueueSlot(slot), ReadyItemIndex(i)).value
            output.add(" " & reportBytes(item.report))
            var deps: seq[byte] = @[]
            for j in 0..<item.dependencies:
              let value = readyDependencyAt(owner, WorkQueueSlot(slot), ReadyItemIndex(i),
                  WorkQueueHashIndex(j)).value
              # Extract all copied octets through the selected original parent item.
              for b in value.bytes: deps.add(b)
            output.add(" " & $item.dependencies & ":" & hex(deps))
        echo output
    else:
      assert parts[1] == "A" # Distinct retained owner types prevent schema substitution.
      let parsed = decodeAccumulatedState(bytes, policy)
      if parsed.error != WorkQueueError.None:
        echo ($parsed.error).toLowerAscii() # No fabricated empty sets after a malformed late row.
      else:
        for i in 0..<bytes.len: bytes[i] = 0 # Captured fixed identities must survive input mutation.
        let owner = parsed.value.snapshot
        let info = accumulatedInfo(owner).value
        var output = $parsed.value.consumed & " " & $info.slots & " " & $info.items & " 0"
        for slot in 0..<info.slots:
          let count = accumulatedSlotCount(owner, WorkQueueSlot(slot)).value
          var hashes: seq[byte] = @[]
          for i in 0..<count:
            let value = accumulatedHashAt(owner, WorkQueueSlot(slot), WorkQueueHashIndex(i)).value
            # Only this selected row's independently copied members may be observed.
            for b in value.bytes: hashes.add(b)
          output.add(" " & $count & ":" & hex(hashes))
        echo output

# Each trusted request releases all temporary and retained values independently.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Empty trusted transport lines are ignored.
