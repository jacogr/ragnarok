# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 C.1.3/C.1.5/C.1.6 typed canonical collections; see spec/collections.md.
##
## Exposes typed scalar schemas, canonical set/dictionary codecs and immutable collection
## accessors.

import std/assertions
import ./[natural, fixed_unsigned, bounded]

type
  CollectionCount* = distinct uint64 ## Schema cardinality is distinct from both resource ceilings and serialized byte extents.
  CollectionUInt*[width: static[int]] = object ## A fixed-width unsigned scalar keeps its schema in the type, including the valid zero-width domain.
    value*: FixedUnsigned
  CollectionBytes*[size: static[int]] = object ## Fixed octets sort lexicographically by octet, with no length discriminator on individual elements.
    bytes*: array[size, byte]
    # A zero-wire-width scalar needs one physical unit for safe standard sequence capacity arithmetic.
    unit: array[ord(size == 0), byte]
  CollectionFamily* = JamNatural | CollectionUInt[0] | CollectionUInt[1] | CollectionUInt[2] | ## Application-defined referenced types cannot extend this closed scalar family gate.
    CollectionUInt[3] | CollectionUInt[4] | CollectionUInt[5] | CollectionUInt[6] |
    CollectionUInt[7] | CollectionUInt[8] | CollectionBytes
  Entry*[K, V] = object ## Dictionary keys and values retain their separate compile-time schemas and logical roles.
    key*: K
    value*: V
  CollectionLimits* = object ## Explicit caller policy bounds both entry count and the complete consumed/written parent prefix.
    items*: ElementLimit
    maxBytes*: ByteLimit
  CollectionError* {.pure.} = enum ## Default/error alternatives never carry a value, owner, initialized count or partial cursor.
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, InvalidCount,
    ValueOutOfRange, LengthOverflow, OutputTooSmall, AliasedBuffers, InvalidOwner, InvalidIndex
  CollectionResult*[T] = object ## Select complete success before reading its copied scalar, retained owner or byte extent.
    case status: CollectionError
    of None:
      # Only successful operations expose complete data/progress.
      completed: T
    else:
      # Failed/default operations expose their reason alone.
      discard
  ScalarRead*[T] = object ## Child decoding returns a complete fixed value with its exact canonical prefix extent.
    value*: T
    consumed*: int
  # Private layout retains no input pointer and authorizes capture only after complete validation.
  Layout = object
    count, offset, consumed: int
  # Immutable typed storage contains only supported value-only scalar schemas, never public mutable sequences.
  SetData[T] = ref object
    values: seq[T]
  OwnedSet*[T] = object ## Copies retain an acyclic immutable snapshot; default differs from a validated empty set.
    data: nil SetData[T]
  # Dictionary storage copies keys/values as fixed values after every nested field and order check succeeds.
  DictionaryData[K, V] = ref object
    values: seq[Entry[K, V]]
  OwnedDictionary*[K, V] = object ## Sets and dictionaries are distinct owners even when their scalar wire widths coincide.
    data: nil DictionaryData[K, V]
  CollectionRead*[T] = object ## Success binds one complete retained owner to the exact consumed prefix for caller cursor advancement.
    owner*: T
    consumed*: int

func error*[T](value: CollectionResult[T]): CollectionError =
  ## Outcomes remain read-only; only complete success authorizes values, owners or progress.
  value.status
func value*[T](value: CollectionResult[T]): T {.inline, requires: value.status ==
    CollectionError.None.} =
  ## Supported contracts replace unchecked raw variant-field reads on this compiler.
  value.completed

proc scalarMinimum*(T: typedesc[JamNatural]): int =
  ## Naturals need at least one count/value octet; logical order is numeric rather than wire-byte order.
  1

proc scalarMinimum*[W: static[int]](T: typedesc[CollectionUInt[W]]): int {.requires: W >= 0 and W <= 8.} =
  ## Fixed unsigned schemas have a compile-time supported width; invalid widths cannot instantiate a codec.
  W

proc scalarMinimum*[N: static[int]](T: typedesc[CollectionBytes[N]]): int =
  ## A fixed octet schema contributes exactly its configured number of bytes, including a possible empty value.
  N

