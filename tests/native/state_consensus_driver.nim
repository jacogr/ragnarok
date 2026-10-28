# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted independent source/field adapter for chapter-4 serialization and immutable parent
## ownership.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import std/parseutils
import ../../src/codec/state_consensus as codec_state_consensus
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances

## Decode trusted hex with a separate token for an empty source.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty malformed inputs remain expressible.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Copy source octets without host integer reordering.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Trusted fixture transport has exactly two lowercase digits per source byte.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Display exact bytes, preserving leading zeroes.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Retain one token for empty observations.
  result = ""
  # Each output byte is independently observable by Python.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii())

## Fixed typed fields are constructed directly from source bytes, not from production decoder output.
proc fixed[N: static[int]](bytes: openArray[byte], offset: int): array[N, byte] =
  result = default(array[N, byte])
  # Trusted request schemas establish exact field widths before this helper runs.
  for i in 0..<N: result[i] = bytes[offset+i]

## Reconstruct authored validator source records with exact field positions.
proc records(bytes: seq[byte]): seq[StateValidator] =
  assert bytes.len mod 336 == 0
  result = newSeq[StateValidator](bytes.len div 336)
  # Field swaps become visible in encoder output against the independent source wire.
  for i in 0..<result.len:
    let p = i*336
    result[i] = StateValidator(bandersnatch: StateBsKey(fixed[32](bytes, p)),
      ed25519: StateEdKey(fixed[32](bytes, p+32)), bls: StateBlsKey(fixed[144](bytes, p+64)),
      metadata: StateValidatorMetadata(fixed[128](bytes, p+208)))

## Construct fixed source tickets without consulting the production decoder.
proc tickets(bytes: seq[byte]): seq[WinningTicket] =
  assert bytes.len mod 33 == 0
  result = newSeq[WinningTicket](bytes.len div 33)
  # Identifiers precede E1 attempts; these are not proof-bearing extrinsic records.
  for i in 0..<result.len:
    result[i] = WinningTicket(id: WinningTicketId(fixed[32](bytes, i*33)), attempt: TicketAttempt(
        bytes[i*33+32]))

# Append fixture fields through the supported single-element sequence API.
proc append(output: var seq[byte], input: openArray[byte]) =
  # Every copied octet is independent observation data, not a production encoding expectation.
  for octet in input: output.add(octet)
# Parse full-width unsigned fixture values without signed narrowing.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

## Read explicit chain and resource policy from trusted transport fields.
proc config(parts: seq[string]): SafroleStateConfig =
  SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(unsigned(parts[1])),
    validators: ElementLimit(unsigned(parts[2])), maxBytes: ByteLimit(unsigned(parts[3]))),
    epochSlots: EpochSlots(unsigned(parts[4])), maxAccumulator: ElementLimit(
        unsigned(parts[5])),
    maxBytes: ByteLimit(unsigned(parts[6])))

## Observe a fixed ticket through its explicit fields, not via the production encoder.
proc appendTicket(output: var seq[byte], value: WinningTicket) =
  append(output, array[32, byte](value.id))
  output.add(byte(value.attempt))

## Execute one complete request; failure never publishes default state or partial progress.
proc request(parts: seq[string]) {.raises.} =
  let policy = config(parts)
  case parts[0]
  of "V", "R":
    # Typed sources are authored directly from separate pending/root/schedule/accumulator inputs.
    var source = SafroleState(pending: records(unhex(parts[7])), root: StateRingRoot(fixed[144](
        unhex(parts[8]), 0)),
      accumulator: tickets(unhex(parts[11])))
    let raw = unhex(parts[10])
    if parts[9] == "0":
      source.schedule = ticketSchedule(tickets(raw)) # Select only active ticket fields.
    else:
      # Fallback source records are exactly 32 bytes; invalid schedule counts remain expressible.
      assert parts[9] == "1" and raw.len mod 32 == 0
      var sourceKeys = newSeq[StateBsKey](raw.len div 32)
      # Independent typed keys are assembled before constructing their closed schedule alternative.
      for i in 0..<sourceKeys.len: sourceKeys[i] = StateBsKey(fixed[32](raw, i*32))
      source.schedule = keySchedule(sourceKeys)
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
        assert root.error == StateTrieError.None
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
      assert info.error == StateComponentError.None
      var pending: seq[byte] = @[]
      var schedule: seq[byte] = @[]
      var accumulator: seq[byte] = @[]
      # Pending extraction stays bound to the parent and returns full copied validator records.
      for i in 0..<info.value.validators:
        let item = pendingValidatorAt(owner, StateValidatorIndex(i))
        assert item.error == StateComponentError.None
        append(pending, array[32, byte](item.value.bandersnatch)); append(pending, array[32, byte](
            item.value.ed25519))
        append(pending, array[144, byte](item.value.bls)); append(pending, array[128, byte](
            item.value.metadata))
      # Select the schedule kind before accessing its owner-bound slot values.
      for i in 0..<info.value.slots:
        if info.value.kind == SealerKind.Tickets:
          let item = sealerTicketAt(owner, SafroleStateIndex(i))
          assert item.error == StateComponentError.None
          appendTicket(schedule, item.value)
        else:
          let item = sealerKeyAt(owner, SafroleStateIndex(i)) # Fallback keys are fixed independent values.
          assert item.error == StateComponentError.None
          append(schedule, array[32, byte](item.value))
      # Preserve accumulator order exactly, including repeated and unsorted opaque identifiers.
      for i in 0..<info.value.accumulated:
        let item = accumulatedTicketAt(owner, SafroleStateIndex(i))
        assert item.error == StateComponentError.None
        appendTicket(accumulator, item.value)
      echo $decoded.value.consumed & " " & hex(pending) & " " & hex(array[144, byte](
          info.value.root)) & " " &
        $ord(info.value.kind) & " " & hex(schedule) & " " & hex(accumulator)
  else: assert false # Unknown trusted operations cannot choose a different schema.

# Keep trusted file/argument parsing outside the codec's typed failure contract.
proc main() {.raises.} =
  # Every batch observation releases its own source arrays and retained handles.
  for line in lines(paramStr(1)):
    if line.len > 0: request(line.splitWhitespace()) # Empty lines have no operation.
try:
  main()
except:
  # Trusted transport failures must not masquerade as protocol rejection.
  quit(2)
