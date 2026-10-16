## GP 0.8.0 T(state) chapter 5: four independently sorted variable sets.
## Structural framing does not prove verdict validity, key eligibility or dispute transitions.
import ./[natural, bounded, state_layout, state_trie]
from ./disputes import DisputeHash, OffenderKey
export DisputeHash, OffenderKey

type
  ## The three report judgment domains share a report identity type but retain separate set membership.
  JudgmentSet* {.pure.} = enum
    Good, Bad, Wonky
  ## A set ordinal is distinct from validator, service and byte indices.
  DisputeStateIndex* = distinct uint64
  ## Stable borrowed sources; each set must already be strictly increasing by octet order.
  DisputeState* = object
    reports*: array[JudgmentSet, seq[DisputeHash]]
    offenders*: seq[OffenderKey]
  ## Independent per-set, aggregate item and complete encoded-byte resource ceilings.
  DisputeStateConfig* = object
    perSet*, totalItems*: ElementLimit
    maxBytes*: ByteLimit
  ## Default and failed alternatives expose neither values nor partial progress.
  DisputeStateError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, LengthOverflow, InvalidOwner, InvalidIndex
  ## A complete selected success alone carries an entry, snapshot, copied field or count.
  DisputeStateResult*[T] = object
    case error*: DisputeStateError
    of DisputeStateError.None:
      value*: T # Failure alternatives cannot expose fabricated data.
    else:
      discard   # Default and failures contain only their reason.
  ## Private acyclic ARC storage retains fixed copied values in their canonical set order.
  DisputeStateData = ref object
    state: DisputeState
  ## Value handles share immutable private data; replacing a handle leaves other copies unchanged.
  DisputeStateSnapshot* = object
    data: DisputeStateData
  ## Prefix success binds one complete retained component to its exact consumed extent.
  DisputeStateRead* = object
    snapshot*: DisputeStateSnapshot
    consumed*: int
  ## Fixed copied counts preserve report-class and offender separation without exporting sequences.
  DisputeStateInfo* = object
    reports*: array[JudgmentSet, int]
    offenders*: int
  ## Private synchronous layout proof contains no retained pointer or externally reusable span.
  Layout = object
    starts, counts: array[4, int]
    consumed: int

## Strict lexicographic octet order agrees with GP sequence ordering and canonical fixed-octet sets.
proc less(a, b: array[32, byte]): bool =
  # The first differing octet determines order; complete equality is a duplicate.
  for i in 0..<32:
    if a[i] < b[i]: return true # Earlier octets belong before the next identity.
    elif a[i] > b[i]: return false # Descending values cannot enter the canonical set.
  false

## Check a complete row's count and resource extent before narrowing or allocating typed storage.
proc charge(count: uint64, prefix: int, config: DisputeStateConfig,
            total: var uint64, cursor: var int): DisputeStateError =
  if count > uint64(config.perSet) or count > uint64(config.totalItems)-total:
    return DisputeStateError.LimitExceeded # Each repeated count is charged without aggregate overflow.
  if prefix > high(int)-cursor:
    return DisputeStateError.LengthOverflow # Count framing itself must fit before subtracting it.
  if count > uint64((high(int)-cursor-prefix) div 32) or count > uint64(high(int) div sizeof(DisputeHash)):
    return DisputeStateError.LengthOverflow # Wire and fixed typed storage must both fit native addressing.
  cursor += prefix+int(count)*32
  total += count
  if uint64(cursor) > uint64(config.maxBytes):
    return DisputeStateError.LimitExceeded # Count prefixes consume the same parent byte budget as identities.
  DisputeStateError.None

## Copy an already validated fixed source identity, retaining no borrowed storage.
proc fixed(input: openArray[byte], offset: int): array[32, byte] =
  # The caller proved the whole selected set's payload before any field access.
  for i in 0..<32: result[i] = input[offset+i]

## Validate every canonical count, complete set and strict order before constructing any parent owner.
proc scan(input: openArray[byte], config: DisputeStateConfig): DisputeStateResult[Layout] =
  var layout: Layout
  var cursor = 0
  var total = 0'u64
  # Exactly four independently framed sets occur in good/bad/wonky/offender order.
  for section in 0..<4:
    let parsed = natural.decode(input.toOpenArray(cursor, input.len-1))
    if not parsed.ok:
      # Preserve missing count bytes versus a complete but overlong representation.
      if parsed.error == DecodeError.truncated:
        return DisputeStateResult[Layout](error: DisputeStateError.Truncated) # No partial earlier owner escapes.
      else:
        return DisputeStateResult[Layout](error: DisputeStateError.NonCanonical) # Reject second count encodings.
    let start = cursor
    let error = charge(uint64(parsed.value), parsed.consumed, config, total, cursor)
    if error != DisputeStateError.None: return DisputeStateResult[Layout](
        error: error) # Announced work is bounded before access.
    if input.len < cursor: return DisputeStateResult[Layout](
        error: DisputeStateError.Truncated) # Complete payload precedes order reads.
    layout.starts[section] = start+int(parsed.consumed)
    layout.counts[section] = int(uint64(parsed.value))
    # Equal or descending identities are rejected even when a later set would otherwise be valid.
    for i in 1..<layout.counts[section]:
      let offset = layout.starts[section]+i*32
      if not less(fixed(input, offset-32), fixed(input, offset)):
        return DisputeStateResult[Layout](error: DisputeStateError.NonCanonical) # Canonical set membership has one wire ordering.
  layout.consumed = cursor
  DisputeStateResult[Layout](error: DisputeStateError.None, value: layout)

