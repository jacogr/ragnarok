## GP 0.8.0 C.1.3/C.1.5/C.1.6 typed canonical collections; see spec/collections.md.
import ./[natural, fixed_unsigned, bounded]

type
  # Schema cardinality is distinct from both resource ceilings and serialized byte extents.
  CollectionCount* = distinct uint64
  # A fixed-width unsigned scalar keeps its schema in the type, including the valid zero-width domain.
  CollectionUInt*[width: static int] = object
    value*: FixedUnsigned
  # Fixed octets sort lexicographically by octet, with no length discriminator on individual elements.
  CollectionBytes*[size: static int] = object
    bytes*: array[size, byte]
  # Dictionary keys and values retain their separate compile-time schemas and logical roles.
  Entry*[K, V] = object
    key*: K
    value*: V
  # Explicit caller policy bounds both entry count and the complete consumed/written parent prefix.
  CollectionLimits* = object
    items*: ElementLimit
    maxBytes*: ByteLimit
  # Default/error alternatives never carry a value, owner, initialized count or partial cursor.
  CollectionError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, InvalidCount,
    ValueOutOfRange, LengthOverflow, OutputTooSmall, AliasedBuffers, InvalidOwner, InvalidIndex
  # Select complete success before reading its copied scalar, retained owner or byte extent.
  CollectionResult*[T] = object
    case error*: CollectionError
    of CollectionError.None:
      # Only successful operations expose complete data/progress.
      value*: T
    else:
      # Failed/default operations expose their reason alone.
      discard
  # Child decoding returns a complete fixed value with its exact canonical prefix extent.
  ScalarRead[T] = object
    value: T
    consumed: int
  # Private layout retains no input pointer and authorizes capture only after complete validation.
  Layout = object
    count, offset, consumed: int
  # Immutable typed storage contains only supported value-only scalar schemas, never public mutable sequences.
  SetData[T] = ref object
    values: seq[T]
  # Copies retain an acyclic immutable snapshot; default differs from a validated empty set.
  OwnedSet*[T] = object
    data: SetData[T]
  # Dictionary storage copies keys/values as fixed values after every nested field and order check succeeds.
  DictionaryData[K, V] = ref object
    values: seq[Entry[K, V]]
  # Sets and dictionaries are distinct owners even when their scalar wire widths coincide.
  OwnedDictionary*[K, V] = object
    data: DictionaryData[K, V]
  # Success binds one complete retained owner to the exact consumed prefix for caller cursor advancement.
  CollectionRead*[T] = object
    owner*: T
    consumed*: int

# Approve each schema independently; arbitrary referenced children have no immutable scalar codec contract.
template requireScalar(T: typedesc) =
  static:
    doAssert T is JamNatural or T is CollectionUInt or T is CollectionBytes,
      "Unsupported collection scalar: use JamNatural, CollectionUInt or CollectionBytes"

# Naturals need at least one count/value octet; logical order is numeric rather than wire-byte order.
proc minimum(T: typedesc[JamNatural]): int = 1

# Fixed unsigned schemas have a compile-time supported width; invalid widths cannot instantiate a codec.
proc minimum[W: static int](T: typedesc[CollectionUInt[W]]): int =
  static: doAssert W >= 0 and W <= 8, "CollectionUInt width must be 0..8"
  W

# A fixed octet schema contributes exactly its configured number of bytes, including a possible empty value.
proc minimum[N: static int](T: typedesc[CollectionBytes[N]]): int = N

# Preserve complete primitive framing errors without publishing a default natural or partial child cursor.
proc read(T: typedesc[JamNatural], input: openArray[byte]): CollectionResult[ScalarRead[JamNatural]] =
  let parsed = natural.decode(input)
  # A natural's inverse rejects incomplete and overlong encodings before any parent ordering decision.
  if not parsed.ok:
    # Keep missing input distinct from a complete but noncanonical scalar.
    if parsed.error == natural.truncated:
      return CollectionResult[ScalarRead[JamNatural]](error: CollectionError.Truncated)
    else:
      # An overlong key/value cannot introduce another representation of an existing logical entry.
      return CollectionResult[ScalarRead[JamNatural]](error: CollectionError.NonCanonical)
  CollectionResult[ScalarRead[JamNatural]](error: CollectionError.None,
    value: ScalarRead[JamNatural](value: parsed.value, consumed: parsed.consumed))

