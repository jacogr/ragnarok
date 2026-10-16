## Trusted field transport for independently authored chapter-12 source and wire requests.
import std/[os, strutils]
import ../../src/[state_privileges, state_trie, bounded]

## Preserve empty malformed input without adding a byte to the protocol stream.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Trusted empty token is distinct from encoded zero.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Parse each independently supplied byte, including leading zeroes.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

## Observe all entry bytes directly rather than deriving expected values with a production decoder.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Whitespace transport retains empty observations.
  # Hex output preserves exact little-endian and natural field framing.
  for b in bytes: result.add(toHex(b, 2).toLowerAscii())

## Construct typed values directly from decimal field transport; no production wire decoding builds sources.
proc source(parts: seq[string]): PrivilegeState =
  result.manager = ServiceIndex(parseBiggestUInt(parts[4]))
  result.delegator = ServiceIndex(parseBiggestUInt(parts[5]))
  result.registrar = ServiceIndex(parseBiggestUInt(parts[6]))
  if parts[7] != "-":
    # Preserve core-position order and duplicate service IDs across cores.
    for text in parts[7].split(','): result.assigners.add(ServiceIndex(parseBiggestUInt(text)))
  if parts[8] != "-":
    # Preserve hostile dictionary order/duplicates for source rejection checks.
    for text in parts[8].split(','):
      let pair = text.split(':')
      result.always.add(AlwaysAccumulate(service: ServiceIndex(parseBiggestUInt(pair[0])),
        gas: PrivilegeGas(parseBiggestUInt(pair[1]))))

## Compare complete entries, partial roots, or copied field observations after destroying mutable inputs.
proc request(parts: seq[string]) =
  let config = PrivilegeConfig(cores: CoreCount(parseBiggestUInt(parts[1])),
    maxAlways: ElementLimit(parseBiggestUInt(parts[2])), maxBytes: ByteLimit(parseBiggestUInt(parts[3])))
  case parts[0]
  of "V", "R":
    # Field sources are independent of the implementation's wire parser.
    var state = source(parts)
    let encoded = privilegeStateEntry(state, config)
    if encoded.error != PrivilegeError.None:
      echo ($encoded.error).toLowerAscii() # Failure exposes only its reason.
    else:
      # Destroy mutable source arrays before reading the independent output.
      for i in 0..<state.assigners.len: state.assigners[i] = ServiceIndex(0)
      for i in 0..<state.always.len: state.always[i] = default(AlwaysAccumulate)
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        # C(12)-only roots are integration checks, not complete state-root claims.
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
          perValue: ByteLimit(high(uint64)), totalValueBytes: ByteLimit(high(uint64)),
              nodes: TrieNodeLimit(1)))
        doAssert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))
  of "D":
    # Complete preflight precedes immutable capture of even the earlier role fields.
    var input = unhex(parts[4])
    let decoded = decodePrivilegeState(input, config)
    if decoded.error != PrivilegeError.None:
      echo ($decoded.error).toLowerAscii() # No partial owner or cursor after a late failure.
    else:
      for i in 0..<input.len: input[i] = 0 # Retained observations cannot depend on caller wire.
      let owner = decoded.value.snapshot
      let info = privilegeInfo(owner).value
      var output = $decoded.value.consumed & " " & $uint32(info.manager) & " " &
        $uint32(info.delegator) & " " & $uint32(info.registrar) & " " & $info.cores
      # Every configured assigner is extracted by nominal core position.
      for i in 0..<info.cores:
        output.add(" " & $uint32(privilegeAssignerAt(owner, PrivilegeCoreIndex(i)).value))
      output.add(" " & $info.always)
      # Every pair is observed as logical numbers rather than re-encoded expected bytes.
      for i in 0..<info.always:
        let pair = alwaysAccumulateAt(owner, PrivilegeEntryIndex(i)).value
        output.add(" " & $uint32(pair.service) & ":" & $uint64(pair.gas))
      echo output
  else: doAssert false # Trusted operation cannot silently select another component.

# Each request owns and releases its temporary source, output and retained state independently.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Empty trusted transport lines have no meaning.