proc readScalar*(T: typedesc[JamNatural], input: openArray[byte]): CollectionResult[ScalarRead[JamNatural]] =
  ## Preserve complete primitive framing errors without publishing a default natural or partial child cursor.
  let parsed = natural.decode(input)
  # A natural's inverse rejects incomplete and overlong encodings before any parent ordering decision.
  if not parsed.ok:
    # Keep missing input distinct from a complete but noncanonical scalar.
    if parsed.error == natural.truncated:
      return CollectionResult[ScalarRead[JamNatural]](status: CollectionError.Truncated)
    else:
      # An overlong key/value cannot introduce another representation of an existing logical entry.
      return CollectionResult[ScalarRead[JamNatural]](status: CollectionError.NonCanonical)
  CollectionResult[ScalarRead[JamNatural]](status: CollectionError.None,
    completed: ScalarRead[JamNatural](value: parsed.value, consumed: parsed.consumed))

proc readScalar*[W: static[int]](T: typedesc[CollectionUInt[W]], input: openArray[
    byte]): CollectionResult[ScalarRead[CollectionUInt[W]]] =
  ## Fixed unsigned decoding copies one typed scalar after complete field presence is proved.
  discard scalarMinimum(T)
  let parsed = decodeFixed(input, ByteWidth(W))
  # The compile-time width is valid, so an unsuccessful decoder here can only lack input bytes.
  if not parsed.ok: return CollectionResult[ScalarRead[CollectionUInt[W]]](
      status: CollectionError.Truncated)
  CollectionResult[ScalarRead[CollectionUInt[W]]](status: CollectionError.None,
    completed: ScalarRead[CollectionUInt[W]](value: CollectionUInt[W](value: parsed.value), consumed: W))

proc readScalar*[N: static[int]](T: typedesc[CollectionBytes[N]], input: openArray[
    byte]): CollectionResult[ScalarRead[CollectionBytes[N]]] =
  ## Fixed octet decoding copies complete bytes without retaining any borrowed child span.
  # Even an empty fixed byte string has a complete value; positive schemas require the entire extent.
  if input.len < N: return CollectionResult[ScalarRead[CollectionBytes[N]]](
      status: CollectionError.Truncated)
  var value: CollectionBytes[N] = default(CollectionBytes[N])
  # Every copied octet belongs to the value-only result rather than the caller's storage.
  for i in 0..<N: value.bytes[i] = input[i]
  CollectionResult[ScalarRead[CollectionBytes[N]]](status: CollectionError.None,
    completed: ScalarRead[CollectionBytes[N]](value: value, consumed: N))

proc scalarSize*(value: JamNatural): CollectionResult[int] =
  ## Canonical natural encoding is infallible over its complete nominal uint64 domain.
  CollectionResult[int](status: CollectionError.None, completed: natural.encode(value).len)

proc scalarSize*[W: static[int]](value: CollectionUInt[W]): CollectionResult[int] =
  ## Source fixed integers must fit their declared width; never silently truncate an overflowing late value.
  discard scalarMinimum(typeof(value))
  let checked = encodeFixed(value.value, ByteWidth(W))
  # Width is a schema constant; source overflow is the only remaining primitive encoding failure.
  if not checked.ok: return CollectionResult[int](status: CollectionError.ValueOutOfRange)
  CollectionResult[int](status: CollectionError.None, completed: W)

proc scalarSize*[N: static[int]](value: CollectionBytes[N]): CollectionResult[int] =
  ## Fixed byte arrays already own exactly their compile-time extent and need no content validation.
  CollectionResult[int](status: CollectionError.None, completed: N)

proc scalarLess*(a, b: JamNatural): bool =
  ## Natural-key order compares the logical uint64 values, independently of prefix/wire byte order.
  uint64(a) < uint64(b)

proc scalarLess*[W: static[int]](a, b: CollectionUInt[W]): bool =
  ## Little-endian scalar wire order is deliberately not used to sort numeric keys.
  uint64(a.value) < uint64(b.value)

proc scalarLess*[N: static[int]](a, b: CollectionBytes[N]): bool =
  ## Fixed byte keys use ordinary lexicographic octet order; equal complete keys are not strictly increasing.
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
proc put[W: static[int]](value: CollectionUInt[W], output: var openArray[byte], cursor: var int) =
  let encoded = encodeFixed(value.value, ByteWidth(W))
  # Parent source validation proves the primitive success alternative and complete destination extent.
  for i in 0..<W: output[cursor+i] = encoded.encoded.bytes[i]
  cursor += W