# Fixed unsigned decoding copies one typed scalar after complete field presence is proved.
proc read[W: static int](T: typedesc[CollectionUInt[W]], input: openArray[byte]): CollectionResult[
    ScalarRead[CollectionUInt[W]]] =
  discard minimum(T)
  let parsed = decodeFixed(input, ByteWidth(W))
  # The compile-time width is valid, so an unsuccessful decoder here can only lack input bytes.
  if not parsed.ok: return CollectionResult[ScalarRead[T]](error: CollectionError.Truncated)
  CollectionResult[ScalarRead[T]](error: CollectionError.None,
    value: ScalarRead[T](value: T(value: parsed.value), consumed: W))

# Fixed octet decoding copies complete bytes without retaining any borrowed child span.
proc read[N: static int](T: typedesc[CollectionBytes[N]], input: openArray[byte]): CollectionResult[
    ScalarRead[CollectionBytes[N]]] =
  # Even an empty fixed byte string has a complete value; positive schemas require the entire extent.
  if input.len < N: return CollectionResult[ScalarRead[T]](error: CollectionError.Truncated)
  var value: T
  # Every copied octet belongs to the value-only result rather than the caller's storage.
  for i in 0..<N: value.bytes[i] = input[i]
  CollectionResult[ScalarRead[T]](error: CollectionError.None,
    value: ScalarRead[T](value: value, consumed: N))

# Canonical natural encoding is infallible over its complete nominal uint64 domain.
proc size(value: JamNatural): CollectionResult[int] =
  CollectionResult[int](error: CollectionError.None, value: natural.encode(value).len)

# Source fixed integers must fit their declared width; never silently truncate an overflowing late value.
proc size[W: static int](value: CollectionUInt[W]): CollectionResult[int] =
  discard minimum(typeof(value))
  let checked = encodeFixed(value.value, ByteWidth(W))
  # Width is a schema constant; source overflow is the only remaining primitive encoding failure.
  if not checked.ok: return CollectionResult[int](error: CollectionError.ValueOutOfRange)
  CollectionResult[int](error: CollectionError.None, value: W)

# Fixed byte arrays already own exactly their compile-time extent and need no content validation.
proc size[N: static int](value: CollectionBytes[N]): CollectionResult[int] =
  CollectionResult[int](error: CollectionError.None, value: N)

# Natural-key order compares the logical uint64 values, independently of prefix/wire byte order.
proc less(a, b: JamNatural): bool = uint64(a) < uint64(b)

# Little-endian scalar wire order is deliberately not used to sort numeric keys.
proc less[W: static int](a, b: CollectionUInt[W]): bool = uint64(a.value) < uint64(b.value)

# Fixed byte keys use ordinary lexicographic octet order; equal complete keys are not strictly increasing.
proc less[N: static int](a, b: CollectionBytes[N]): bool =
  # The first differing octet decides the logical order; later octets cannot reverse it.
  for i in 0..<N:
    # Equal leading octets defer the decision to the next position.
    if a.bytes[i] != b.bytes[i]: return a.bytes[i] < b.bytes[i]
  false

# Commit a previously preflighted natural into a caller destination at a proved cursor.
proc put(value: JamNatural, output: var openArray[byte], cursor: var int) =
  let encoded = natural.encode(value)
  # Canonical scalar bytes fit because parent source/capacity checks have already completed.
  for i in 0..<encoded.len: output[cursor+i] = encoded.bytes[i]
  cursor += encoded.len

