## Independent source fields and copied-value observations for C(255, service) metadata.
import std/[assertions, cmdline, syncio, strutils, parseutils]
import ../../src/codec/[state_accounts, state_trie, bounded]

## Preserve hostile empty input rather than replacing it with a valid zero discriminator.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Trusted empty transport token is not protocol version zero.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Trusted fixture transport carries exactly two lowercase hexadecimal digits per octet.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Reject malformed tokens rather than silently accepting a partial parse.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Display complete fixed bytes including leading zeroes, without interpreting hashes as integers.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Preserve empty trusted fields if encountered.
  result = ""
  # Display every supplied fixed octet, preserving leading zeroes.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii()) # No production serialization creates these observations.

## Require a complete trusted uint64 token through the supported nonthrowing interface.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

## Construct typed source metadata directly from decimal fields and literal code identity.
proc source(parts: seq[string]): ServiceMetadata =
  assert parts.len == 13
  let raw = unhex(parts[3])
  assert raw.len == 32
  var code = default(array[32, byte])
  for i in 0..<32: code[i] = raw[i] # Code identity is a fixed value, independent of production decoding.
  ServiceMetadata(codeHash: CodeHash(code), balance: AccountBalance(unsigned(parts[4])),
    minimumAccumulationGas: Gas(unsigned(parts[5])), minimumTransferGas: Gas(
        unsigned(parts[6])),
    storageBytes: AccountStorageBytes(unsigned(parts[7])), depositOffset: AccountBalance(
        unsigned(parts[8])),
    storageItems: AccountStorageItems(unsigned(parts[9])), created: AccountSlot(
        unsigned(parts[10])),
    lastAccumulation: AccountSlot(unsigned(parts[11])), parent: ServiceIndex(
        unsigned(parts[12])))

## Observe every logical fixed field, preserving the precise normative ordering of the five E8/four E4 values.
proc observed(value: ServiceMetadataRead): string =
  let data = value.metadata
  result = $value.consumed & " " & hex(array[32, byte](data.codeHash))
  for field in [uint64(data.balance), uint64(data.minimumAccumulationGas), uint64(
      data.minimumTransferGas), uint64(data.storageBytes), uint64(data.depositOffset)]: result.add(
          " " & $field) # Token/gas/octet domains remain separate in the source API.
  for field in [uint32(data.storageItems), uint32(data.created), uint32(data.lastAccumulation),
      uint32(data.parent)]:
    result.add(" " & $field) # E4 values are observed numerically, not through production re-encoding.

## Execute a complete trusted source or hostile-wire request, exposing only selected success or a failure reason.
proc request(parts: seq[string]) =
  let budget = ByteLimit(unsigned(parts[1]))
  case parts[0]
  of "V", "R":
    var value = source(parts)
    let encoded = serviceMetadataEntry(ServiceIndex(unsigned(parts[2])), value, budget)
    if encoded.error != ServiceMetadataError.None:
      echo ($encoded.error).toLowerAscii() # No fabricated default key/value after resource failure.
    else:
      value = default(ServiceMetadata) # Returned entry must be an independent fixed copy.
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(
              1))) # One metadata entry only, not the whole service or JAM state.
        assert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))
  of "D":
    var input = unhex(parts[2])
    let decoded = decodeServiceMetadata(input, budget)
    if decoded.error != ServiceMetadataError.None:
      echo ($decoded.error).toLowerAscii() # Failure contains no metadata or consumed cursor.
    else:
      for i in 0..<input.len: input[i] = 0 # Fixed copied fields must survive complete caller-input destruction.
      echo observed(decoded.value)
  else: assert false # Unknown trusted operations cannot silently become a different schema.

# Every request releases its temporary caller arrays; decoded metadata has no retained heap ownership.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Empty trusted transport lines contain no request.