# Commit fixed bytes exactly as supplied; keys have already been checked in logical order.
proc put[N: static[int]](value: CollectionBytes[N], output: var openArray[byte], cursor: var int) =
  # Copy only the schema's bytes, preserving all unrelated destination suffix capacity.
  for i in 0..<N: output[cursor+i] = value.bytes[i]
  cursor += N

proc encodeScalar*(value: JamNatural, output: var openArray[byte]): CollectionResult[int] =
  ## Encode one copied JamNatural atomically for generic composition, with typed source/capacity failures.
  let measured = scalarSize(value)
  # Invalid scalar sources never authorize a partial field write.
  if measured.error != CollectionError.None: return measured
  # Prove the whole field fits before copying any byte.
  if output.len < measured.value: return CollectionResult[int](
      status: CollectionError.OutputTooSmall)
  let copied = value
  var cursor = 0
  put(copied, output, cursor)
  CollectionResult[int](status: CollectionError.None, completed: cursor)

proc encodeScalar*[W: static[int]](value: CollectionUInt[W], output: var openArray[
    byte]): CollectionResult[int] =
  ## Encode one copied CollectionUInt[W] atomically for generic composition, with typed source/capacity failures.
  let measured = scalarSize(value)
  # Invalid scalar sources never authorize a partial field write.
  if measured.error != CollectionError.None: return measured
  # Prove the whole field fits before copying any byte.
  if output.len < measured.value: return CollectionResult[int](
      status: CollectionError.OutputTooSmall)
  let copied = value
  var cursor = 0
  put(copied, output, cursor)
  CollectionResult[int](status: CollectionError.None, completed: cursor)

proc encodeScalar*[N: static[int]](value: CollectionBytes[N], output: var openArray[
    byte]): CollectionResult[int] =
  ## Encode one copied CollectionBytes[N] atomically for generic composition, with typed source/capacity failures.
  let measured = scalarSize(value)
  # Invalid scalar sources never authorize a partial field write.
  if measured.error != CollectionError.None: return measured
  # Prove the whole field fits before copying any byte.
  if output.len < measured.value: return CollectionResult[int](
      status: CollectionError.OutputTooSmall)
  let copied = value
  var cursor = 0
  put(copied, output, cursor)
  CollectionResult[int](status: CollectionError.None, completed: cursor)

type
  CollectionScalar* = concept ## Exported checked scalar operations let Nimony verify generic callers across module boundaries.
    proc default(T: typedesc[Self]): Self
    proc scalarMinimum(T: typedesc[Self]): int
    proc readScalar(T: typedesc[Self], input: openArray[byte]): CollectionResult[ScalarRead[Self]]
    proc scalarSize(value: Self): CollectionResult[int]
    proc scalarLess(a, b: Self): bool
    proc encodeScalar(value: Self, output: var openArray[byte]): CollectionResult[int]

# Parent preflight already proves scalar encoding succeeds; keep cursor commits inside this module.
proc put[T: CollectionScalar and CollectionFamily](value: T, output: var openArray[byte],
    cursor: var int) =
  let encoded = encodeScalar(value, output.toOpenArray(cursor, output.high))
  assert encoded.error == CollectionError.None # Whole-parent preflight establishes this complete field.
  cursor += encoded.value

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
          status: CollectionError.Truncated)
      else:
        # Overlong counts cannot encode a second representation of the same collection.
        return CollectionResult[Layout](status: CollectionError.NonCanonical)
    n = uint64(prefix.value)
    offset = prefix.consumed
  # Resource policy applies before narrowing count or multiplying a record stride.
  if n > uint64(limits.items): return CollectionResult[Layout](
      status: CollectionError.LimitExceeded)
  # Typed snapshots must have a representable byte extent, even when the wire schema has zero width.
  if n > uint64(high(int) div max(1, sizeof(T))): return CollectionResult[Layout](
      status: CollectionError.LengthOverflow)
  # A count discriminator alone can exceed the whole-prefix policy for an empty collection.
  if uint64(offset) > uint64(limits.maxBytes): return CollectionResult[Layout](
      status: CollectionError.LimitExceeded)
  # Division proves the minimum complete fields exist without count*stride overflow.
  if stride > 0 and n > uint64((input.len-offset) div stride):
    return CollectionResult[Layout](status: CollectionError.Truncated)
  CollectionResult[Layout](status: CollectionError.None,
    completed: Layout(count: int(n), offset: offset, consumed: offset))

