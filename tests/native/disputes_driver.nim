## Trusted fixture adapter: independent typed sources and individual decoded field observation.
import std/[os, strutils]
import ../../src/codec/[disputes, bounded, assurances]

# Test-only success selection makes every expected-good getter check its failure branch explicitly.
proc checked[T](parsed: DisputeResult[T]): T =
  doAssert parsed.error == DisputeError.None
  parsed.value

# Convert bounded trusted hexadecimal tokens to test-owned mutable octets.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # A dash preserves empty input as one token.
  doAssert text.len mod 2 == 0 and text.len <= 4*1024*1024
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1])) # Exact byte pairs.

# Render every public identity/signature byte without invoking the production encoder.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Empty fields still occupy a token.
  for octet in bytes: result.add(toHex(octet, 2).toLowerAscii()) # Preserve exact byte order.

# Construct independent fixed-width typed sources from trusted tokens.
proc fixed[N: static int](text: string): array[N, byte] =
  let bytes = unhex(text)
  doAssert bytes.len == N
  for i in 0..<N: result[i] = bytes[i] # No decoder creates the encoding source.

# Source fields follow the Python oracle's logical field sequence, independently of wire offsets.
proc source(parts: seq[string]): Disputes =
  var cursor = 4
  # Advance exactly once per trusted token; all protocol validation remains in the codec.
  template next(): string =
    block:
      let token = parts[cursor]
      inc cursor
      token
  let verdictCount = parseInt(next())
  doAssert verdictCount in 0..17
  result.verdicts = newSeq[Verdict](verdictCount)
  # Each judgment sequence is independently owned source storage for nested-alias checks.
  for i in 0..<verdictCount:
    result.verdicts[i].target = DisputeHash(fixed[32](next()))
    result.verdicts[i].epoch = DisputeEpoch(parseBiggestUInt(next()))
    let count = parseInt(next())
    doAssert count in 0..1024
    result.verdicts[i].judgments = newSeq[Judgment](count)
    # Construct every explicit source judgment, including deliberately invalid identities.
    for j in 0..<count:
      result.verdicts[i].judgments[j].valid = parseInt(next()) == 1 # Source Bool is always representable.
      result.verdicts[i].judgments[j].judge = JudgeIndex(parseInt(next()))
      result.verdicts[i].judgments[j].signature = DisputeSignature(fixed[64](next()))
  let culpritCount = parseInt(next())
  doAssert culpritCount in 0..17
  result.culprits = newSeq[Culprit](culpritCount)
  # Culprit fields omit the fault validity bit.
  for i in 0..<culpritCount:
    result.culprits[i].target = DisputeHash(fixed[32](next()))
    result.culprits[i].key = OffenderKey(fixed[32](next()))
    result.culprits[i].signature = DisputeSignature(fixed[64](next()))
  let faultCount = parseInt(next())
  doAssert faultCount in 0..17
  result.faults = newSeq[Fault](faultCount)
  # Offender ordering is supplied explicitly, including deliberately invalid late records.
  for i in 0..<faultCount:
    result.faults[i].target = DisputeHash(fixed[32](next()))
    result.faults[i].valid = parseInt(next()) == 1
    result.faults[i].key = OffenderKey(fixed[32](next()))
    result.faults[i].signature = DisputeSignature(fixed[64](next()))
  doAssert cursor == parts.len

