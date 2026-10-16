## GP 0.8.0 T chapter 3, recent history and MMR encoding; state transitions/hashing remain external.
## See spec/state-history.md for exact field order, policies and synchronous ownership contracts.
import ./[natural, bounded, assurances, state_layout, state_trie]
from ./work_report import PackageHash, SegmentRoot
export PackageHash, SegmentRoot

type
  ## Recent block header identity is distinct from the two commitments stored beside it.
  HistoryHeaderHash* = distinct array[32, byte]
  ## Recent state root is copied independently from header and accumulation commitments.
  HistoryStateRoot* = distinct array[32, byte]
  ## Accumulation-log super-peak is a commitment, not an individual retained belt peak.
  HistorySuperPeak* = distinct array[32, byte]
  ## A present MMR peak is nominally distinct from the super-peak and other state roots.
  HistoryPeakHash* = distinct array[32, byte]
  ## Recent block timeslot uses E4, with no natural-number framing.
  HistorySlot* = distinct uint32
  ## One canonical dictionary pair binds a work-package identity to its segment root.
  ReportedPackage* = object
    package*: PackageHash
    segment*: SegmentRoot
  ## Borrowed source record; package keys must be strictly increasing by octet order.
  HistoryBlock* = object
    header*: HistoryHeaderHash
    superPeak*: HistorySuperPeak
    state*: HistoryStateRoot
    slot*: HistorySlot
    packages*: seq[ReportedPackage]
  ## Optional peaks retain presence: a present all-zero hash differs from an absent peak.
  HistoryPeak* = object
    case present*: bool
    of true:
      hash*: HistoryPeakHash # Only present peaks contain a fixed hash value.
    of false:
      discard                # Absent peaks contain no fabricated zero identity.
  ## Stable synchronous borrowed sources; history and peak order are semantically significant.
  HistoryState* = object
    blocks*: seq[HistoryBlock]
    peaks*: seq[HistoryPeak]
  ## Explicit chain cores plus independent block/package/peak/complete-byte caller ceilings.
  HistoryConfig* = object
    cores*: CoreCount
    blocks*, perBlock*, totalPackages*, peaks*: ElementLimit
    maxBytes*: ByteLimit
  ## Indices retain the distinction between history records, dictionary pairs and belt positions.
  HistoryBlockIndex* = distinct uint64
  ## Package ordinals are meaningful only together with their original history block owner.
  HistoryPackageIndex* = distinct uint64
  ## Belt positions are independent of history record positions, including absent entries.
  HistoryPeakIndex* = distinct uint64
  ## Failures and defaults never expose values, owners or partial parser progress.
  HistoryError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidCount, Truncated, NonCanonical,
    InvalidTag, LimitExceeded, LengthOverflow, InvalidOwner, InvalidIndex
  ## Only complete success permits application access to its selected payload.
  HistoryResult*[T] = object
    case error*: HistoryError
    of HistoryError.None:
      value*: T # Full values/counts are available only after success selection.
    else:
      discard   # Failed/default alternatives carry only their reason.
  ## Copied metadata exposes fixed fields and dictionary cardinality without mutable storage.
  HistoryBlockInfo* = object
    header*: HistoryHeaderHash
    superPeak*: HistorySuperPeak
    state*: HistoryStateRoot
    slot*: HistorySlot
    packages*: int
  ## Fixed copied parent cardinalities do not expose nested source arrays.
  HistoryInfo* = object
    blocks*, peaks*: int
  ## Private acyclic ARC storage owns every fixed record, dictionary pair and optional peak copy.
  HistoryData = ref object
    state: HistoryState
  ## Value handles share private immutable storage; default handles contain no validated history.
  HistorySnapshot* = object
    data: HistoryData
  ## Complete prefix decoding binds retained state to its exact consumed extent.
  HistoryRead* = object
    snapshot*: HistorySnapshot
    consumed*: int
  ## At most eight block layouts are needed; no input-derived scratch allocation is required for scanning.
  Layout = object
    blocks, peaks, peakStart, consumed: int
    starts, packages, counts: array[8, int]