# Commit an already width-checked unsigned value without another failure path or source allocation.
proc put[W: static int](value: CollectionUInt[W], output: var openArray[byte], cursor: var int) =
  let encoded = encodeFixed(value.value, ByteWidth(W))
  # Parent source validation proves the primitive success alternative and complete destination extent.
  for i in 0..<W: output[cursor+i] = encoded.encoded.bytes[i]
  cursor += W

# Commit fixed bytes exactly as supplied; keys have already been checked in logical order.
proc put[N: static int](value: CollectionBytes[N], output: var openArray[byte], cursor: var int) =
  # Copy only the schema's bytes, preserving all unrelated destination suffix capacity.
  for i in 0..<N: output[cursor+i] = value.bytes[i]
  cursor += N

# Detect intersection by address distance without overflowing endpoint sums, including empty encodings.
proc overlaps(a: pointer, an: int, b: pointer, bn: int): bool =
  # Empty source/destination ranges need no valid element address and cannot intersect.
  if an == 0 or bn == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  # The lower-address range supplies the extent in the distance comparison.
  if left <= right: right-left < uint(an)
  else:
    # Exchanging the ranges preserves the same overflow-free intersection test.
    left-right < uint(bn)

# Increment parent serialized extent only after checked host arithmetic and explicit byte policy.
proc grow(cursor: var int, amount: int, limits: CollectionLimits): CollectionError =
  # Child sizes are nonnegative, but their sum still needs a host-int overflow proof.
  if amount > high(int)-cursor: return CollectionError.LengthOverflow
  cursor += amount
  # Count/framing bytes consume this budget just like the actual elements.
  if uint64(cursor) > uint64(limits.maxBytes): return CollectionError.LimitExceeded
  CollectionError.None

# Establish a canonical count, count policy, typed allocation bound and minimum payload extent without allocation.
proc frame[T](input: openArray[byte], count: CollectionCount, variable: bool,
    stride: int, limits: CollectionLimits): CollectionResult[Layout] =
  var n = uint64(count)
  var offset = 0
  # Only variable sets and dictionaries carry a natural element/pair count.
  if variable:
    let prefix = natural.decode(input)
    # Prefix canonicality precedes all count, resource and child decisions.
    if not prefix.ok:
      # Missing prefix bytes cannot authorize any typed allocation or traversal.
      if prefix.error == natural.truncated: return CollectionResult[Layout](
          error: CollectionError.Truncated)
      else:
        # Overlong counts cannot encode a second representation of the same collection.
        return CollectionResult[Layout](error: CollectionError.NonCanonical)
    n = uint64(prefix.value)
    offset = prefix.consumed
  # Resource policy applies before narrowing count or multiplying a record stride.
  if n > uint64(limits.items): return CollectionResult[Layout](error: CollectionError.LimitExceeded)
  # Typed snapshots must have a representable byte extent, even when the wire schema has zero width.
  if n > uint64(high(int) div max(1, sizeof(T))): return CollectionResult[Layout](
      error: CollectionError.LengthOverflow)
  # A count discriminator alone can exceed the whole-prefix policy for an empty collection.
  if uint64(offset) > uint64(limits.maxBytes): return CollectionResult[Layout](
      error: CollectionError.LimitExceeded)
  # Division proves the minimum complete fields exist without count*stride overflow.
  if stride > 0 and n > uint64((input.len-offset) div stride):
    return CollectionResult[Layout](error: CollectionError.Truncated)
  CollectionResult[Layout](error: CollectionError.None,
    value: Layout(count: int(n), offset: offset, consumed: offset))

