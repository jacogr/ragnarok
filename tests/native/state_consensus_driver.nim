## Trusted independent source/field adapter for chapter-4 serialization and immutable parent ownership.
import std/[os, strutils]
import ../../src/[state_consensus, state_safrole, state_trie, bounded, assurances]

## Decode trusted hex with a separate token for an empty source.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty malformed inputs remain expressible.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Copy source octets without host integer reordering.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

## Display exact bytes, preserving leading zeroes.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Retain one token for empty observations.
  # Each output byte is independently observable by Python.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii())

## Fixed typed fields are constructed directly from source bytes, not from production decoder output.
proc fixed[N: static int](bytes: openArray[byte], offset: int): array[N, byte] =
  # Trusted request schemas establish exact field widths before this helper runs.
  for i in 0..<N: result[i] = bytes[offset+i]

## Reconstruct authored validator source records with exact field positions.
proc records(bytes: seq[byte]): seq[StateValidator] =
  doAssert bytes.len mod 336 == 0
  result = newSeq[StateValidator](bytes.len div 336)
  # Field swaps become visible in encoder output against the independent source wire.
  for i in 0..<result.len:
    let p = i*336
    result[i] = StateValidator(bandersnatch: StateBsKey(fixed[32](bytes, p)),
      ed25519: StateEdKey(fixed[32](bytes, p+32)), bls: StateBlsKey(fixed[144](bytes, p+64)),
      metadata: StateValidatorMetadata(fixed[128](bytes, p+208)))

## Construct fixed source tickets without consulting the production decoder.
proc tickets(bytes: seq[byte]): seq[WinningTicket] =
  doAssert bytes.len mod 33 == 0
  result = newSeq[WinningTicket](bytes.len div 33)
  # Identifiers precede E1 attempts; these are not proof-bearing extrinsic records.
  for i in 0..<result.len:
    result[i] = WinningTicket(id: WinningTicketId(fixed[32](bytes, i*33)), attempt: TicketAttempt(
        bytes[i*33+32]))

## Read explicit chain and resource policy from trusted transport fields.
proc config(parts: seq[string]): SafroleStateConfig =
  SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(parseBiggestUInt(parts[1])),
    validators: ElementLimit(parseBiggestUInt(parts[2])), maxBytes: ByteLimit(parseBiggestUInt(
        parts[3]))),
    epochSlots: EpochSlots(parseBiggestUInt(parts[4])), maxAccumulator: ElementLimit(
        parseBiggestUInt(parts[5])),
    maxBytes: ByteLimit(parseBiggestUInt(parts[6])))

## Observe a fixed ticket through its explicit fields, not via the production encoder.
proc appendTicket(output: var seq[byte], value: WinningTicket) =
  output.add(array[32, byte](value.id))
  output.add(byte(value.attempt))

## Execute one complete request; failure never publishes default state or partial progress.
proc request(parts: seq[string]) =
  let policy = config(parts)
  case parts[0]
  of "V", "R":
    # Typed sources are authored directly from separate pending/root/schedule/accumulator inputs.
    var source = SafroleState(pending: records(unhex(parts[7])), root: StateRingRoot(fixed[144](
        unhex(parts[8]), 0)),
      accumulator: tickets(unhex(parts[11])))
    let raw = unhex(parts[10])
    if parts[9] == "0":
      source.schedule = SealerSchedule(kind: SealerKind.Tickets, tickets: tickets(
          raw)) # Select only active ticket fields.
    else:
      # Fallback source records are exactly 32 bytes; invalid schedule counts remain expressible.
      doAssert parts[9] == "1" and raw.len mod 32 == 0
      source.schedule = SealerSchedule(kind: SealerKind.Keys, keys: newSeq[StateBsKey](
          raw.len div 32))
      for i in 0..<source.schedule.keys.len: source.schedule.keys[i] = StateBsKey(fixed[32](raw, i*32))
    let encoded = safroleStateEntry(source, policy)
    if encoded.error != StateComponentError.None:
      echo ($encoded.error).toLowerAscii() # No entry/value/length after rejection.
    else:
      source = default(SafroleState) # Output must retain no borrowed source sequence.
      if parts[0] == "V":
        echo $encoded.value.value.len & " " & hex(
            encoded.value.value) # Observe independent raw bytes for all fields.
      else:
        # Single chapter integration is a partial mapping root, never a complete JAM state claim.
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(1)))
        doAssert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))
  of "D":
    # Whole-parent decoding must retain each child when its original bytes are destroyed.
    var input = unhex(parts[7])
    let decoded = decodeSafroleState(input, policy)
    if decoded.error != StateComponentError.None:
      echo ($decoded.error).toLowerAscii() # Failure carries neither child owners nor consumed progress.
    else:
      for i in 0..<input.len: input[i] = 0 # All following observations depend on private copies.
      let owner = decoded.value.snapshot
      let info = safroleInfo(owner)
      doAssert info.error == StateComponentError.None
      var pending, schedule, accumulator: seq[byte]
      # Pending extraction stays bound to the parent and returns full copied validator records.
      for i in 0..<info.value.validators:
        let item = pendingValidatorAt(owner, StateValidatorIndex(i))
        doAssert item.error == StateComponentError.None
        pending.add(array[32, byte](item.value.bandersnatch)); pending.add(array[32, byte](
            item.value.ed25519))
        pending.add(array[144, byte](item.value.bls)); pending.add(array[128, byte](
            item.value.metadata))
      # Select the schedule kind before accessing its owner-bound slot values.
      for i in 0..<info.value.slots:
        if info.value.kind == SealerKind.Tickets:
          let item = sealerTicketAt(owner, SafroleStateIndex(i))
          doAssert item.error == StateComponentError.None
          appendTicket(schedule, item.value)
        else:
          let item = sealerKeyAt(owner, SafroleStateIndex(i)) # Fallback keys are fixed independent values.
          doAssert item.error == StateComponentError.None
          schedule.add(array[32, byte](item.value))
      # Preserve accumulator order exactly, including repeated and unsorted opaque identifiers.
      for i in 0..<info.value.accumulated:
        let item = accumulatedTicketAt(owner, SafroleStateIndex(i))
        doAssert item.error == StateComponentError.None
        appendTicket(accumulator, item.value)
      echo $decoded.value.consumed & " " & hex(pending) & " " & hex(array[144, byte](
          info.value.root)) & " " &
        $ord(info.value.kind) & " " & hex(schedule) & " " & hex(accumulator)
  else: doAssert false # Unknown trusted operations cannot choose a different schema.

# Request-local mutable source arrays and immutable snapshot handles release after every observation.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Ignore empty transport lines.
