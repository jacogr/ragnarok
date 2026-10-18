# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 C.2 disputes: canonical verdicts/judgments and culprit/fault evidence. Framing and
## structural ceilings do not establish contextual quorum or signature validity.
##
## Exposes dispute records and immutable snapshots, encoding/decoding, inspection and bounded
## verdict/judgment/evidence access.

import std/assertions
import ./[natural, bounded, assurances]

type
  # A disputed report identity is distinct from an offender key, despite the same wire width.
  DisputeHash* = distinct array[32, byte]
  # Verdict epochs are E4 values, separate from report slots and other timeslots.
  DisputeEpoch* = distinct uint32
  # Judgment E2 indices belong to the selected validator population.
  JudgeIndex* = distinct uint16
  # Exact Ed25519 offender identity bytes determine evidence order.
  OffenderKey* = distinct array[32, byte]
  # Opaque Ed25519 evidence bytes carry no signature-verification claim.
  DisputeSignature* = distinct array[64, byte]
  # A judgment owns all its fields; validity is a canonical Boolean, never an arbitrary tag byte.
  Judgment* = object
    valid*: bool
    judge*: JudgeIndex
    signature*: DisputeSignature
  # Encoder-only borrowed source; its sequence must remain stable during the synchronous call.
  Verdict* = object
    target*: DisputeHash
    epoch*: DisputeEpoch
    judgments*: seq[Judgment]
  # Culprit evidence owns exact report, Ed25519 key and signature bytes.
  Culprit* = object
    target*: DisputeHash
    key*: OffenderKey
    signature*: DisputeSignature
  # Fault evidence additionally records the signed judgment's validity bit.
  Fault* = object
    target*: DisputeHash
    valid*: bool
    key*: OffenderKey
    signature*: DisputeSignature
  # Stable borrowed encoding sources; no mutable sequence is exported by a decoded owner.
  Disputes* = object
    verdicts*: seq[Verdict]
    culprits*: seq[Culprit]
    faults*: seq[Fault]
  # The caller supplies a structural ceiling covering both eligible validator sets and a prefix byte budget.
  DisputeConfig* = object
    validators*: ValidatorCount
    maxBytes*: ByteLimit
  # Failure alternatives never contain records, owner handles or parser progress.
  DisputeError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, Truncated, NonCanonical, LimitExceeded,
    InvalidTag, InvalidValidator, OutputTooSmall, AliasedBuffers,
    InvalidOwner, InvalidIndex
  # Only an explicitly successful tagged result carries an application value.
  DisputeResult*[T] = object
    case status: DisputeError
    of None:
      # A successful selection alone authorizes application access.
      completed: T
    else:
      # Default and rejected inputs expose only their failure reason.
      discard
  # Public metadata copies fixed fields and lengths without detaching coordinates from an owner.
  VerdictInfo* = object
    target*: DisputeHash
    epoch*: DisputeEpoch
    judgments*: int
  # Public cardinalities describe a complete validated prefix.
  DisputeInfo* = object
    verdicts*, culprits*, faults*, consumed*: int
  # Private bounded offsets exist only alongside the exact retained bytes they describe.
  Layout = object
    info: DisputeInfo
    verdictOffsets, voteOffsets, voteCounts: array[16, int]
    culpritOffset, faultOffset: int
  # Acyclic ARC storage is private and immutable after complete capture.
  DisputeData = ref object
    wire: seq[byte]
    layout: Layout
  # Copying this opaque handle retains the same immutable snapshot without exposing bytes or offsets.
  OwnedDisputes* = object
    data: nil DisputeData
  # Decode success binds exact prefix progress to its owning snapshot.
  DisputesRead* = object
    owner*: OwnedDisputes
    info*: DisputeInfo

# Observe a generic operation's outcome without permitting safe-code retagging.
func error*[T](value: DisputeResult[T]): DisputeError = value.status
# Only complete validated operations expose application values, owners or progress.
func value*[T](value: DisputeResult[T]): T {.inline, requires: value.status == DisputeError.None.} =
  value.completed
