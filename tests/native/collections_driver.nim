## Trusted adapter independently constructs logical scalars and observes immutable collection fields and exact wire.
import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/[collections, natural, fixed_unsigned, bounded]

# Select success before reading any completed value, metadata or extent.
proc checked[T](parsed: CollectionResult[T]): T =
  assert parsed.error == CollectionError.None
  parsed.value

# Decode trusted hex transport into separately mutable test bytes.
proc unhex(text: string): seq[byte] {.raises.} =
  if text == "-": return @[] # Keep zero bytes as one trusted whitespace token.
  assert text.len mod 2 == 0 and text.len <= 2*1024*1024
  result = newSeq[byte](text.len div 2)
  # Every exact byte pair belongs to this independent request's input storage.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Check trusted fixture spelling before unsigned conversion.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

# Render exact bitstring bytes independently of the native logical observations.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Preserve empty field tokens when needed.
  result = ""
  # Every identity/proof byte contributes exactly two lowercase characters.
  for value in bytes: result.add(toHex(int(value), 2).toLowerAscii())

# Parse the full uint64 fixture domain without narrowing through signed host integers.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

# Natural logical sources are supplied as explicit uint64 numbers, never native decoded wire.
proc scalar(T: typedesc[JamNatural], text: string): JamNatural = JamNatural(unsigned(text))

# Fixed-width source schemas may deliberately contain an out-of-range value for encoder rejection tests.
proc scalar[W: static[int]](T: typedesc[CollectionUInt[W]], text: string): CollectionUInt[W] {.raises.} =
  CollectionUInt[W](value: FixedUnsigned(unsigned(text)))

# Fixed bytes are explicitly named octets; zero-width scalars use z rather than the empty-collection token.
proc scalar[N: static[int]](T: typedesc[CollectionBytes[N]], text: string): CollectionBytes[N] {.raises.} =
  result = default(CollectionBytes[N])
  let bytes = unhex(if text == "z": "-" else: text)
  assert bytes.len == N
  # Copy fields by value, so typed source construction retains no borrowed pointer.
  for i in 0..<N: result.bytes[i] = bytes[i]

# Observe logical naturals numerically, independently of their variable wire widths.
proc text(value: JamNatural): string = $uint64(value)

# Fixed numeric logical order can differ from the order of its little-endian wire octets.
proc text[W: static[int]](value: CollectionUInt[W]): string = $uint64(value.value)

# Observe fixed byte fields exactly, including an explicit zero-width scalar token.
proc text[N: static[int]](value: CollectionBytes[N]): string =
  # A zero-width scalar still occupies one logical entry in the source/observation protocol.
  if N == 0: "z"
  else:
    # Nonempty byte keys preserve exact lexicographic field identities.
    hex(value.bytes)

type
  # Trusted fixture sources add only parsing/observation to the production scalar operation contract.
  FixtureScalar = concept
    proc scalar(T: typedesc[Self], text: string): Self {.raises.}
    proc text(value: Self): string

# Every destination is initialized independently so failed writes and untouched suffixes are observable.
proc output(capacity: int): seq[byte] =
  assert capacity in 0..2097152
  result = newSeq[byte](capacity)
  # Canary initialization covers the whole destination, including spare capacity.
  for i in 0..<capacity: result[i] = 0xA5

# Print only selected failures or the exact successful prefix after checking whole-output atomicity.
proc emitted(parsed: CollectionResult[int], bytes: openArray[byte]) =
  # A failed source/policy/capacity/alias check cannot expose a partial write count.
  if parsed.error != CollectionError.None:
    # Every supplied byte, not just the intended prefix, stays unchanged.
    for octet in bytes: assert octet == 0xA5
    echo ($parsed.error).toLowerAscii()
  else:
    # A successful operation must not touch unrelated destination suffix capacity.
    for i in parsed.value..<bytes.len: assert bytes[i] == 0xA5
    echo hex(bytes.toOpenArray(0, parsed.value-1))