# Scan a complete set before allocating typed snapshot storage; duplicates/descending elements are rejected, never sorted.
proc scanSet[T](input: openArray[byte], count: CollectionCount, variable: bool,
    limits: CollectionLimits): CollectionResult[Layout] =
  requireScalar(T)
  let framed = frame[T](input, count, variable, minimum(T), limits)
  # Failed framing supplies no narrowed count or successful cursor.
  if framed.error != CollectionError.None: return framed
  var layout = framed.value
  var previous: T
  # Every scalar is fully decoded and compared in its logical domain before parent ownership can be granted.
  for i in 0..<layout.count:
    let parsed = read(T, input.toOpenArray(layout.consumed, input.high))
    # A malformed late child invalidates the whole parent without allocating an earlier partial set.
    if parsed.error != CollectionError.None: return CollectionResult[Layout](error: parsed.error)
    let error = grow(layout.consumed, parsed.value.consumed, limits)
    # Resource/host-extent failure precedes the next child and any snapshot allocation.
    if error != CollectionError.None: return CollectionResult[Layout](error: error)
    # Strict order enforces uniqueness; zero-width singleton schemas therefore reject their second key immediately.
    if i > 0 and not less(previous, parsed.value.value):
      return CollectionResult[Layout](error: CollectionError.NonCanonical)
    previous = parsed.value.value
  CollectionResult[Layout](error: CollectionError.None, value: layout)

# Capture value-only scalar snapshots after whole-set validation, while caller input remains stable for this call.
proc decodeSetImpl[T](input: openArray[byte], count: CollectionCount, variable: bool,
    limits: CollectionLimits): CollectionResult[CollectionRead[OwnedSet[T]]] =
  let scanned = scanSet[T](input, count, variable, limits)
  # Failed/default alternatives cannot publish a parent owner or partial element count.
  if scanned.error != CollectionError.None:
    return CollectionResult[CollectionRead[OwnedSet[T]]](error: scanned.error)
  let data = SetData[T](values: newSeq[T](scanned.value.count))
  var cursor = scanned.value.offset
  # Stable input and completed preflight make these value-copy reads infallible without retaining borrowed spans.
  for i in 0..<data.values.len:
    let parsed = read(T, input.toOpenArray(cursor, input.high))
    data.values[i] = parsed.value.value
    cursor += parsed.value.consumed
  CollectionResult[CollectionRead[OwnedSet[T]]](error: CollectionError.None,
    value: CollectionRead[OwnedSet[T]](owner: OwnedSet[T](data: data), consumed: cursor))

# Decode a set with caller-known cardinality and no count discriminator, as C.1.6 directly specifies.
proc decodeSet*[T](input: openArray[byte], count: CollectionCount,
    limits: CollectionLimits): CollectionResult[CollectionRead[OwnedSet[T]]] =
  decodeSetImpl[T](input, count, false, limits)

# Decode an explicitly variable set using C.1.3's canonical natural cardinality discriminator.
proc decodeVariableSet*[T](input: openArray[byte],
    limits: CollectionLimits): CollectionResult[CollectionRead[OwnedSet[T]]] =
  decodeSetImpl[T](input, CollectionCount(0), true, limits)