# Sibling adapters can construct a failure reason, never success without a completed operation.
func disputeFailure*[T](reason: DisputeError): DisputeResult[T] {.requires: reason !=
    DisputeError.None.} =
  DisputeResult[T](status: reason)

# Both eligible populations must fit this GP 0.8.0 domain; selecting the actual epoch set is external.
proc validConfig(config: DisputeConfig): bool {.raises: [].} =
  uint64(config.validators) in 6'u64..1023'u64 and uint64(config.validators) mod 3 == 0

# Read exact little-endian E2/E4 fields only after their enclosing extent is proved.
proc integer(input: openArray[byte], start, width: int): uint32 {.raises: [].} =
  result = 0
  # Each shift stays within the explicitly bounded four-byte scalar.
  for i in 0..<width: result = result or (uint32(input[start+i]) shl (8*i))

# Copy a fixed-width identity or signature without retaining a caller pointer.
proc fixed[N: static[int]](input: openArray[byte], start: int): array[N, byte] {.raises: [].} =
  result = default(array[N, byte])
  # Callers prove the complete fixed extent before invoking this private helper.
  for i in 0..<N: result[i] = input[start+i]

# Lexicographic byte order is the GP ordering for hashes and Ed25519 encodings.
proc increasing(a, b: array[32, byte]): bool {.raises: [].} =
  # The first unequal octet determines order; equal identities are duplicates.
  for i in 0..<32:
    # Equal prefixes need another octet; the first difference decides the unique ordering.
    if a[i] != b[i]: return a[i] < b[i]
  false