# Scan a complete set before allocating typed snapshot storage; duplicates/descending elements are rejected, never sorted.
proc scanSet[T: CollectionScalar and CollectionFamily](input: openArray[byte],
    count: CollectionCount, variable: bool, limits: CollectionLimits): CollectionResult[Layout] =
  let framed = frame[T](input, count, variable, scalarMinimum(T), limits)
  # Failed framing supplies no narrowed count or successful cursor.
  if framed.error != CollectionError.None: return framed
  var layout = framed.value
  var previous: T = default(T)
  # Every scalar is fully decoded and compared in its logical domain before parent ownership can be granted.
  for i in 0..<layout.count:
    let parsed = readScalar(T, input.toOpenArray(layout.consumed, input.high))
    # A malformed late child invalidates the whole parent without allocating an earlier partial set.
    if parsed.error != CollectionError.None: return CollectionResult[Layout](status: parsed.error)
    let error = grow(layout.consumed, parsed.value.consumed, limits)
    # Resource/host-extent failure precedes the next child and any snapshot allocation.
    if error != CollectionError.None: return CollectionResult[Layout](status: error)
    # Strict order enforces uniqueness; zero-width singleton schemas therefore reject their second key immediately.
    if i > 0 and not scalarLess(previous, parsed.value.value):
      return CollectionResult[Layout](status: CollectionError.NonCanonical)
    previous = parsed.value.value
  CollectionResult[Layout](status: CollectionError.None, completed: layout)

# Capture value-only scalar snapshots after whole-set validation, while caller input remains stable for this call.
proc decodeSetImpl[T: CollectionScalar and CollectionFamily](input: openArray[byte],
    count: CollectionCount, variable: bool,

limits: CollectionLimits): CollectionResult[CollectionRead[OwnedSet[T]]] =
  let scanned = scanSet[T](input, count, variable, limits)
  # Failed/default alternatives cannot publish a parent owner or partial element count.
  if scanned.error != CollectionError.None:
    return CollectionResult[CollectionRead[OwnedSet[T]]](status: scanned.error)
  let data = SetData[T](values: newSeq[T](scanned.value.count))
  var cursor = scanned.value.offset
  # Stable input and completed preflight make these value-copy reads infallible without retaining borrowed spans.
  for i in 0..<data.values.len:
    let parsed = readScalar(T, input.toOpenArray(cursor, input.high))
    data.values[i] = parsed.value.value
    cursor += parsed.value.consumed
  CollectionResult[CollectionRead[OwnedSet[T]]](status: CollectionError.None,
    completed: CollectionRead[OwnedSet[T]](owner: OwnedSet[T](data: data), consumed: cursor))

proc decodeSet*[T: CollectionScalar and CollectionFamily](input: openArray[byte],
    count: CollectionCount, limits: CollectionLimits): CollectionResult[CollectionRead[OwnedSet[T]]] =
  ## Decode a set with caller-known cardinality and no count discriminator, as C.1.6 directly specifies.
  decodeSetImpl[T](input, count, false, limits)

proc decodeVariableSet*[T: CollectionScalar and CollectionFamily](input: openArray[byte],
    limits: CollectionLimits): CollectionResult[CollectionRead[OwnedSet[T]]] =
  ## Decode an explicitly variable set using C.1.3's canonical natural cardinality discriminator.
  decodeSetImpl[T](input, CollectionCount(0), true, limits)