# Observe complete typed sets through matching owners after destroying their original input bytes.
proc runSet[T: FixtureScalar and CollectionScalar and CollectionFamily](parts: seq[
    string]) {.raises.} =
  let count = CollectionCount(unsigned(parts[3]))
  let limits = CollectionLimits(items: ElementLimit(unsigned(parts[4])),
    maxBytes: ByteLimit(unsigned(parts[5])))
  # Decoder requests provide untrusted bytes; encoders below receive independent logical fields.
  if parts[0] == "D":
    var input = unhex(parts[6])
    let parsed = (if parts[1] == "F": decodeSet[T](input, count, limits)
      else: decodeVariableSet[T](input, limits)) # Only variable sets carry their cardinality on wire.
 # Failed parent decoding publishes neither partial fields nor cursor progress.
    if parsed.error != CollectionError.None:
      echo ($parsed.error).toLowerAscii()
      return
    let owner = parsed.value.owner
    let n = int(uint64(checked(setCount(owner))))
    # Retained typed snapshots must survive mutation of all caller bytes, including unrelated suffixes.
    for i in 0..<input.len: input[i] = 0
    var fields: seq[string] = @[]
    # Indexed copies observe exact logical values independently of owner re-emission.
    for i in 0..<n: fields.add(text(checked(setAt(owner, i))))
    assert setAt(owner, -1).error == CollectionError.InvalidIndex
    assert setAt(owner, n).error == CollectionError.InvalidIndex
    let broad = CollectionLimits(items: ElementLimit(high(uint64)), maxBytes: ByteLimit(high(uint64)))
    var fixed = output(parsed.value.consumed+12)
    let fixedSize = checked(encodeOwnedSet(owner, CollectionCount(uint64(n)), broad, fixed))
    var variable = output(parsed.value.consumed+12)
    let variableSize = checked(encodeOwnedVariableSet(owner, broad, variable))
    # Owner copies preserve suffixes under both explicitly selected framing forms.
    for i in fixedSize..<fixed.len: assert fixed[i] == 0xA5
    for i in variableSize..<variable.len: assert variable[i] == 0xA5
    echo $parsed.value.consumed & " " & $n & " " & (if n == 0: "-" else: fields.join(",")) &
      " " & hex(fixed.toOpenArray(0, fixedSize-1)) & " " & hex(variable.toOpenArray(0,
          variableSize-1))
  else:
    # Sources are explicit logical scalar values, never constructed using the collection decoder.
    var values: seq[T] = @[]
    # An empty collection differs from one zero-width scalar, represented by z.
    if parts[7] != "-":
      # Source value order is preserved, including deliberately duplicate/descending test cases.
      for field in parts[7].split(','): values.add(scalar(T, field))
    var bytes = output(parseInt(parts[6]))
    # Fixed terms require exact schema cardinality; variable terms derive it from typed source length.
    if parts[1] == "F": emitted(encodeSet(values, count, limits, bytes), bytes)
    else:
      # The variable set adds exactly one natural cardinality discriminator.
      emitted(encodeVariableSet(values, limits, bytes), bytes)

# Observe dictionary key/value association independently of encoded byte order and after caller input release.
proc runDictionary[K, V: FixtureScalar and CollectionScalar and CollectionFamily](parts: seq[
    string]) {.raises.} =
  let limits = CollectionLimits(items: ElementLimit(unsigned(parts[4])),
    maxBytes: ByteLimit(unsigned(parts[5])))
  # A dictionary always carries its pair count, unlike a fixed-cardinality set.
  if parts[0] == "D":
    var input = unhex(parts[6])
    let parsed = decodeDictionary[K, V](input, limits)
    # No earlier pair may escape a malformed late key/value or ordering failure.
    if parsed.error != CollectionError.None:
      echo ($parsed.error).toLowerAscii()
      return
    let owner = parsed.value.owner
    let n = int(uint64(checked(dictionaryCount(owner))))
    # Destructive caller mutation proves snapshots contain independent value copies.
    for i in 0..<input.len: input[i] = 0
    var fields: seq[string] = @[]
    # Each returned pair retains its original key/value relationship, regardless of value ordering.
    for i in 0..<n:
      let pair = checked(dictionaryAt(owner, i))
      fields.add(text(pair.key) & "/" & text(pair.value))
    assert dictionaryAt(owner, -1).error == CollectionError.InvalidIndex
    assert dictionaryAt(owner, n).error == CollectionError.InvalidIndex
    var bytes = output(parsed.value.consumed+3)
    let size = checked(encodeOwnedDictionary(owner, limits, bytes))
    # Successful owner re-emission cannot overwrite unrelated capacity after the parent prefix.
    for i in size..<bytes.len: assert bytes[i] == 0xA5
    echo $parsed.value.consumed & " " & $n & " " & (if n == 0: "-" else: fields.join(",")) &
      " " & hex(bytes.toOpenArray(0, size-1))
  else:
    # Independent typed pairs preserve deliberately invalid key order for encoder validation.
    var values: seq[Entry[K, V]] = @[]
    # The empty-list token cannot be mistaken for a zero-width key or value.
    if parts[7] != "-":
      # Each logical pair is independently named rather than extracted from native decoded bytes.
      for field in parts[7].split(','):
        let pair = field.split('/')
        values.add(Entry[K, V](key: scalar(K, pair[0]), value: scalar(V, pair[1])))
    var bytes = output(parseInt(parts[6]))
    emitted(encodeDictionary(values, limits, bytes), bytes)