## Check fixed-stride wire growth before native narrowing, multiplication and addition.
proc grow(cursor: var int, count: uint64, width: int, limit: ByteLimit): HistoryError =
  if count > uint64((high(int)-cursor) div width):
    return HistoryError.LengthOverflow # No arithmetic overflow before sizing or access.
  cursor += int(count)*width
  if uint64(cursor) > uint64(limit): return HistoryError.LimitExceeded # Counts, tags and fixed bytes all consume the parent budget.
  HistoryError.None

## Canonical natural-prefix reads return complete count/progress together or a failure-only reason.
proc count(input: openArray[byte], cursor: int): HistoryResult[tuple[value: uint64, size: int]] =
  let parsed = natural.decode(input.toOpenArray(cursor, input.len-1))
  if not parsed.ok:
    # Distinguish missing bytes from a complete but overlong count.
    if parsed.error == DecodeError.truncated:
      return HistoryResult[tuple[value: uint64, size: int]](
          error: HistoryError.Truncated) # No count available yet.
    else:
      return HistoryResult[tuple[value: uint64, size: int]](
          error: HistoryError.NonCanonical) # Reject alternate encodings.
  HistoryResult[tuple[value: uint64, size: int]](error: HistoryError.None,
    value: (uint64(parsed.value), int(parsed.consumed)))

## Copy fixed identities only after their whole selected record/set extent was validated.
proc fixed(input: openArray[byte], offset: int): array[32, byte] =
  # Fixed value results retain no pointer into the caller's input.
  for i in 0..<32: result[i] = input[offset+i]

## Compare dictionary keys by octet order, never by their associated segment value.
proc less(a, b: array[32, byte]): bool =
  # Equality is a duplicate key regardless of whether segment roots differ.
  for i in 0..<32:
    if a[i] < b[i]: return true # First smaller key octet establishes ascending order.
    elif a[i] > b[i]: return false # Descending keys have no canonical dictionary image.
  false

## Enforce at most eight recent blocks plus the caller's independently stricter cardinality ceiling.
proc blockCount(n: uint64, config: HistoryConfig): HistoryError =
  if uint64(config.cores) < 2: return HistoryError.InvalidConfig # JAM's core/validator configuration needs at least two cores.
  if n > 8: return HistoryError.InvalidCount # GP recent-history length is eight for both profiles.
  if n > uint64(config.blocks): return HistoryError.LimitExceeded # Caller may permit fewer retained records.
  HistoryError.None

## Enforce per-record core cardinality, aggregate dictionary policy and typed storage bounds.
proc packageCount(n: uint64, config: HistoryConfig, total: var uint64): HistoryError =
  if n > uint64(config.cores): return HistoryError.InvalidCount # One record cannot report more packages than cores.
  if n > uint64(config.perBlock) or n > uint64(config.totalPackages)-total:
    return HistoryError.LimitExceeded # Aggregate counting uses subtraction before addition.
  if n > uint64(high(int) div sizeof(ReportedPackage)): return HistoryError.LengthOverflow # Typed pair arrays must fit native storage.
  total += n
  HistoryError.None