# Validate every source scalar and strict logical order before capacity, aliases or the first committed byte.
proc encodeSetImpl[T: CollectionScalar and CollectionFamily](values: openArray[T],
    count: CollectionCount, variable: bool, limits: CollectionLimits, output: var openArray[
        byte]): CollectionResult[int] =
  discard scalarMinimum(T)
  # Fixed schemas cannot silently drop, duplicate or invent caller source elements.
  if uint64(values.len) != uint64(count): return CollectionResult[int](
      status: CollectionError.InvalidCount)
  # Count and typed storage extents must be bounded before source traversal or alias arithmetic.
  if uint64(count) > uint64(limits.items): return CollectionResult[int](
      status: CollectionError.LimitExceeded)
  if values.len > high(int) div max(1, sizeof(T)): return CollectionResult[int](
      status: CollectionError.LengthOverflow)
  let prefix = natural.encode(JamNatural(uint64(count)))
  var total = 0
  # Only explicitly variable terms emit a cardinality prefix.
  if variable: total = prefix.len
  # Even an empty prefixed set must fit the serialized-byte policy.
  if uint64(total) > uint64(limits.maxBytes): return CollectionResult[int](
      status: CollectionError.LimitExceeded)
  # Validate the final source element before writing an earlier prefix or element.
  for i, value in values:
    let measured = scalarSize(value)
    # Late fixed-width overflow rejects the whole operation without changing output.
    if measured.error != CollectionError.None: return CollectionResult[int](status: measured.error)
    let error = grow(total, measured.value, limits)
    # Host/budget bounds precede capacity, ensuring caller output size cannot conceal invalid sources.
    if error != CollectionError.None: return CollectionResult[int](status: error)
    # Reject both duplicate and descending elements; canonicalization is the caller's explicit responsibility.
    if i > 0 and not scalarLess(values[i-1], value): return CollectionResult[int](
        status: CollectionError.NonCanonical)
  # Whole-parent capacity is established before taking output addresses or committing any child.
  if output.len < total: return CollectionResult[int](status: CollectionError.OutputTooSmall)
  # The whole written destination cannot overwrite any source scalar, including a later key.
  if values.len > 0 and total > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(T),
      addr output[0], total):
    return CollectionResult[int](status: CollectionError.AliasedBuffers)
  var cursor = 0
  # A fixed empty encoding needs no output pointer or count byte.
  if variable:
    # Canonical framing is committed only after every nested source and destination check passes.
    for i in 0..<prefix.len: output[i] = prefix.bytes[i]
    cursor = prefix.len
  # All scalar writes are infallible after complete stable-source preflight.
  for value in values: put(value, output, cursor)
  CollectionResult[int](status: CollectionError.None, completed: cursor)

# Encode a fixed-cardinality canonical set without adding an implicit sequence count.
proc encodeSet*[T: CollectionScalar and CollectionFamily](values: openArray[T],
    count: CollectionCount, limits: CollectionLimits,

output: var openArray[byte]): CollectionResult[int] =
  encodeSetImpl(values, count, false, limits, output)

proc encodeVariableSet*[T: CollectionScalar and CollectionFamily](values: openArray[T],
    limits: CollectionLimits, output: var openArray[byte]): CollectionResult[int] =
  ## Encode an explicitly variable canonical set with one natural element count.
  encodeSetImpl(values, CollectionCount(uint64(values.len)), true, limits, output)

# Scan every key/value in dictionary order before allocating a retained typed record array.
proc scanDictionary[K, V: CollectionScalar and CollectionFamily](input: openArray[byte],
    limits: CollectionLimits): CollectionResult[Layout] =
  let keySize = scalarMinimum(K)
  let valueSize = scalarMinimum(V)
  # Compile-time schemas still need a safe minimum-stride sum on the target host.
  if valueSize > high(int)-keySize: return CollectionResult[Layout](
      status: CollectionError.LengthOverflow)
  let framed = frame[Entry[K, V]](input, CollectionCount(0), true, keySize+valueSize, limits)
  # Framing failure cannot publish a narrowed count or initialized cursor.
  if framed.error != CollectionError.None: return framed
  var layout = framed.value
  var previous: K = default(K)
  # Values are serialized beside their matching keys, not in a separate value sequence or additional blob frame.
  for i in 0..<layout.count:
    let key = readScalar(K, input.toOpenArray(layout.consumed, input.high))
    # Missing or noncanonical keys invalidate the complete dictionary.
    if key.error != CollectionError.None: return CollectionResult[Layout](status: key.error)
    var error = grow(layout.consumed, key.value.consumed, limits)
    # Bound key traversal before inspecting its matching value.
    if error != CollectionError.None: return CollectionResult[Layout](status: error)
    # Dictionary order is exclusively by logical key; values need not be sorted or unique.
    if i > 0 and not scalarLess(previous, key.value.value): return CollectionResult[Layout](
        status: CollectionError.NonCanonical)
    let value = readScalar(V, input.toOpenArray(layout.consumed, input.high))
    # A malformed final value cannot expose earlier complete key/value pairs.
    if value.error != CollectionError.None: return CollectionResult[Layout](status: value.error)
    error = grow(layout.consumed, value.value.consumed, limits)
    # The byte policy includes the complete final value before granting ownership.
    if error != CollectionError.None: return CollectionResult[Layout](status: error)
    previous = key.value.value
  CollectionResult[Layout](status: CollectionError.None, completed: layout)