# Validate every source scalar and strict logical order before capacity, aliases or the first committed byte.
proc encodeSetImpl[T](values: openArray[T], count: CollectionCount, variable: bool,
    limits: CollectionLimits, output: var openArray[byte]): CollectionResult[int] =
  requireScalar(T)
  discard minimum(T)
  # Fixed schemas cannot silently drop, duplicate or invent caller source elements.
  if uint64(values.len) != uint64(count): return CollectionResult[int](
      error: CollectionError.InvalidCount)
  # Count and typed storage extents must be bounded before source traversal or alias arithmetic.
  if uint64(count) > uint64(limits.items): return CollectionResult[int](
      error: CollectionError.LimitExceeded)
  if values.len > high(int) div max(1, sizeof(T)): return CollectionResult[int](
      error: CollectionError.LengthOverflow)
  let prefix = natural.encode(JamNatural(uint64(count)))
  var total = 0
  # Only explicitly variable terms emit a cardinality prefix.
  if variable: total = prefix.len
  # Even an empty prefixed set must fit the serialized-byte policy.
  if uint64(total) > uint64(limits.maxBytes): return CollectionResult[int](
      error: CollectionError.LimitExceeded)
  # Validate the final source element before writing an earlier prefix or element.
  for i, value in values:
    let measured = size(value)
    # Late fixed-width overflow rejects the whole operation without changing output.
    if measured.error != CollectionError.None: return CollectionResult[int](error: measured.error)
    let error = grow(total, measured.value, limits)
    # Host/budget bounds precede capacity, ensuring caller output size cannot conceal invalid sources.
    if error != CollectionError.None: return CollectionResult[int](error: error)
    # Reject both duplicate and descending elements; canonicalization is the caller's explicit responsibility.
    if i > 0 and not less(values[i-1], value): return CollectionResult[int](
        error: CollectionError.NonCanonical)
  # Whole-parent capacity is established before taking output addresses or committing any child.
  if output.len < total: return CollectionResult[int](error: CollectionError.OutputTooSmall)
  # The whole written destination cannot overwrite any source scalar, including a later key.
  if values.len > 0 and total > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(T),
      addr output[0], total):
    return CollectionResult[int](error: CollectionError.AliasedBuffers)
  var cursor = 0
  # A fixed empty encoding needs no output pointer or count byte.
  if variable:
    # Canonical framing is committed only after every nested source and destination check passes.
    for i in 0..<prefix.len: output[i] = prefix.bytes[i]
    cursor = prefix.len
  # All scalar writes are infallible after complete stable-source preflight.
  for value in values: put(value, output, cursor)
  CollectionResult[int](error: CollectionError.None, value: cursor)

# Encode a fixed-cardinality canonical set without adding an implicit sequence count.
proc encodeSet*[T](values: openArray[T], count: CollectionCount, limits: CollectionLimits,
    output: var openArray[byte]): CollectionResult[int] =
  encodeSetImpl(values, count, false, limits, output)

# Encode an explicitly variable canonical set with one natural element count.
proc encodeVariableSet*[T](values: openArray[T], limits: CollectionLimits,
    output: var openArray[byte]): CollectionResult[int] =
  encodeSetImpl(values, CollectionCount(uint64(values.len)), true, limits, output)

# Scan every key/value in dictionary order before allocating a retained typed record array.
proc scanDictionary[K, V](input: openArray[byte], limits: CollectionLimits): CollectionResult[Layout] =
  requireScalar(K)
  requireScalar(V)
  let keySize = minimum(K)
  let valueSize = minimum(V)
  # Compile-time schemas still need a safe minimum-stride sum on the target host.
  if valueSize > high(int)-keySize: return CollectionResult[Layout](
      error: CollectionError.LengthOverflow)
  let framed = frame[Entry[K, V]](input, CollectionCount(0), true, keySize+valueSize, limits)
  # Framing failure cannot publish a narrowed count or initialized cursor.
  if framed.error != CollectionError.None: return framed
  var layout = framed.value
  var previous: K
  # Values are serialized beside their matching keys, not in a separate value sequence or additional blob frame.
  for i in 0..<layout.count:
    let key = read(K, input.toOpenArray(layout.consumed, input.high))
    # Missing or noncanonical keys invalidate the complete dictionary.
    if key.error != CollectionError.None: return CollectionResult[Layout](error: key.error)
    var error = grow(layout.consumed, key.value.consumed, limits)
    # Bound key traversal before inspecting its matching value.
    if error != CollectionError.None: return CollectionResult[Layout](error: error)
    # Dictionary order is exclusively by logical key; values need not be sorted or unique.
    if i > 0 and not less(previous, key.value.value): return CollectionResult[Layout](
        error: CollectionError.NonCanonical)
    let value = read(V, input.toOpenArray(layout.consumed, input.high))
    # A malformed final value cannot expose earlier complete key/value pairs.
    if value.error != CollectionError.None: return CollectionResult[Layout](error: value.error)
    error = grow(layout.consumed, value.value.consumed, limits)
    # The byte policy includes the complete final value before granting ownership.
    if error != CollectionError.None: return CollectionResult[Layout](error: error)
    previous = key.value.value
  CollectionResult[Layout](error: CollectionError.None, value: layout)

