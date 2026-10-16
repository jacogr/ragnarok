## Trusted independent source/field adapter for history dictionaries and optional MMR peaks.
import std/[os, strutils]
import ../../src/codec/[state_history, state_trie, bounded, assurances]

## Preserve empty dictionary and absent-peak transport tokens without adding wire bytes.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty trusted sources remain independently expressible.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Exact octet order is used for independent fixed-field sources.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

## Observe complete byte identities without dropping leading zeroes.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Empty dictionary values retain one token.
  # Fixed identities are never rendered as host integers.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii())

## Copy fixed trusted source fields rather than relying on a production decoder to define their offsets.
proc fixed(bytes: seq[byte], offset: int): array[32, byte] =
  # Trusted row schemas establish field width before this helper runs.
  for i in 0..<32: result[i] = bytes[offset+i]

## Decode explicit core, block, per-record/aggregate package, peak and byte policy tokens.
proc config(parts: seq[string]): HistoryConfig =
  HistoryConfig(cores: CoreCount(parseBiggestUInt(parts[1])), blocks: ElementLimit(parseBiggestUInt(
      parts[2])),
    perBlock: ElementLimit(parseBiggestUInt(parts[3])), totalPackages: ElementLimit(
        parseBiggestUInt(parts[4])),
    peaks: ElementLimit(parseBiggestUInt(parts[5])), maxBytes: ByteLimit(parseBiggestUInt(parts[6])))

## Construct typed source fields directly, preserving dictionary key/value pairing and optional presence.
proc source(parts: seq[string]): HistoryState =
  let records = parseInt(parts[7])
  result.blocks = newSeq[HistoryBlock](records)
  var cursor = 8
  # Each source block has an independent fixed tuple and raw key/value pair sequence.
  for i in 0..<records:
    let bytes = unhex(parts[cursor])
    let pairs = unhex(parts[cursor+1])
    cursor += 2
    doAssert bytes.len == 100 and pairs.len mod 64 == 0
    var slot = 0'u32
    for j in 0..<4: slot = slot or (uint32(bytes[96+j]) shl (j*8)) # Trusted E4 source field is little-endian.
    result.blocks[i] = HistoryBlock(header: HistoryHeaderHash(fixed(bytes, 0)),
        superPeak: HistorySuperPeak(fixed(bytes, 32)),
      state: HistoryStateRoot(fixed(bytes, 64)), slot: HistorySlot(slot), packages: newSeq[
          ReportedPackage](pairs.len div 64))
    # Dictionary keys and values are authored separately from production encode/decode.
    for j in 0..<result.blocks[i].packages.len:
      result.blocks[i].packages[j] = ReportedPackage(package: PackageHash(bytes: fixed(pairs,
          j*64)),
        segment: SegmentRoot(bytes: fixed(pairs, j*64+32)))
  let peaks = parseInt(parts[cursor])
  inc cursor
  doAssert parts.len == cursor+peaks
  result.peaks = newSeq[HistoryPeak](peaks)
  # A dash denotes an absent source alternative, while 64 hex zeroes denote a present zero hash.
  for i in 0..<peaks:
    if parts[cursor+i] == "-":
      result.peaks[i] = HistoryPeak(present: false) # No hidden default hash for absence.
    else:
      let bytes = unhex(parts[cursor+i])
      doAssert bytes.len == 32
      result.peaks[i] = HistoryPeak(present: true, hash: HistoryPeakHash(fixed(bytes, 0)))

## Execute one independent entry/root or owner-bound observation request.
proc request(parts: seq[string]) =
  let policy = config(parts)
  case parts[0]
  of "V", "R":
    # Typed sources may intentionally have bad dictionary order or wrong protocol cardinalities.
    var state = source(parts)
    let encoded = historyStateEntry(state, policy)
    if encoded.error != HistoryError.None:
      echo ($encoded.error).toLowerAscii() # Failure publishes no default entry or partial progress.
    else:
      # Mutation of source fields after encoding must not alter the returned payload.
      for i in 0..<state.blocks.len:
        state.blocks[i].header = default(HistoryHeaderHash)
        for j in 0..<state.blocks[i].packages.len: state.blocks[i].packages[j] = default(
            ReportedPackage) # Entry owns its fields.
      state.peaks = @[]
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        # C(3)-only roots are partial mapping evidence, not full JAM state commitments.
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(1)))
        doAssert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))
  of "D":
    # Whole nested decoding is observed only after destroying every caller wire byte.
    var bytes = unhex(parts[7])
    let decoded = decodeHistoryState(bytes, policy)
    if decoded.error != HistoryError.None:
      echo ($decoded.error).toLowerAscii() # No earlier child owners escape a late failure.
    else:
      for i in 0..<bytes.len: bytes[i] = 0 # All following field observations require private copied storage.
      let owner = decoded.value.snapshot
      let info = historyInfo(owner)
      doAssert info.error == HistoryError.None
      var output = $decoded.value.consumed & " " & $info.value.blocks & " " & $info.value.peaks
      # Copy block metadata and dictionary pairs independently rather than re-encoding production state.
      for i in 0..<info.value.blocks:
        let record = historyBlockAt(owner, HistoryBlockIndex(i))
        doAssert record.error == HistoryError.None
        var pairs: seq[byte]
        for j in 0..<record.value.packages:
          let pair = historyPackageAt(owner, HistoryBlockIndex(i), HistoryPackageIndex(
              j)) # Child indices stay bound to this block.
          doAssert pair.error == HistoryError.None
          pairs.add(pair.value.package.bytes); pairs.add(pair.value.segment.bytes)
        output.add(" " & hex(array[32, byte](record.value.header)) & " " & hex(array[32, byte](
            record.value.superPeak)) & " " &
          hex(array[32, byte](record.value.state)) & " " & $uint32(record.value.slot) & " " &
              $record.value.packages & ":" & hex(pairs))
      # Absence and present-zero remain independently visible even after source destruction.
      for i in 0..<info.value.peaks:
        let peak = historyPeakAt(owner, HistoryPeakIndex(i))
        doAssert peak.error == HistoryError.None
        if peak.value.present:
          output.add(" " & hex(array[32, byte](peak.value.hash))) # Read only the active copied hash alternative.
        else:
          output.add(" -") # Retain each hole and its position, including trailing absence.
      echo output
  else: doAssert false # Unknown trusted operations cannot silently choose another schema.

# Every request owns and releases its caller arrays and snapshot handles independently.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Ignore blank transport lines.