# Instantiate only supported explicit scalar schemas, keeping trusted fixture dispatch out of production.
proc request(parts: seq[string]) {.raises.} =
  # Dictionary combinations deliberately include zero-width, variable-width and independently typed key/value roles.
  if parts[1] == "M":
    case parts[2]
    of "nn": runDictionary[JamNatural, JamNatural](parts) # Variable encoded fields still sort by numeric key.
    of "21": runDictionary[CollectionUInt[2], CollectionUInt[1]](
        parts) # Different fixed widths prevent role substitution.
    of "bn": runDictionary[CollectionBytes[2], JamNatural](
        parts) # Lexicographic keys with variable natural values.
    of "nb": runDictionary[JamNatural, CollectionBytes[2]](
        parts) # Numeric keys with independent fixed byte values.
    of "zz": runDictionary[CollectionUInt[0], CollectionUInt[0]](parts) # Singleton zero-width key/value domains.
    of "zn": runDictionary[CollectionBytes[0], JamNatural](
        parts) # Zero-width keys cannot encode duplicate entries.
    of "hh": runDictionary[CollectionBytes[32], CollectionBytes[32]](
        parts) # Existing report lookup hash/root widths.
    else: assert false # Unknown trusted schemas must never silently select another production type.
  else:
    # Sets exercise every supported scalar family and important fixed-width boundaries.
    case parts[2]
    of "n": runSet[JamNatural](parts) # General naturals retain their canonical variable representations.
    of "0": runSet[CollectionUInt[0]](parts) # Zero width has only logical value zero.
    of "1": runSet[CollectionUInt[1]](parts) # E1 boundary and late range rejection.
    of "2": runSet[CollectionUInt[2]](parts) # Numeric order differs visibly from lexicographic wire order.
    of "3": runSet[CollectionUInt[3]](parts) # Every supported E0..E8 schema must instantiate its own typed codec.
    of "4": runSet[CollectionUInt[4]](parts) # E4 width and host-independent unsigned semantics.
    of "5": runSet[CollectionUInt[5]](parts) # Every supported E0..E8 schema must instantiate its own typed codec.
    of "6": runSet[CollectionUInt[6]](parts) # Every supported E0..E8 schema must instantiate its own typed codec.
    of "7": runSet[CollectionUInt[7]](parts) # Every supported E0..E8 schema must instantiate its own typed codec.
    of "8": runSet[CollectionUInt[8]](parts) # Complete uint64 key domain.
    of "b0": runSet[CollectionBytes[0]](parts) # Empty byte keys form a singleton domain.
    of "b1": runSet[CollectionBytes[1]](parts) # Exhaustive one-octet ordering cases.
    of "b2": runSet[CollectionBytes[2]](parts) # Lexicographic comparison follows the first differing octet.
    of "b32": runSet[CollectionBytes[32]](parts) # Existing prerequisite hash widths.
    else: assert false # Unsupported fixture schemas cannot fabricate another codec's result.

# Each request owns its buffers and snapshot handles until its complete observation is emitted.
try:
  for line in lines(paramStr(1)):
    # Ignore empty trusted batch lines without issuing accidental decode operations.
    if line.len > 0: request(line.splitWhitespace())
except:
  # Trusted fixture transport failures fail separately from typed codec rejection.
  quit(2)