# Decode a naturally count-prefixed dictionary into an immutable acyclic typed snapshot.
proc decodeDictionary*[K, V](input: openArray[byte], limits: CollectionLimits): CollectionResult[
    CollectionRead[OwnedDictionary[K, V]]] =
  let scanned = scanDictionary[K, V](input, limits)
  # Parent ownership is granted only after all keys, values, ordering and extents pass.
  if scanned.error != CollectionError.None:
    return CollectionResult[CollectionRead[OwnedDictionary[K, V]]](error: scanned.error)
  let data = DictionaryData[K, V](values: newSeq[Entry[K, V]](scanned.value.count))
  var cursor = scanned.value.offset
  # The second stable-input pass copies only complete fixed values; no caller storage is retained.
  for i in 0..<data.values.len:
    let key = read(K, input.toOpenArray(cursor, input.high))
    cursor += key.value.consumed
    let value = read(V, input.toOpenArray(cursor, input.high))
    cursor += value.value.consumed
    data.values[i] = Entry[K, V](key: key.value.value, value: value.value.value)
  CollectionResult[CollectionRead[OwnedDictionary[K, V]]](error: CollectionError.None,
    value: CollectionRead[OwnedDictionary[K, V]](owner: OwnedDictionary[K, V](data: data),
        consumed: cursor))

# Encode an already logically ordered dictionary atomically; duplicate keys are errors, never last-value-wins updates.
proc encodeDictionary*[K, V](values: openArray[Entry[K, V]], limits: CollectionLimits,
    output: var openArray[byte]): CollectionResult[int] =
  requireScalar(K)
  requireScalar(V)
  discard minimum(K)
  discard minimum(V)
  # Count policy and typed source extent precede all source iteration and pointer arithmetic.
  if uint64(values.len) > uint64(limits.items): return CollectionResult[int](
      error: CollectionError.LimitExceeded)
  if values.len > high(int) div max(1, sizeof(Entry[K, V])): return CollectionResult[int](
      error: CollectionError.LengthOverflow)
  let prefix = natural.encode(JamNatural(uint64(values.len)))
  var total = int(prefix.len)
  # A zero-pair dictionary still emits its count and must fit the complete-prefix byte budget.
  if uint64(total) > uint64(limits.maxBytes): return CollectionResult[int](
      error: CollectionError.LimitExceeded)
  # Preflight both fields of every pair before committing any count/key/value byte.
  for i, pair in values:
    let keySize = size(pair.key)
    # Width-overflow in even the final key must preserve the whole output.
    if keySize.error != CollectionError.None: return CollectionResult[int](error: keySize.error)
    var error = grow(total, keySize.value, limits)
    # Key byte extent contributes to the aggregate resource limit before its value is measured.
    if error != CollectionError.None: return CollectionResult[int](error: error)
    # Keys alone determine canonical order; rejecting equality enforces uniqueness.
    if i > 0 and not less(values[i-1].key, pair.key): return CollectionResult[int](
        error: CollectionError.NonCanonical)
    let valueSize = size(pair.value)
    # A bad late value cannot leave an earlier pair or discriminator in the destination.
    if valueSize.error != CollectionError.None: return CollectionResult[int](error: valueSize.error)
    error = grow(total, valueSize.value, limits)
    # Checked growth prevents wrapped capacity/alias calculations.
    if error != CollectionError.None: return CollectionResult[int](error: error)
  # Source errors precede output capacity; no addresses are needed for undersized outputs.
  if output.len < total: return CollectionResult[int](error: CollectionError.OutputTooSmall)
  # Protect all key/value source records against every byte of the written destination.
  if values.len > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(Entry[K, V]), addr output[
      0], total):
    return CollectionResult[int](error: CollectionError.AliasedBuffers)
  # Every potential failure has passed before emitting the one dictionary cardinality discriminator.
  for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  var cursor = int(prefix.len)
  # Preserve key/value association and caller-supplied value order exactly.
  for pair in values:
    put(pair.key, output, cursor)
    put(pair.value, output, cursor)
  CollectionResult[int](error: CollectionError.None, value: cursor)