## Prove complete history/dictionaries/belt without allocating any retained parent or child arrays.
proc scan(input: openArray[byte], config: HistoryConfig): HistoryResult[Layout] =
  if uint64(config.cores) < 2: return HistoryResult[Layout](
      error: HistoryError.InvalidConfig) # Configuration precedes framing.
  let n = count(input, 0)
  if n.error != HistoryError.None: return HistoryResult[Layout](error: n.error) # No partial history count.
  var error = blockCount(n.value.value, config)
  if error != HistoryError.None: return HistoryResult[Layout](
      error: error) # Bound the fixed stack layout before indexing it.
  var cursor = 0
  error = grow(cursor, uint64(n.value.size), 1, config.maxBytes)
  if error != HistoryError.None: return HistoryResult[Layout](
      error: error) # Initial count is part of the parent budget.
  var layout = Layout(blocks: int(n.value.value))
  var total = 0'u64
  # T serializes header/super-peak/state-root/E4-slot before each variable package dictionary.
  for i in 0..<layout.blocks:
    layout.starts[i] = cursor
    error = grow(cursor, 100, 1, config.maxBytes)
    if error != HistoryError.None: return HistoryResult[Layout](
        error: error) # Prove fixed fields before reading a child count.
    if input.len < cursor: return HistoryResult[Layout](
        error: HistoryError.Truncated) # Never pad missing fixed fields.
    let pairs = count(input, cursor)
    if pairs.error != HistoryError.None: return HistoryResult[Layout](
        error: pairs.error) # Canonical dictionary framing first.
    error = packageCount(pairs.value.value, config, total)
    if error != HistoryError.None: return HistoryResult[Layout](
        error: error) # Counts cannot trigger allocation yet.
    error = grow(cursor, uint64(pairs.value.size), 1, config.maxBytes)
    if error != HistoryError.None: return HistoryResult[Layout](error: error) # Account for child count bytes.
    layout.packages[i] = cursor
    layout.counts[i] = int(pairs.value.value)
    error = grow(cursor, pairs.value.value, 64, config.maxBytes)
    if error != HistoryError.None: return HistoryResult[Layout](
        error: error) # Prove the complete fixed-pair extent.
    if input.len < cursor: return HistoryResult[Layout](
        error: HistoryError.Truncated) # No partial dictionary accepted.
    # Ordering is local to each dictionary; repeated segment values are permitted at distinct keys.
    for j in 1..<layout.counts[i]:
      let offset = layout.packages[i]+j*64
      if not less(fixed(input, offset-64), fixed(input, offset)):
        return HistoryResult[Layout](error: HistoryError.NonCanonical) # Duplicate or descending package keys reject the parent.
  let peaks = count(input, cursor)
  if peaks.error != HistoryError.None: return HistoryResult[Layout](
      error: peaks.error) # Belt has its own canonical count.
  if peaks.value.value > uint64(config.peaks): return HistoryResult[Layout](
      error: HistoryError.LimitExceeded) # Bound peak work before traversal.
  if peaks.value.value > uint64(high(int) div sizeof(HistoryPeak)):
    return HistoryResult[Layout](error: HistoryError.LengthOverflow) # Optional peak storage must fit before narrowing.
  error = grow(cursor, uint64(peaks.value.size), 1, config.maxBytes)
  if error != HistoryError.None: return HistoryResult[Layout](
      error: error) # Belt framing is included in parent bytes.
  layout.peaks = int(peaks.value.value)
  layout.peakStart = cursor
  # Preserve absent entries and trailing holes; serialization does not normalize a supplied belt shape.
  for i in 0..<layout.peaks:
    error = grow(cursor, 1, 1, config.maxBytes)
    if error != HistoryError.None: return HistoryResult[Layout](
        error: error) # Optional discriminator needs one byte.
    if input.len < cursor: return HistoryResult[Layout](
        error: HistoryError.Truncated) # Check before reading the tag.
    let tag = input[cursor-1]
    if tag > 1: return HistoryResult[Layout](error: HistoryError.InvalidTag) # Only absent/present forms exist.
    if tag == 1:
      # A present zero hash is still a full 32-byte present value, unlike an absent peak.
      error = grow(cursor, 32, 1, config.maxBytes)
      if error != HistoryError.None: return HistoryResult[Layout](
          error: error) # Propagate this preflight failure before allocation or output.
      if input.len < cursor: return HistoryResult[Layout](error: HistoryError.Truncated) # No partial peak value.
  layout.consumed = cursor
  HistoryResult[Layout](error: HistoryError.None, value: layout)

## Decode into private immutable copies only after the whole nested source prefix is valid.
proc decodeHistoryState*(input: openArray[byte], config: HistoryConfig): HistoryResult[HistoryRead] =
  let checked = scan(input, config)
  if checked.error != HistoryError.None: return HistoryResult[HistoryRead](
      error: checked.error) # No partial owners/progress on late failure.
  let layout = checked.value
  let data = HistoryData(state: HistoryState(blocks: newSeq[HistoryBlock](layout.blocks),
      peaks: newSeq[HistoryPeak](layout.peaks)))
  # Copy fixed fields in T's explicit order, not the differently ordered conceptual state tuple.
  for i in 0..<layout.blocks:
    let offset = layout.starts[i]
    var slot = 0'u32
    for j in 0..<4: slot = slot or (uint32(input[offset+96+j]) shl (j*8)) # E4 is little-endian and unframed.
    data.state.blocks[i] = HistoryBlock(header: HistoryHeaderHash(fixed(input, offset)),
      superPeak: HistorySuperPeak(fixed(input, offset+32)), state: HistoryStateRoot(fixed(input,
          offset+64)),
      slot: HistorySlot(slot), packages: newSeq[ReportedPackage](layout.counts[i]))
    # Copy both dictionary fields together so package/segment association survives input destruction.
    for j in 0..<layout.counts[i]:
      let start = layout.packages[i]+j*64
      data.state.blocks[i].packages[j] = ReportedPackage(package: PackageHash(bytes: fixed(input,
          start)),
        segment: SegmentRoot(bytes: fixed(input, start+32)))
  var cursor = layout.peakStart
  # Tags/complete payload extents were proved by the stable-input scan; copy only the active alternative.
  for i in 0..<layout.peaks:
    let present = input[cursor] == 1
    inc cursor
    if present:
      data.state.peaks[i] = HistoryPeak(present: true, hash: HistoryPeakHash(fixed(input,
          cursor))) # Independent fixed peak copy.
      cursor += 32
    else:
      data.state.peaks[i] = HistoryPeak(present: false) # No fabricated hash for a hole.
  HistoryResult[HistoryRead](error: HistoryError.None,
    value: HistoryRead(snapshot: HistorySnapshot(data: data), consumed: layout.consumed))