proc decodeDictionary*[K, V: CollectionScalar and CollectionFamily](input: openArray[byte],
    limits: CollectionLimits): CollectionResult[CollectionRead[OwnedDictionary[K, V]]] =
  ## Decode a naturally count-prefixed dictionary into an immutable acyclic typed snapshot.
  let scanned = scanDictionary[K, V](input, limits)
  # Parent ownership is granted only after all keys, values, ordering and extents pass.
  if scanned.error != CollectionError.None:
    return CollectionResult[CollectionRead[OwnedDictionary[K, V]]](status: scanned.error)
  let data = DictionaryData[K, V](values: newSeq[Entry[K, V]](scanned.value.count))
  var cursor = scanned.value.offset
  # The second stable-input pass copies only complete fixed values; no caller storage is retained.
  for i in 0..<data.values.len:
    let key = readScalar(K, input.toOpenArray(cursor, input.high))
    cursor += key.value.consumed
    let value = readScalar(V, input.toOpenArray(cursor, input.high))
    cursor += value.value.consumed
    data.values[i] = Entry[K, V](key: key.value.value, value: value.value.value)
  CollectionResult[CollectionRead[OwnedDictionary[K, V]]](status: CollectionError.None,
    completed: CollectionRead[OwnedDictionary[K, V]](owner: OwnedDictionary[K, V](data: data),
        consumed: cursor))

proc encodeDictionary*[K, V: CollectionScalar and CollectionFamily](values: openArray[Entry[K, V]],
    limits: CollectionLimits, output: var openArray[byte]): CollectionResult[int] =
  ## Encode an already logically ordered dictionary atomically; duplicate keys are errors, never last-value-wins updates.
  discard scalarMinimum(K)
  discard scalarMinimum(V)
  # Count policy and typed source extent precede all source iteration and pointer arithmetic.
  if uint64(values.len) > uint64(limits.items): return CollectionResult[int](
      status: CollectionError.LimitExceeded)
  if values.len > high(int) div max(1, sizeof(Entry[K, V])): return CollectionResult[int](
      status: CollectionError.LengthOverflow)
  let prefix = natural.encode(JamNatural(uint64(values.len)))
  var total = int(prefix.len)
  # A zero-pair dictionary still emits its count and must fit the complete-prefix byte budget.
  if uint64(total) > uint64(limits.maxBytes): return CollectionResult[int](
      status: CollectionError.LimitExceeded)
  # Preflight both fields of every pair before committing any count/key/value byte.
  for i, pair in values:
    let keySize = scalarSize(pair.key)
    # Width-overflow in even the final key must preserve the whole output.
    if keySize.error != CollectionError.None: return CollectionResult[int](status: keySize.error)
    var error = grow(total, keySize.value, limits)
    # Key byte extent contributes to the aggregate resource limit before its value is measured.
    if error != CollectionError.None: return CollectionResult[int](status: error)
    # Keys alone determine canonical order; rejecting equality enforces uniqueness.
    if i > 0 and not scalarLess(values[i-1].key, pair.key): return CollectionResult[int](
        status: CollectionError.NonCanonical)
    let valueSize = scalarSize(pair.value)
    # A bad late value cannot leave an earlier pair or discriminator in the destination.
    if valueSize.error != CollectionError.None: return CollectionResult[int](
        status: valueSize.error)
    error = grow(total, valueSize.value, limits)
    # Checked growth prevents wrapped capacity/alias calculations.
    if error != CollectionError.None: return CollectionResult[int](status: error)
  # Source errors precede output capacity; no addresses are needed for undersized outputs.
  if output.len < total: return CollectionResult[int](status: CollectionError.OutputTooSmall)
  # Protect all key/value source records against every byte of the written destination.
  if values.len > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(Entry[K, V]), addr output[
      0], total):
    return CollectionResult[int](status: CollectionError.AliasedBuffers)
  # Every potential failure has passed before emitting the one dictionary cardinality discriminator.
  for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  var cursor = int(prefix.len)
  # Preserve key/value association and caller-supplied value order exactly.
  for pair in values:
    put(pair.key, output, cursor)
    put(pair.value, output, cursor)
  CollectionResult[int](status: CollectionError.None, completed: cursor)