# Return copied set cardinality through the matching retained owner, without exposing mutable storage.
proc setCount*[T](owner: OwnedSet[T]): CollectionResult[CollectionCount] =
  # Defaults cannot masquerade as a validated empty set.
  if owner.data.isNil: return CollectionResult[CollectionCount](error: CollectionError.InvalidOwner)
  CollectionResult[CollectionCount](error: CollectionError.None, value: CollectionCount(uint64(
      owner.data.values.len)))

# Copy one complete scalar value; supported types contain no mutable referenced payload to leak.
proc setAt*[T](owner: OwnedSet[T], index: int): CollectionResult[T] =
  # Check ownership before accessing the private sequence, then reject signed index misuse.
  if owner.data.isNil: return CollectionResult[T](error: CollectionError.InvalidOwner)
  if index < 0 or index >= owner.data.values.len: return CollectionResult[T](
      error: CollectionError.InvalidIndex)
  CollectionResult[T](error: CollectionError.None, value: owner.data.values[index])

# Re-emit a retained set with fixed cardinality under the caller's current policy and destination constraints.
proc encodeOwnedSet*[T](owner: OwnedSet[T], count: CollectionCount, limits: CollectionLimits,
    output: var openArray[byte]): CollectionResult[int] =
  # Missing ownership must not authorize an empty source or expose a default sequence.
  if owner.data.isNil: return CollectionResult[int](error: CollectionError.InvalidOwner)
  encodeSet(owner.data.values, count, limits, output)

# Reframe a retained set as an explicitly variable term without copying out or exporting its immutable elements.
proc encodeOwnedVariableSet*[T](owner: OwnedSet[T], limits: CollectionLimits,
    output: var openArray[byte]): CollectionResult[int] =
  # Default snapshots contain no validated elements, even when a caller requests an empty frame.
  if owner.data.isNil: return CollectionResult[int](error: CollectionError.InvalidOwner)
  encodeVariableSet(owner.data.values, limits, output)

# Copy complete dictionary cardinality without exporting the key/value array or caller input coordinates.
proc dictionaryCount*[K, V](owner: OwnedDictionary[K, V]): CollectionResult[CollectionCount] =
  # Defaults differ from successfully captured zero-pair dictionaries.
  if owner.data.isNil: return CollectionResult[CollectionCount](error: CollectionError.InvalidOwner)
  CollectionResult[CollectionCount](error: CollectionError.None, value: CollectionCount(uint64(
      owner.data.values.len)))

# Copy one whole key/value pair through its matching owner; callers cannot mutate private snapshot fields.
proc dictionaryAt*[K, V](owner: OwnedDictionary[K, V], index: int): CollectionResult[Entry[K, V]] =
  # Ownership and signed bounds are ordinary typed failures rather than unchecked field/index accesses.
  if owner.data.isNil: return CollectionResult[Entry[K, V]](error: CollectionError.InvalidOwner)
  if index < 0 or index >= owner.data.values.len: return CollectionResult[Entry[K, V]](
      error: CollectionError.InvalidIndex)
  CollectionResult[Entry[K, V]](error: CollectionError.None, value: owner.data.values[index])

# Re-emit immutable dictionary values with all current limits, complete capacity and aliases checked again.
proc encodeOwnedDictionary*[K, V](owner: OwnedDictionary[K, V], limits: CollectionLimits,
    output: var openArray[byte]): CollectionResult[int] =
  # Default handles do not imply validated empty dictionaries.
  if owner.data.isNil: return CollectionResult[int](error: CollectionError.InvalidOwner)
  encodeDictionary(owner.data.values, limits, output)