## Copy fields only into a newly allocated payload whose whole extent has already been checked.
proc put(bytes: openArray[byte], output: var seq[byte], cursor: var int) =
  # Whole-source validation established every destination access.
  for b in bytes:
    output[cursor] = b
    inc cursor

## Commit one canonical natural count without copying unused primitive encoder storage.
proc putCount(n: int, output: var seq[byte], cursor: var int) =
  let prefix = natural.encode(JamNatural(n))
  put(prefix.bytes.toOpenArray(0, prefix.len-1), output, cursor)

## Serialize stable borrowed history/belt sources into an independent C(3) entry after complete preflight.
proc historyStateEntry*(source: HistoryState, config: HistoryConfig): HistoryResult[StateEntry] =
  var error = blockCount(uint64(source.blocks.len), config)
  if error != HistoryError.None: return HistoryResult[StateEntry](
      error: error) # No source traversal/allocation for invalid history count.
  var size = 0
  let prefix = natural.encode(JamNatural(source.blocks.len))
  error = grow(size, uint64(prefix.len), 1, config.maxBytes)
  if error != HistoryError.None: return HistoryResult[StateEntry](
      error: error) # Initial count consumes budget even for empty history.
  var total = 0'u64
  # Validate every dictionary before allocating output, including late duplicates/descending keys.
  for record in source.blocks:
    error = grow(size, 100, 1, config.maxBytes)
    if error != HistoryError.None: return HistoryResult[StateEntry](
        error: error) # Propagate this preflight failure before allocation or output.
    error = packageCount(uint64(record.packages.len), config, total)
    if error != HistoryError.None: return HistoryResult[StateEntry](
        error: error) # Propagate this preflight failure before allocation or output.
    let child = natural.encode(JamNatural(record.packages.len))
    error = grow(size, uint64(child.len), 1, config.maxBytes)
    if error != HistoryError.None: return HistoryResult[StateEntry](
        error: error) # Propagate this preflight failure before allocation or output.
    error = grow(size, uint64(record.packages.len), 64, config.maxBytes)
    if error != HistoryError.None: return HistoryResult[StateEntry](
        error: error) # Propagate this preflight failure before allocation or output.
    # Every adjacent key must remain strictly increasing; associated values do not determine order.
    for i in 1..<record.packages.len:
      if not less(record.packages[i-1].package.bytes, record.packages[i].package.bytes):
        return HistoryResult[StateEntry](error: HistoryError.NonCanonical) # No silent source sorting or duplicate replacement.
  if uint64(source.peaks.len) > uint64(config.peaks): return HistoryResult[StateEntry](
      error: HistoryError.LimitExceeded) # Independent peak-work ceiling.
  if source.peaks.len > high(int) div sizeof(HistoryPeak): return HistoryResult[StateEntry](
      error: HistoryError.LengthOverflow) # Bound typed source extents.
  let belt = natural.encode(JamNatural(source.peaks.len))
  error = grow(size, uint64(belt.len), 1, config.maxBytes)
  if error != HistoryError.None: return HistoryResult[StateEntry](
      error: error) # Propagate this preflight failure before allocation or output.
  # Optional peaks have exact one-byte or 33-byte encodings; absence retains no hash storage.
  for peak in source.peaks:
    let width = if peak.present: 33 else: 1 # Only the active alternative determines size.
    error = grow(size, 1, width, config.maxBytes)
    if error != HistoryError.None: return HistoryResult[StateEntry](
        error: error) # Propagate this preflight failure before allocation or output.
  var entry = StateEntry(key: chapterKey(StateChapter(3)), value: newSeq[byte](size))
  var cursor = 0
  putCount(source.blocks.len, entry.value, cursor)
  # Preserve chronological source order; T explicitly places super-peak before state root.
  for record in source.blocks:
    put(array[32, byte](record.header), entry.value, cursor)
    put(array[32, byte](record.superPeak), entry.value, cursor)
    put(array[32, byte](record.state), entry.value, cursor)
    for i in 0..<4:
      entry.value[cursor] = byte((uint32(record.slot) shr (i*8)) and 255) # E4, not a general natural.
      inc cursor
    putCount(record.packages.len, entry.value, cursor)
    for pair in record.packages:
      put(pair.package.bytes, entry.value, cursor) # Keep the associated value beside its canonical key.
      put(pair.segment.bytes, entry.value, cursor)
  putCount(source.peaks.len, entry.value, cursor)
  # No trimming of absent peaks, implicit padding or extra MMR/tree hashing occurs here.
  for peak in source.peaks:
    entry.value[cursor] = byte(ord(peak.present))
    inc cursor
    if peak.present: put(array[32, byte](peak.hash), entry.value, cursor) # Absence emits only its zero tag.
  HistoryResult[StateEntry](error: HistoryError.None, value: entry)