proc setCount*[T: CollectionScalar and CollectionFamily](owner: OwnedSet[T]): CollectionResult[
    CollectionCount] =
  ## Return copied set cardinality through the matching retained owner, without exposing mutable storage.
  let data = owner.data
  # Defaults cannot masquerade as a validated empty set.
  if data == nil: return CollectionResult[CollectionCount](status: CollectionError.InvalidOwner)
  CollectionResult[CollectionCount](status: CollectionError.None, completed: CollectionCount(uint64(
      data.values.len)))

proc setAt*[T: CollectionScalar and CollectionFamily](owner: OwnedSet[T],
    index: int): CollectionResult[T] =
  ## Copy one complete scalar value; supported types contain no mutable referenced payload to leak.
  let data = owner.data
  # Check ownership before accessing the private sequence, then reject signed index misuse.
  if data == nil: return CollectionResult[T](status: CollectionError.InvalidOwner)
  if index < 0 or index >= data.values.len: return CollectionResult[T](
      status: CollectionError.InvalidIndex)
  CollectionResult[T](status: CollectionError.None, completed: data.values[index])

# Re-emit a retained set with fixed cardinality under the caller's current policy and destination constraints.
proc encodeOwnedSet*[T: CollectionScalar and CollectionFamily](owner: OwnedSet[T],
    count: CollectionCount, limits: CollectionLimits,

output: var openArray[byte]): CollectionResult[int] =
  let data = owner.data
  # Missing ownership must not authorize an empty source or expose a default sequence.
  if data == nil: return CollectionResult[int](status: CollectionError.InvalidOwner)
  encodeSet(data.values, count, limits, output)

proc encodeOwnedVariableSet*[T: CollectionScalar and CollectionFamily](owner: OwnedSet[T],
    limits: CollectionLimits, output: var openArray[byte]): CollectionResult[int] =
  ## Reframe a retained set as an explicitly variable term without copying out or exporting its immutable elements.
  let data = owner.data
  # Default snapshots contain no validated elements, even when a caller requests an empty frame.
  if data == nil: return CollectionResult[int](status: CollectionError.InvalidOwner)
  encodeVariableSet(data.values, limits, output)

proc dictionaryCount*[K, V: CollectionScalar and CollectionFamily](owner: OwnedDictionary[K,
    V]): CollectionResult[CollectionCount] =
  ## Copy complete dictionary cardinality without exporting the key/value array or caller input coordinates.
  let data = owner.data
  # Defaults differ from successfully captured zero-pair dictionaries.
  if data == nil: return CollectionResult[CollectionCount](status: CollectionError.InvalidOwner)
  CollectionResult[CollectionCount](status: CollectionError.None, completed: CollectionCount(uint64(
      data.values.len)))

proc dictionaryAt*[K, V: CollectionScalar and CollectionFamily](owner: OwnedDictionary[K, V],
    index: int): CollectionResult[Entry[K, V]] =
  ## Copy one whole key/value pair through its matching owner; callers cannot mutate private snapshot fields.
  let data = owner.data
  # Ownership and signed bounds are ordinary typed failures rather than unchecked field/index accesses.
  if data == nil: return CollectionResult[Entry[K, V]](status: CollectionError.InvalidOwner)
  if index < 0 or index >= data.values.len: return CollectionResult[Entry[K, V]](
      status: CollectionError.InvalidIndex)
  CollectionResult[Entry[K, V]](status: CollectionError.None, completed: data.values[index])

proc encodeOwnedDictionary*[K, V: CollectionScalar and CollectionFamily](owner: OwnedDictionary[K,
    V], limits: CollectionLimits, output: var openArray[byte]): CollectionResult[int] =
  ## Re-emit immutable dictionary values with all current limits, complete capacity and aliases checked again.
  let data = owner.data
  # Default handles do not imply validated empty dictionaries.
  if data == nil: return CollectionResult[int](status: CollectionError.InvalidOwner)
  encodeDictionary(data.values, limits, output)