## Encode a complete stable source into an independent C(5) entry, rejecting noncanonical input without sorting.
proc disputeStateEntry*(source: DisputeState, config: DisputeStateConfig): DisputeStateResult[StateEntry] =
  var size = 0
  var total = 0'u64
  # Whole-source validation precedes allocation and includes even the last offender identity.
  for section in 0..<4:
    let count = if section < 3: source.reports[JudgmentSet(
        section)].len else: source.offenders.len # Select the correct nominal domain.
    let prefix = natural.encode(JamNatural(count))
    let error = charge(uint64(count), prefix.len, config, total, size)
    if error != DisputeStateError.None: return DisputeStateResult[StateEntry](
        error: error) # No earlier payload is emitted on failure.
    # Canonicality is local to each set; cross-set transition consistency remains external.
    for i in 1..<count:
      var a, b: array[32, byte]
      if section < 3:
        a = array[32, byte](source.reports[JudgmentSet(section)][
            i-1]) # Report identity comparison preserves class membership.
        b = array[32, byte](source.reports[JudgmentSet(section)][i])
      else:
        a = array[32, byte](source.offenders[i-1]) # Keys are compared only within the offender set.
        b = array[32, byte](source.offenders[i])
      if not less(a, b): return DisputeStateResult[StateEntry](
          error: DisputeStateError.NonCanonical) # No silent sorting/deduplication.
  var entry = StateEntry(key: chapterKey(StateChapter(5)), value: newSeq[byte](size))
  var cursor = 0
  # Commit the exact sorted sequences and four canonical counts only after full stable-source preflight.
  for section in 0..<4:
    let count = if section < 3: source.reports[JudgmentSet(
        section)].len else: source.offenders.len # No outer tuple count.
    let prefix = natural.encode(JamNatural(count))
    for i in 0..<prefix.len:
      entry.value[cursor] = prefix.bytes[i] # Count prefix is never omitted for an empty set.
      inc cursor
    # Fixed identities have no individual length prefixes or role discriminators.
    for i in 0..<count:
      let value = if section < 3: array[32, byte](source.reports[JudgmentSet(section)][
          i]) else: array[32, byte](source.offenders[i])               # Copy selected source domain.
      for b in value:
        entry.value[cursor] = b # Output storage is independent of every caller source array.
        inc cursor
  DisputeStateResult[StateEntry](error: DisputeStateError.None, value: entry)

## Decode the complete canonical component into immutable private copies after a no-allocation scan.
proc decodeDisputeState*(input: openArray[byte], config: DisputeStateConfig): DisputeStateResult[
    DisputeStateRead] =
  let checked = scan(input, config)
  if checked.error != DisputeStateError.None:
    return DisputeStateResult[DisputeStateRead](error: checked.error) # No child data or consumed cursor after failure.
  let layout = checked.value
  let data = DisputeStateData()
  # Report arrays remain nominally separate from offender keys throughout capture and extraction.
  for kind in JudgmentSet:
    data.state.reports[kind] = newSeq[DisputeHash](layout.counts[ord(kind)])
    for i in 0..<data.state.reports[kind].len:
      data.state.reports[kind][i] = DisputeHash(fixed(input, layout.starts[ord(
          kind)]+i*32)) # All fields were proved complete.
  data.state.offenders = newSeq[OffenderKey](layout.counts[3])
  # The entire offender set is copied, including leading zero octets and opaque invalid-point encodings.
  for i in 0..<data.state.offenders.len: data.state.offenders[i] = OffenderKey(fixed(input,
      layout.starts[3]+i*32))
  DisputeStateResult[DisputeStateRead](error: DisputeStateError.None,
    value: DisputeStateRead(snapshot: DisputeStateSnapshot(data: data), consumed: layout.consumed))

## Return independent fixed counts without exporting mutable set arrays.
proc disputeStateInfo*(owner: DisputeStateSnapshot): DisputeStateResult[DisputeStateInfo] =
  if owner.data.isNil: return DisputeStateResult[DisputeStateInfo](
      error: DisputeStateError.InvalidOwner) # Default handles are not validated empty state.
  var info = DisputeStateInfo(offenders: owner.data.state.offenders.len)
  # Each report class retains its own canonical set membership/count.
  for kind in JudgmentSet: info.reports[kind] = owner.data.state.reports[kind].len
  DisputeStateResult[DisputeStateInfo](error: DisputeStateError.None, value: info)

## Extract a copied report identity through its retained owner, judgment class and nominal ordinal.
proc judgedReportAt*(owner: DisputeStateSnapshot, kind: JudgmentSet,
    index: DisputeStateIndex): DisputeStateResult[DisputeHash] =
  if owner.data.isNil: return DisputeStateResult[DisputeHash](
      error: DisputeStateError.InvalidOwner) # No storage on default snapshots.
  if uint64(index) >= uint64(owner.data.state.reports[kind].len):
    return DisputeStateResult[DisputeHash](error: DisputeStateError.InvalidIndex) # Bound before native narrowing/access.
  DisputeStateResult[DisputeHash](error: DisputeStateError.None, value: owner.data.state.reports[
      kind][int(uint64(index))])

## Extract an independent offender key without permitting report-hash/key substitution.
proc stateOffenderAt*(owner: DisputeStateSnapshot, index: DisputeStateIndex): DisputeStateResult[OffenderKey] =
  if owner.data.isNil: return DisputeStateResult[OffenderKey](
      error: DisputeStateError.InvalidOwner) # No fabricated default key on failure.
  if uint64(index) >= uint64(owner.data.state.offenders.len):
    return DisputeStateResult[OffenderKey](error: DisputeStateError.InvalidIndex) # Check the key set's own cardinality.
  DisputeStateResult[OffenderKey](error: DisputeStateError.None, value: owner.data.state.offenders[
      int(uint64(index))])
