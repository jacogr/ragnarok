## Bounded JIP-4 telemetry metadata extraction, not chain-state validation or initialization.
import std/[parsejson, streams]
import ../crypto/primitives
import ./wire

const MaxChainBytes* = 8 * 1024 * 1024
# Full-profile epoch markers exceed 64 KiB; keep a bounded allowance for larger validator sets.
const MaxHeaderBytes* = 256 * 1024

# Convert one ASCII hexadecimal digit; -1 keeps invalid input separate from zero.
func nibble(character: char): int =
  # JIP-4 hex strings may use either case, but no whitespace or implicit truncation.
  if character >= '0' and character <= '9': return ord(character) - ord('0')
  if character >= 'a' and character <= 'f': return ord(character) - ord('a') + 10
  if character >= 'A' and character <= 'F': return ord(character) - ord('A') + 10
  -1

# Decode an exact bounded hex field atomically; empty output means invalid, never a valid field here.
proc hexBytes(text: string, maximum: int): seq[byte] =
  result = @[]
  # Both supported fields must be nonempty and have a complete pair per byte.
  if text.len == 0 or text.len mod 2 != 0 or text.len div 2 > maximum: return
  var bytes = newSeq[byte](text.len div 2)
  # Validate every pair before publishing the newly owned sequence.
  for i in 0..<bytes.len:
    let high = nibble(text[2 * i])
    let low = nibble(text[2 * i + 1])
    if high < 0 or low < 0: return # Do not expose a decoded prefix after bad input.
    bytes[i] = byte(high * 16 + low)
  result = move(bytes)

# Parse complete bounded JSON and hash its serialized genesis header using the maintained primitive.
proc chainMetadata*(text: string, identity: array[32, byte], address: array[16, byte],
    port: uint16): MetadataResult =
  # Limit input before the standard token parser creates any strings or parser states.
  if text.len == 0 or text.len > MaxChainBytes: return invalidMetadata(invalidChain)
  var parser = default(JsonParser)
  parser.open(newStringStream(text), "telemetry chain")
  defer: parser.close() # Parser-owned stream and token storage have no escaping borrows.
  parser.next()
  if parser.kind != jsonObjectStart: return invalidMetadata(invalidChain)
  var depth = 1
  var wantKey = true
  var key = ""
  var parameters, header = ""
  var hasParameters, hasHeader = false
  # The standard event parser validates punctuation; depth bounds its iterative state stack.
  while depth > 0:
    parser.next()
    let kind = parser.kind
    if kind in [jsonError, jsonEof]: return invalidMetadata(invalidChain)
    if depth == 1 and kind != jsonObjectEnd:
      if wantKey:
        # Top-level object members require string keys before any value is inspected.
        if kind != jsonString: return invalidMetadata(invalidChain)
        key = parser.str
        wantKey = false
      else:
        # Only these two JIP-4 fields feed telemetry; duplicate relevant keys are ambiguous.
        if key == "protocol_parameters":
          if kind != jsonString or hasParameters: return invalidMetadata(invalidChain)
          parameters = parser.str
          hasParameters = true
        elif key == "genesis_header":
          if kind != jsonString or hasHeader: return invalidMetadata(invalidChain)
          header = parser.str
          hasHeader = true
        wantKey = true
    if kind in [jsonObjectStart, jsonArrayStart]:
      inc depth
      if depth > 32: return invalidMetadata(invalidChain) # Bound nested unused state/extension data too.
    elif kind in [jsonObjectEnd, jsonArrayEnd]:
      dec depth # Standard parser enforces matching delimiters.
  parser.next()
  if parser.kind != jsonEof or not hasParameters or not hasHeader: return invalidMetadata(invalidChain)
  let params = hexBytes(parameters, 122)
  let genesis = hexBytes(header, MaxHeaderBytes)
  if params.len != 122 or genesis.len == 0: return invalidMetadata(invalidChain)
  let digest = blake2b256(genesis)
  if digest.error != CryptoError.None: return invalidMetadata(hashFailed)
  let hash = array[32, byte](digest.value)
  var bytes = default(array[MetadataSize, byte])
  # Copy exact fetch bytes; the later metadata constructor validates the bounded core count.
  for i in 0..<122: bytes[i] = params[i]
  # Header identity is Blake2b-256 of the complete serialized header, not a state root.
  for i in 0..<32:
    bytes[122 + i] = hash[i]
    bytes[154 + i] = identity[i]
  # Advertise the local QUIC endpoint, never the collector's TCP endpoint.
  for i in 0..<16: bytes[186 + i] = address[i]
  bytes[202] = byte(port and 255)
  bytes[203] = byte(port shr 8)
  metadata(bytes)