## Return copied parent cardinalities while retaining all nested storage privately.
proc historyInfo*(owner: HistorySnapshot): HistoryResult[HistoryInfo] =
  if owner.data.isNil: return HistoryResult[HistoryInfo](
      error: HistoryError.InvalidOwner) # Default handles are not validated empty history.
  HistoryResult[HistoryInfo](error: HistoryError.None, value: HistoryInfo(
      blocks: owner.data.state.blocks.len, peaks: owner.data.state.peaks.len))

## Return copied block metadata, bound to its original owner and nominal history position.
proc historyBlockAt*(owner: HistorySnapshot, index: HistoryBlockIndex): HistoryResult[
    HistoryBlockInfo] =
  if owner.data.isNil: return HistoryResult[HistoryBlockInfo](
      error: HistoryError.InvalidOwner) # No dereference of default storage.
  if uint64(index) >= uint64(owner.data.state.blocks.len): return HistoryResult[HistoryBlockInfo](
      error: HistoryError.InvalidIndex) # Check before narrowing.
  let record = owner.data.state.blocks[int(uint64(index))]
  HistoryResult[HistoryBlockInfo](error: HistoryError.None, value: HistoryBlockInfo(
    header: record.header,
    superPeak: record.superPeak, state: record.state, slot: record.slot,
    packages: record.packages.len))

## Extract one copied package/segment pair through the retained block and its own nominal pair position.
proc historyPackageAt*(owner: HistorySnapshot, blockIndex: HistoryBlockIndex,
    index: HistoryPackageIndex): HistoryResult[ReportedPackage] =
  let info = historyBlockAt(owner, blockIndex)
  if info.error != HistoryError.None: return HistoryResult[ReportedPackage](
      error: info.error) # Invalid parent cannot expose a child.
  if uint64(index) >= uint64(info.value.packages): return HistoryResult[ReportedPackage](
      error: HistoryError.InvalidIndex) # Check the selected dictionary's count.
  HistoryResult[ReportedPackage](error: HistoryError.None,
    value: owner.data.state.blocks[int(uint64(blockIndex))].packages[int(uint64(index))])

## Extract a fixed tagged peak copy; absent peaks expose no hash alternative.
proc historyPeakAt*(owner: HistorySnapshot, index: HistoryPeakIndex): HistoryResult[HistoryPeak] =
  if owner.data.isNil: return HistoryResult[HistoryPeak](
      error: HistoryError.InvalidOwner) # No fabricated peak on a missing owner.
  if uint64(index) >= uint64(owner.data.state.peaks.len): return HistoryResult[HistoryPeak](
      error: HistoryError.InvalidIndex) # Check before indexing.
  HistoryResult[HistoryPeak](error: HistoryError.None, value: owner.data.state.peaks[int(uint64(index))])