# Observe every metadata/identity/Boolean/signature field through owner-bound copying getters.
proc fields(owner: OwnedDisputes): string =
  let info = checked(disputesInfo(owner))
  result = $info.verdicts
  # Getter copies cannot expose the snapshot's mutable bytes or nested sequences.
  for i in 0..<info.verdicts:
    var selected = checked(verdictAt(owner, i))
    result.add(" " & hex(array[32, byte](selected.target)) & " " & $uint32(selected.epoch) & " " &
        $selected.judgments)
    let epoch = selected.epoch
    selected.epoch = DisputeEpoch(0)
    doAssert uint32(checked(verdictAt(owner, i)).epoch) == uint32(epoch)
    doAssert judgmentAt(owner, i, -1).error == DisputeError.InvalidIndex
    doAssert judgmentAt(owner, i, selected.judgments).error == DisputeError.InvalidIndex
    # Observe each retained vote and verify that a locally mutated copy cannot change it.
    for j in 0..<selected.judgments:
      var vote = checked(judgmentAt(owner, i, j))
      result.add(" " & $int(vote.valid) & " " & $uint16(vote.judge) & " " & hex(array[64, byte](
          vote.signature)))
      let signature = vote.signature
      vote.signature = DisputeSignature(default(array[64, byte]))
      doAssert array[64, byte](checked(judgmentAt(owner, i, j)).signature) == array[64, byte](signature)
  result.add(" " & $info.culprits)
  # Return every culprit field rather than comparing only a same-codec round trip.
  for i in 0..<info.culprits:
    var value = checked(culpritAt(owner, i))
    result.add(" " & hex(array[32, byte](value.target)) & " " & hex(array[32, byte](value.key)) &
        " " & hex(array[64, byte](value.signature)))
    let key = value.key
    value.key = OffenderKey(default(array[32, byte]))
    doAssert array[32, byte](checked(culpritAt(owner, i)).key) == array[32, byte](key)
  result.add(" " & $info.faults)
  # Fault Boolean copies preserve their exact decoded meaning after local mutation.
  for i in 0..<info.faults:
    var value = checked(faultAt(owner, i))
    result.add(" " & hex(array[32, byte](value.target)) & " " & $int(value.valid) & " " & hex(array[
        32, byte](value.key)) & " " & hex(array[64, byte](value.signature)))
    let valid = value.valid
    value.valid = not valid
    doAssert checked(faultAt(owner, i)).valid == valid

# Process one independently specified encode or decode operation and assert atomicity/lifetime contracts.
proc request(line: string) =
  let parts = line.splitWhitespace()
  doAssert parts.len >= 4
  let config = DisputeConfig(validators: ValidatorCount(parseBiggestUInt(parts[1])),
    maxBytes: ByteLimit(parseBiggestUInt(parts[2])))
  if parts[0] == "E":
    # Native encoding sources come from named fields rather than a production decode round trip.
    let value = source(parts)
    let capacity = parseInt(parts[3])
    doAssert capacity in 0..2097152
    var output = newSeq[byte](capacity)
    for i in 0..<output.len: output[i] = 0xA5 # Whole-buffer sentinel detects late writes on rejection.
    let written = encodeDisputes(value, config, output)
    if written.error != DisputeError.None:
      # All rejection paths leave the complete caller destination unchanged.
      for octet in output: doAssert octet == 0xA5
      echo ($written.error).toLowerAscii()
    else:
      # Successful writes leave unused destination suffix bytes untouched.
      for i in written.value..<output.len: doAssert output[i] == 0xA5
      echo hex(output.toOpenArray(0, written.value-1))
  else:
    # Decoding accepts unrelated suffix bytes but retains only the validated prefix.
    doAssert parts[0] == "D" and parts.len == 4
    var input = unhex(parts[3])
    let parsed = decodeDisputes(input, config)
    if parsed.error != DisputeError.None:
      # Failures contain neither default records nor partial parser progress.
      echo ($parsed.error).toLowerAscii()
    else:
      # Mutating the entire original input cannot alter the retained source identity.
      let owner = parsed.value.owner
      let consumed = parsed.value.info.consumed
      let original = hex(input.toOpenArray(0, consumed-1))
      # Overwrite caller input after capture, including all unrelated suffix bytes.
      for i in 0..<input.len: input[i] = 0
      doAssert verdictAt(owner, -1).error == DisputeError.InvalidIndex
      doAssert verdictAt(owner, parsed.value.info.verdicts).error == DisputeError.InvalidIndex
      doAssert culpritAt(owner, -1).error == DisputeError.InvalidIndex
      doAssert culpritAt(owner, parsed.value.info.culprits).error == DisputeError.InvalidIndex
      doAssert faultAt(owner, -1).error == DisputeError.InvalidIndex
      doAssert faultAt(owner, parsed.value.info.faults).error == DisputeError.InvalidIndex
      let observed = fields(owner)
      var output = newSeq[byte](consumed+3)
      for i in 0..<output.len: output[i] = 0xA5 # Owner re-emission preserves unrelated suffix capacity.
      let encoded = encodeOwnedDisputes(owner, output)
      doAssert encoded.error == DisputeError.None and encoded.value == consumed
      doAssert hex(output.toOpenArray(0, consumed-1)) == original
      # Re-emission must preserve the entire unused output suffix.
      for i in consumed..<output.len: doAssert output[i] == 0xA5
      echo $consumed & " " & observed

# Batched requests retain no cross-request mutable state.
for line in lines(paramStr(1)):
  if line.len > 0: request(line) # Blank fixture lines contain no operation.