# Scan without allocation; no partially checked metadata can escape through a failed result.
proc scan(input: openArray[byte], config: DisputeConfig): DisputeResult[Layout] {.raises: [].} =
  # Reject invalid caller domains before inspecting attacker bytes.
  if not validConfig(config): return DisputeResult[Layout](status: DisputeError.InvalidConfig)
  var layout: Layout = default(Layout)
  var cursor = 0
  # Canonical counts are bounded before host conversion; even empty sections consume budget.
  template number(target: untyped, ceiling: uint64) =
    block:
      let parsed = natural.decode(input.toOpenArray(cursor, input.high))
      # Incomplete and overlong naturals remain distinct typed failures.
      if not parsed.ok:
        return DisputeResult[Layout](status: if parsed.error == natural.truncated:
          DisputeError.Truncated
        else: DisputeError.NonCanonical) # Overlong encodings cannot select a second representation.
      cursor += int(parsed.consumed)
      # Prefix bytes themselves consume the caller's frame budget.
      if uint64(cursor) > uint64(config.maxBytes):
        return DisputeResult[Layout](status: DisputeError.LimitExceeded)
      # Reject excessive counts before narrowing them to a host integer.
      if uint64(parsed.value) > ceiling:
        return DisputeResult[Layout](status: DisputeError.LimitExceeded)
      target = int(uint64(parsed.value))
  # Check remaining input by division before multiplying any externally selected count.
  template extent(count, stride: int) =
    block:
      # Division proves a complete input extent without overflowing count times stride.
      if count > (input.len-cursor) div stride:
        return DisputeResult[Layout](status: DisputeError.Truncated)
      # The extent now fits input, so its safe endpoint must also fit the retained-byte policy.
      if uint64(cursor+count*stride) > uint64(config.maxBytes):
        return DisputeResult[Layout](status: DisputeError.LimitExceeded)
  number(layout.info.verdicts, 16'u64)
  var previousHash: array[32, byte] = default(array[32, byte])
  # At most sixteen verdicts bound all private metadata before any allocation.
  for i in 0..<layout.info.verdicts:
    extent(1, 36)
    layout.verdictOffsets[i] = cursor
    let target = fixed[32](input, cursor)
    # Verdict report hashes must be strictly increasing, independently of state-history checks.
    if i > 0 and not increasing(previousHash, target):
      return DisputeResult[Layout](status: DisputeError.NonCanonical)
    previousHash = target
    cursor += 36
    number(layout.voteCounts[i], uint64(config.validators))
    extent(layout.voteCounts[i], 67)
    layout.voteOffsets[i] = cursor
    var previousJudge = -1
    # Check every Boolean and E2 judge before publishing any owner, including late judgments.
    for j in 0..<layout.voteCounts[i]:
      # Only 0/1 are Boolean encodings; signatures cannot hide unsupported tag values.
      if input[cursor] > 1: return DisputeResult[Layout](status: DisputeError.InvalidTag)
      let judge = int(integer(input, cursor+1, 2))
      # A representable E2 index still needs membership in the caller's structural ceiling.
      if judge >= int(uint64(config.validators)):
        return DisputeResult[Layout](status: DisputeError.InvalidValidator)
      # Strict order also excludes repeated validator identities.
      if judge <= previousJudge: return DisputeResult[Layout](status: DisputeError.NonCanonical)
      previousJudge = judge
      cursor += 67
  number(layout.info.culprits, 16'u64)
  extent(layout.info.culprits, 128)
  layout.culpritOffset = cursor
  var previousKey: array[32, byte] = default(array[32, byte])
  # Culprit evidence orders by offender key rather than target report hash.
  for i in 0..<layout.info.culprits:
    let key = fixed[32](input, cursor+32)
    # Evidence order uses keys, independently of each report target.
    if i > 0 and not increasing(previousKey, key):
      return DisputeResult[Layout](status: DisputeError.NonCanonical)
    previousKey = key
    cursor += 128
  number(layout.info.faults, 16'u64)
  extent(layout.info.faults, 129)
  layout.faultOffset = cursor
  # Faults have their own independent key ordering and canonical Boolean tag.
  for i in 0..<layout.info.faults:
    # A fault's validity tag precedes its offender identity and must be canonical.
    if input[cursor+32] > 1: return DisputeResult[Layout](status: DisputeError.InvalidTag)
    let key = fixed[32](input, cursor+33)
    # Restart ordering for this section rather than comparing against the final culprit.
    if i > 0 and not increasing(previousKey, key):
      return DisputeResult[Layout](status: DisputeError.NonCanonical)
    previousKey = key
    cursor += 129
  layout.info.consumed = cursor
  DisputeResult[Layout](status: DisputeError.None, completed: layout)

# Snapshot only the completely validated prefix; callers keep borrowed input stable during this call.
proc decodeDisputes*(input: openArray[byte], config: DisputeConfig): DisputeResult[
    DisputesRead] {.raises: [].} =
  let parsed = scan(input, config)
  # No input-derived allocation occurs on a malformed frame or invalid caller configuration.
  if parsed.error != DisputeError.None: return DisputeResult[DisputesRead](status: parsed.error)
  let data = DisputeData(layout: parsed.value, wire: newSeq[byte](parsed.value.info.consumed))
  # A private copy makes caller mutation and source lifetime irrelevant after return.
  for i in 0..<data.wire.len: data.wire[i] = input[i]
  DisputeResult[DisputesRead](status: DisputeError.None,
    completed: DisputesRead(owner: OwnedDisputes(data: data), info: parsed.value.info))

# Preflight all source fields and byte arithmetic before any destination write or capacity check.
proc measure(value: Disputes, config: DisputeConfig): DisputeResult[int] {.raises: [].} =
  # Uninitialized profiles and excessive section counts cannot authorize source traversal.
  if not validConfig(config): return DisputeResult[int](status: DisputeError.InvalidConfig)
  # Each GP section has its own sixteen-record bound.
  if value.verdicts.len > 16 or value.culprits.len > 16 or value.faults.len > 16:
    return DisputeResult[int](status: DisputeError.LimitExceeded)
  # All three bounded outer counts have canonical one-octet encodings.
  var required = 3
  # Validate full verdict/judgment sources, including the last record, before committing earlier ones.
  for i, verdict in value.verdicts:
    # Require canonical report order even for sources built directly by the application.
    if i > 0 and not increasing(array[32, byte](value.verdicts[i-1].target),
        array[32, byte](verdict.target)):
      return DisputeResult[int](status: DisputeError.NonCanonical)
    # Bound multiplication and source traversal before reading judgments.
    if uint64(verdict.judgments.len) > uint64(config.validators):
      return DisputeResult[int](status: DisputeError.LimitExceeded)
    var previous = -1
    # Bool fields need no runtime tag narrowing; nominal E2 judges still need domain/order checks.
    for vote in verdict.judgments:
      let judge = int(uint16(vote.judge))
      # A representable E2 index still needs membership in the caller's structural ceiling.
      if judge >= int(uint64(config.validators)):
        return DisputeResult[int](status: DisputeError.InvalidValidator)
      # Strict order also excludes repeated validator identities.
      if judge <= previous: return DisputeResult[int](status: DisputeError.NonCanonical)
      previous = judge
    required += 36+int(natural.encode(JamNatural(verdict.judgments.len)).len)+67*verdict.judgments.len
  # Culprit and fault uniqueness are independent; the same key may occur once in each section.
  for i in 1..<value.culprits.len:
    # Reject duplicate or descending culprit identities before computing output capacity.
    if not increasing(array[32, byte](value.culprits[i-1].key), array[32, byte](value.culprits[i].key)):
      return DisputeResult[int](status: DisputeError.NonCanonical)
  # Fault ordering starts independently from the first fault, including an empty section.
  for i in 1..<value.faults.len:
    # A late duplicate offender cannot authorize earlier output writes.
    if not increasing(array[32, byte](value.faults[i-1].key), array[32, byte](value.faults[i].key)):
      return DisputeResult[int](status: DisputeError.NonCanonical)
  required += 128*value.culprits.len+129*value.faults.len
  # Counts are at most 16/1023, so the proven maximum extent fits even a 32-bit host int.
  if uint64(required) > uint64(config.maxBytes):
    return DisputeResult[int](status: DisputeError.LimitExceeded)
  DisputeResult[int](status: DisputeError.None, completed: required)

# Compare address distances instead of potentially overflowing end addresses.
proc overlaps(a: pointer, an: int, b: pointer, bn: int): bool {.raises: [].} =
  # Empty sources have neither an address to read nor bytes to overlap.
  if an == 0 or bn == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  if left <= right: right-left < uint(an) # Lower source address selects its own extent.
  else: left-right < uint(bn) # Lower destination address selects the written prefix extent.

# Encode stable borrowed sources atomically after checking outer records and all nested judgment storage.
proc encodeDisputes*(value: Disputes, config: DisputeConfig,
    output: var openArray[byte]): DisputeResult[int] {.raises: [].} =
  let measured = measure(value, config)
  # Source policy errors take precedence over capacity and cannot alter caller sentinels.
  if measured.error != DisputeError.None: return measured
  let required = measured.value
  # Complete capacity is required before addresses or destination elements can be inspected.
  if output.len < required: return DisputeResult[int](status: DisputeError.OutputTooSmall)
  # The outer descriptor object must survive commit just like its nested record storage.
  if overlaps(unsafeAddr value, sizeof(Disputes), addr output[0], required):
    return DisputeResult[int](status: DisputeError.AliasedBuffers)
  # Check entire written destination against every borrowed source, including sequence descriptors.
  template rejectAlias(items: untyped) =
    block:
      # Empty sequences borrow no elements; nonempty source extents are bounded by preflight.
      if items.len > 0 and overlaps(unsafeAddr items[0], items.len*sizeof(items[0]),
          addr output[0], required):
        return DisputeResult[int](status: DisputeError.AliasedBuffers)
  rejectAlias(value.verdicts)
  rejectAlias(value.culprits)
  rejectAlias(value.faults)
  # A late judgment source may overlap an earlier record's destination; local-slice checks are insufficient.
  for verdict in value.verdicts: rejectAlias(verdict.judgments)
  var cursor = 0
  # Private commit helpers operate only on preflight-proved exact fields and destination extents.
  template put(bytes: untyped) =
    block:
      # Commit exact owned scalar/identity bytes only within the preflight-proved destination.
      for octet in bytes:
        output[cursor] = octet # Every emitted octet belongs to the selected canonical prefix.
        inc cursor
  # Counts use canonical compact naturals rather than the scalar widths of indices/epochs.
  template number(count: int) =
    block:
      let prefix = natural.encode(JamNatural(count))
      # Emit only the active canonical natural prefix, never its unused fixed storage.
      for i in 0..<prefix.len:
        output[cursor] = prefix.bytes[i] # Vote counts above 127 retain general-natural encoding.
        inc cursor
  number(value.verdicts.len)
  # Fixed E4 epochs and E2 indices never use compact-natural encoding.
  for verdict in value.verdicts:
    put(array[32, byte](verdict.target))
    # Epochs always retain four little-endian octets, including zero/high-valued epochs.
    for i in 0..<4:
      output[cursor] = byte((uint32(verdict.epoch) shr (8*i)) and 255) # Commit one E4 octet.
      inc cursor
    number(verdict.judgments.len)
    # Emit each complete prevalidated Boolean/index/signature judgment.
    for vote in verdict.judgments:
      output[cursor] = byte(vote.valid); inc cursor # Canonical Boolean 0/1 only.
      # E2 remains two octets even for small validator identities.
      for i in 0..<2:
        output[cursor] = byte((uint16(vote.judge) shr (8*i)) and 255) # Commit one E2 octet.
        inc cursor
      put(array[64, byte](vote.signature))
  number(value.culprits.len)
  # Culprits omit the validity field that occurs in fault evidence.
  for culprit in value.culprits:
    put(array[32, byte](culprit.target))
    put(array[32, byte](culprit.key))
    put(array[64, byte](culprit.signature))
  number(value.faults.len)
  # Fault validity precedes the offender key on the wire.
  for fault in value.faults:
    put(array[32, byte](fault.target))
    output[cursor] = byte(fault.valid); inc cursor
    put(array[32, byte](fault.key))
    put(array[64, byte](fault.signature))
  assert cursor == required
  measured

# Return copied cardinalities; a default handle never fabricates an empty validated extrinsic.
proc disputesInfo*(owner: OwnedDisputes): DisputeResult[DisputeInfo] {.raises: [].} =
  # A default handle carries no validated snapshot, even when an empty result would be plausible.
  let data = owner.data
  if data == nil: return DisputeResult[DisputeInfo](status: DisputeError.InvalidOwner)
  DisputeResult[DisputeInfo](status: DisputeError.None, completed: data.layout.info)

# Copy fixed verdict metadata; judgments are selected only through the matching retained owner.
proc verdictAt*(owner: OwnedDisputes, index: int): DisputeResult[VerdictInfo] {.raises: [].} =
  # A default handle carries no validated snapshot, even when an empty result would be plausible.
  let data = owner.data
  if data == nil: return DisputeResult[VerdictInfo](status: DisputeError.InvalidOwner)
  # Signed invalid indices must fail before reading owner-bound coordinates.
  if index < 0 or index >= data.layout.info.verdicts:
    return DisputeResult[VerdictInfo](status: DisputeError.InvalidIndex)
  let start = data.layout.verdictOffsets[index]
  DisputeResult[VerdictInfo](status: DisputeError.None, completed: VerdictInfo(
    target: DisputeHash(fixed[32](data.wire, start)),
    epoch: DisputeEpoch(integer(data.wire, start+32, 4)),
    judgments: data.layout.voteCounts[index]))

# Copy one complete judgment; neither detached offsets nor mutable vote sequences leave the owner.
proc judgmentAt*(owner: OwnedDisputes, verdict, index: int): DisputeResult[Judgment] {.raises: [].} =
  # Retain and prove the backing reference independently of the nested verdict query.
  let data = owner.data
  if data == nil: return DisputeResult[Judgment](status: DisputeError.InvalidOwner)
  let selected = verdictAt(owner, verdict)
  # Invalid owner/verdict selections cannot authorize reading a judgment offset.
  if selected.error != DisputeError.None: return DisputeResult[Judgment](status: selected.error)
  # Signed invalid indices must fail before reading owner-bound coordinates.
  if index < 0 or index >= selected.value.judgments:
    return DisputeResult[Judgment](status: DisputeError.InvalidIndex)
  let start = data.layout.voteOffsets[verdict]+67*index
  DisputeResult[Judgment](status: DisputeError.None, completed: Judgment(
    valid: data.wire[start] == 1, judge: JudgeIndex(integer(data.wire, start+1, 2)),
    signature: DisputeSignature(fixed[64](data.wire, start+3))))

# Copy complete culprit evidence from a validated owner-bound record.
proc culpritAt*(owner: OwnedDisputes, index: int): DisputeResult[Culprit] {.raises: [].} =
  # A default handle carries no validated snapshot, even when an empty result would be plausible.
  let data = owner.data
  if data == nil: return DisputeResult[Culprit](status: DisputeError.InvalidOwner)
  # Signed invalid indices must fail before reading owner-bound coordinates.
  if index < 0 or index >= data.layout.info.culprits:
    return DisputeResult[Culprit](status: DisputeError.InvalidIndex)
  let start = data.layout.culpritOffset+128*index
  DisputeResult[Culprit](status: DisputeError.None, completed: Culprit(
    target: DisputeHash(fixed[32](data.wire, start)),
    key: OffenderKey(fixed[32](data.wire, start+32)),
    signature: DisputeSignature(fixed[64](data.wire, start+64))))

# Copy complete fault evidence, preserving the validity bit's meaning separately from its signature.
proc faultAt*(owner: OwnedDisputes, index: int): DisputeResult[Fault] {.raises: [].} =
  # A default handle carries no validated snapshot, even when an empty result would be plausible.
  let data = owner.data
  if data == nil: return DisputeResult[Fault](status: DisputeError.InvalidOwner)
  # Signed invalid indices must fail before reading owner-bound coordinates.
  if index < 0 or index >= data.layout.info.faults:
    return DisputeResult[Fault](status: DisputeError.InvalidIndex)
  let start = data.layout.faultOffset+129*index
  DisputeResult[Fault](status: DisputeError.None, completed: Fault(
    target: DisputeHash(fixed[32](data.wire, start)), valid: data.wire[start+32] == 1,
    key: OffenderKey(fixed[32](data.wire, start+33)),
    signature: DisputeSignature(fixed[64](data.wire, start+65))))

# Re-emit an immutable validated snapshot atomically without exporting its storage.
proc encodeOwnedDisputes*(owner: OwnedDisputes, output: var openArray[byte]): DisputeResult[
    int] {.raises: [].} =
  # A default handle carries no validated snapshot, even when an empty result would be plausible.
  let data = owner.data
  if data == nil: return DisputeResult[int](status: DisputeError.InvalidOwner)
  let required = data.wire.len
  # Complete capacity is required before addresses or destination elements can be inspected.
  if output.len < required: return DisputeResult[int](status: DisputeError.OutputTooSmall)
  # Private storage remains protected even if foreign caller code fabricates an overlapping destination.
  if overlaps(unsafeAddr data.wire[0], required, addr output[0], required):
    return DisputeResult[int](status: DisputeError.AliasedBuffers)
  # All checks precede the first write; only the original validated prefix is copied.
  for i in 0..<required: output[i] = data.wire[i]
  DisputeResult[int](status: DisputeError.None, completed: required)

# Inspect all dispute sections without capturing bytes; only copied counts and exact progress leave the scan.
proc inspectDisputes*(input: openArray[byte], config: DisputeConfig): DisputeResult[
    DisputeInfo] {.raises: [].} =
  let scanned = scan(input, config)
  # Reuse the existing complete Boolean/index/order/extent validator.
  if scanned.error != DisputeError.None: return DisputeResult[DisputeInfo](status: scanned.error)
  DisputeResult[DisputeInfo](status: DisputeError.None, completed: scanned.value.info)
