# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 C.2 guarantees: canonical reports, E4 slots and two/three E2-indexed credentials.
## Reports remain immutable owned snapshots; signatures are opaque and state eligibility is
## external.
##
## Exposes guarantee credentials, immutable guarantee collections, single/collection codecs and
## checked report access.

import std/assertions
import ./natural as codec_natural
import ./fixed_unsigned as codec_fixed_unsigned
import ./bounded as codec_bounded
import ./composite as codec_composite
import ./work_report as codec_work_report
import ./report_owned as codec_report_owned
import ./owned as codec_owned
import ./assurances as codec_assurances

type
  GuaranteeSlot* = distinct uint32 ## A guarantee's evaluation slot is separate from anchor/lookup timeslots.
  GuarantorIndex* = distinct uint16 ## A guarantor credential index cannot silently become an assurance-record index.
  GuaranteeSignature* = distinct array[64, byte] ## An exact Ed25519 wire encoding; no signature-validity claim is made by this codec.
  GuaranteeCredential* = object ## Complete owned credential bytes are independent of input lifetimes.
    validator*: GuarantorIndex
    signature*: GuaranteeSignature
  Guarantee* = object ## A copied value retains its immutable report through ARC and owns its fixed credential array.
    report*: OwnedReport
    slot*: GuaranteeSlot
    credentials*: array[3, GuaranteeCredential]
    credentialCount*: int
  GuaranteeConfig* = object ## Explicit structural ceilings; validator membership/rotation selection remains caller context.
    cores*: CoreCount
    validators*: ValidatorCount
    maxBytes*: ByteLimit
  GuaranteeError* {.pure.} = enum ## Failure-only reasons preserve framing errors and add owner/configuration/credential errors.
    Uninitialized, None, InvalidConfig, Truncated, NonCanonical, LimitExceeded,
    OutputTooSmall, AliasedBuffers, LengthOverflow, InvalidTag, InvalidReport,
    InvalidCredential, InvalidValidator, InvalidOwner, InvalidIndex
  GuaranteeResult*[T] = object ## Tagged success is the only branch containing a value or progress.
    case status: GuaranteeError
    of None:
      completed: T
    else:
      # Defaults and malformed nested reports expose no application value.
      discard
  GuaranteeRead* = object ## One complete standalone guarantee, without an extrinsic sequence count prefix.
    value*: Guarantee
    consumed*: int
  # Private acyclic owner stores only complete owned records and their validated configuration.
  GuaranteesData = ref object
    values: seq[Guarantee]
    config: GuaranteeConfig
    consumed: int
  OwnedGuarantees* = object ## Copying this opaque handle retains all reports and fixed metadata without exposing mutable storage.
    data: nil GuaranteesData
  GuaranteesRead* = object ## Successful prefix progress and its matching owner travel together.
    owner*: OwnedGuarantees
    count*, consumed*: int
  # Preflight descriptors are private and used only while the original borrowed input is stable.
  ScannedGuarantee = object
    reportOffset, reportLength, endCursor: int
    core: uint64
    slot: GuaranteeSlot
    credentials: array[3, GuaranteeCredential]
    credentialCount: int
  # A bounded local scan validates all records before any input-derived owner allocation.
  Scan = object
    values: array[341, ScannedGuarantee]
    count, consumed: int

func error*[T](value: GuaranteeResult[T]): GuaranteeError =
  ## Read a generic guarantee outcome without permitting callers to retag its private state.
  value.status
func value*[T](value: GuaranteeResult[T]): T {.inline, requires: value.status ==
    GuaranteeError.None.} =
  ## Only complete operations expose their value, owner or progress metadata.
  value.completed
func guaranteeFailure*[T](reason: GuaranteeError): GuaranteeResult[T] {.requires: reason !=
    GuaranteeError.None.} =
  ## Sibling adapters may report a failure, never manufacture success without a completed value.
  GuaranteeResult[T](status: reason)

# Validate chain ceilings before byte access; the same validator domain applies to assurances.
proc validConfig(config: GuaranteeConfig): bool {.raises: [].} =
  codec_assurances.validConfig(AssuranceConfig(cores: config.cores, validators: config.validators))

# Preserve existing report framing/canonicality failures while keeping unrelated owner errors private.
proc reportError(error: CompositeError): GuaranteeError {.raises: [].} =
  case error
  of CompositeError.Truncated: GuaranteeError.Truncated # A required nested field is absent.
  of CompositeError.NonCanonical: GuaranteeError.NonCanonical # A nested set/count is not canonical.
  of CompositeError.LimitExceeded: GuaranteeError.LimitExceeded # Report policy failed.
  of CompositeError.LengthOverflow: GuaranteeError.LengthOverflow # A host extent cannot be represented.
  of CompositeError.InvalidTag: GuaranteeError.InvalidTag # A work-result alternative is unsupported.
  else: GuaranteeError.InvalidReport # No other status describes a usable decoded report here.

# Scan a single record at a private absolute frame offset; optional prior-core ordering preserves extrinsic error precedence.
proc scanRecord(input: openArray[byte], start: int, config: GuaranteeConfig,
                previousCore: uint64 = 0, ordered: bool = false): GuaranteeResult[
                    ScannedGuarantee] {.raises: [].} =
  var cursor = start
  var record: ScannedGuarantee = default(ScannedGuarantee)
  # Canonical numbers advance private parser state only after complete prefix validation.
  template readNumber(target: untyped) =
    block:
      let number = codec_natural.decode(input.toOpenArray(cursor, input.high))
      # Preserve the original failure instead of narrowing a partial count.
      if not number.ok:
        return GuaranteeResult[ScannedGuarantee](status: if number.error ==
            codec_natural.truncated: GuaranteeError.Truncated
          else: GuaranteeError.NonCanonical) # Overlong counts cannot select a second wire representation.
      target = uint64(number.value)
      cursor += int(number.consumed)
      # Every consumed prefix byte counts toward the explicitly supplied frame budget.
      if uint64(cursor) > uint64(config.maxBytes):
        return GuaranteeResult[ScannedGuarantee](status: GuaranteeError.LimitExceeded)
  let parsed = decodeReportBorrowed(input.toOpenArray(cursor, input.high), uint64(config.cores))
  # A malformed final report cannot publish any earlier guarantee owner.
  if parsed.error != CompositeError.None: return GuaranteeResult[ScannedGuarantee](
      status: reportError(parsed.error))
  let core = uint64(parsed.value.core)
  # Extrinsic report cores form a strictly increasing unique sequence.
  if ordered and core <= previousCore:
    return GuaranteeResult[ScannedGuarantee](status: GuaranteeError.NonCanonical)
  record.reportOffset = cursor
  record.reportLength = parsed.consumed
  record.core = core
  cursor += parsed.consumed
  # Frame limits are independent of whether more borrowed trailing bytes happen to be available.
  if uint64(cursor) > uint64(config.maxBytes):
    return GuaranteeResult[ScannedGuarantee](status: GuaranteeError.LimitExceeded)
  # The complete E4 slot must exist before reading any of its little-endian octets.
  if input.len-cursor < 4: return GuaranteeResult[ScannedGuarantee](
      status: GuaranteeError.Truncated)
  record.slot = GuaranteeSlot(decodeFixed(input.toOpenArray(cursor, cursor+3),
      ByteWidth(4)).value)
  cursor += 4
  var credentials: uint64 = 0
  readNumber(credentials)
  # Credentials are exactly two or three, even when the source is otherwise syntactically decodable.
  if credentials < 2 or credentials > 3:
    return GuaranteeResult[ScannedGuarantee](status: GuaranteeError.InvalidCredential)
  # Divide before multiplying an untrusted extent; each record is E2 plus 64 signature bytes.
  if credentials > uint64((input.len-cursor) div 66):
    return GuaranteeResult[ScannedGuarantee](status: GuaranteeError.Truncated)
  let endCursor = cursor+int(credentials)*66
  # Check the complete final credential extent before copying any record metadata.
  if uint64(endCursor) > uint64(config.maxBytes):
    return GuaranteeResult[ScannedGuarantee](status: GuaranteeError.LimitExceeded)
  record.credentialCount = int(credentials)
  # Each copied credential owns exact bytes; signatures are not verified during decoding.
  for j in 0..<int(credentials):
    let validator = uint64(decodeFixed(input.toOpenArray(cursor, cursor+1), ByteWidth(2)).value)
    # An E2 representation alone does not establish membership in the caller's validator ceiling.
    if validator >= uint64(config.validators):
      return GuaranteeResult[ScannedGuarantee](status: GuaranteeError.InvalidValidator)
    # Duplicate or descending credential identities are not canonical input.
    if j > 0 and validator <= uint64(record.credentials[j-1].validator):
      return GuaranteeResult[ScannedGuarantee](status: GuaranteeError.NonCanonical)
    record.credentials[j].validator = GuarantorIndex(validator)
    var signature: array[64, byte] = default(array[64, byte])
    # Preserve every signature identity byte without interpreting cryptographic validity.
    for k in 0..<64: signature[k] = input[cursor+2+k]
    record.credentials[j].signature = GuaranteeSignature(signature)
    cursor += 66
  record.endCursor = cursor
  GuaranteeResult[ScannedGuarantee](status: GuaranteeError.None, completed: record)

# Read all records without allocation or writes; private coordinates never leave the subsequent capture call.
proc scan(input: openArray[byte], config: GuaranteeConfig): GuaranteeResult[Scan] {.raises: [].} =
  # Invalid chain configuration cannot authorize an empty result or inspect attacker data.
  if not validConfig(config): return GuaranteeResult[Scan](status: GuaranteeError.InvalidConfig)
  var cursor = 0
  # Canonical numbers advance private parser state only after complete prefix validation.
  template readNumber(target: untyped) =
    block:
      let number = codec_natural.decode(input.toOpenArray(cursor, input.high))
      # Preserve the original failure instead of narrowing a partial count.
      if not number.ok:
        return GuaranteeResult[Scan](status: if number.error ==
            codec_natural.truncated: GuaranteeError.Truncated
          else: GuaranteeError.NonCanonical) # Overlong counts cannot select a second wire representation.
      target = uint64(number.value)
      cursor += int(number.consumed)
      # Every consumed prefix byte counts toward the explicitly supplied frame budget.
      if uint64(cursor) > uint64(config.maxBytes):
        return GuaranteeResult[Scan](status: GuaranteeError.LimitExceeded)
  var count: uint64 = 0
  readNumber(count)
  # At most one report per configured core bounds metadata before host conversion/allocation.
  if count > uint64(config.cores): return GuaranteeResult[Scan](
      status: GuaranteeError.LimitExceeded)
  var scanned: Scan = default(Scan)
  scanned.count = int(count)
  # Validate all nested reports and credentials before allocating their retained owners.
  for i in 0..<scanned.count:
    # Only records after the first have a previous core to enforce unique ascending order.
    let record = scanRecord(input, cursor, config,
      previousCore = (if i > 0: scanned.values[i-1].core else: 0), ordered = i > 0)
    if record.error != GuaranteeError.None:
      return GuaranteeResult[Scan](status: record.error) # A late record failure cannot publish an earlier owner.
    scanned.values[i] = record.value
    cursor = record.value.endCursor
  scanned.consumed = cursor
  GuaranteeResult[Scan](status: GuaranteeError.None, completed: scanned)

proc decodeGuarantees*(input: openArray[byte], config: GuaranteeConfig): GuaranteeResult[
    GuaranteesRead] {.raises: [].} =
  ## Capture only completely validated records, retaining no caller buffer or detached borrowed spans.
  let scanned = scan(input, config)
  # No allocation based on an untrusted count occurs until the complete scan succeeds.
  if scanned.error != GuaranteeError.None: return GuaranteeResult[GuaranteesRead](
      status: scanned.error)
  let data = GuaranteesData(values: newSeq[Guarantee](scanned.value.count), config: config,
    consumed: scanned.value.consumed)
  # Reparse stable validated report slices into their existing private immutable owner API.
  for i in 0..<scanned.value.count:
    let record = scanned.value.values[i]
    let captured = decodeOwnedReport(input.toOpenArray(record.reportOffset,
      record.reportOffset+record.reportLength-1), uint64(config.cores))
    # Preserve a typed failure even if a future report-owner contract adds a new rejection.
    if captured.error != OwnershipError.None:
      return GuaranteeResult[GuaranteesRead](status: GuaranteeError.InvalidReport)
    data.values[i] = Guarantee(report: captured.value, slot: record.slot,
      credentials: record.credentials, credentialCount: record.credentialCount)
  GuaranteeResult[GuaranteesRead](status: GuaranteeError.None,
    completed: GuaranteesRead(owner: OwnedGuarantees(data: data), count: data.values.len,
        consumed: data.consumed))

# Compare addresses by distance so even empty or near-address-limit ranges need no overflowing endpoint sum.
proc overlaps(a: pointer, an: int, b: pointer, bn: int): bool {.raises: [].} =
  # Empty ranges cannot alias and require no valid element address.
  if an == 0 or bn == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  # Measure from the lower address in either ordering.
  if left <= right: right-left < uint(an)
  else: left-right < uint(bn) # Reverse when the mutable destination comes first.

# Validate and charge one owned source record into its enclosing byte extent without allocating.
proc chargeRecord(value: Guarantee, config: GuaranteeConfig, required: var int,
                  previousCore: uint64 = 0, ordered: bool = false): GuaranteeResult[
                      uint64] {.raises: [].} =
  let report = ownedReportInfo(value.report)
  # Default report handles are not encodable as successfully validated empty reports.
  if report.error != OwnershipError.None: return GuaranteeResult[uint64](
      status: GuaranteeError.InvalidReport)
  let core = uint64(report.value.core)
  # A report captured under a broader profile must still meet this encoder's supplied ceiling.
  if core >= uint64(config.cores) or uint64(report.value.header.erasureShards) div 3 > uint64(config.cores):
    return GuaranteeResult[uint64](status: GuaranteeError.LimitExceeded)
  # Core order and uniqueness are required independently from any caller's earlier validation.
  if ordered and core <= previousCore: return GuaranteeResult[uint64](
      status: GuaranteeError.NonCanonical)
  # Only two or three valid, strictly ordered credential identities may be serialized.
  if value.credentialCount < 2 or value.credentialCount > 3:
    return GuaranteeResult[uint64](status: GuaranteeError.InvalidCredential)
  for j in 0..<value.credentialCount:
    # Fixed-width identity bytes still need membership in the caller's structural ceiling.
    if uint64(value.credentials[j].validator) >= uint64(config.validators):
      return GuaranteeResult[uint64](status: GuaranteeError.InvalidValidator)
    # Strict ordering rejects duplicate identities before serialization.
    if j > 0 and uint16(value.credentials[j].validator) <= uint16(value.credentials[
        j-1].validator):
      return GuaranteeResult[uint64](status: GuaranteeError.NonCanonical)
  let suffix = 5+66*value.credentialCount
  # Both additions are checked before the accumulated extent can overflow host arithmetic.
  if required > high(int)-suffix or report.value.consumed > high(int)-required-suffix:
    return GuaranteeResult[uint64](status: GuaranteeError.LengthOverflow)
  required += report.value.consumed+suffix
  # Stop measuring once a frame already exceeds the caller's byte budget.
  if uint64(required) > uint64(config.maxBytes):
    return GuaranteeResult[uint64](status: GuaranteeError.LimitExceeded)
  GuaranteeResult[uint64](status: GuaranteeError.None, completed: core)

# Validate every report owner, credential and frame extent before authorizing a byte write.
proc measure(values: openArray[Guarantee], config: GuaranteeConfig): GuaranteeResult[
    int] {.raises: [].} =
  # Configuration and count ceilings precede access to any possibly default report owner.
  if not validConfig(config): return GuaranteeResult[int](status: GuaranteeError.InvalidConfig)
  if values.len > int(uint64(config.cores)): return GuaranteeResult[int](
      status: GuaranteeError.LimitExceeded)
  var required = int(codec_natural.encode(JamNatural(values.len)).len)
  var previousCore = 0'u64
  # The final malformed source record must be discovered before committing an earlier record.
  for i, value in values:
    let charged = chargeRecord(value, config, required, previousCore, i > 0)
    if charged.error != GuaranteeError.None:
      return GuaranteeResult[int](status: charged.error) # Whole-source failure precedes all output writes.
    previousCore = charged.value
  # The empty frame still consumes its one-byte count and must satisfy the same resource policy.
  if uint64(required) > uint64(config.maxBytes): return GuaranteeResult[int](
      status: GuaranteeError.LimitExceeded)
  GuaranteeResult[int](status: GuaranteeError.None, completed: required)

# Commit one fully preflighted stable record; output/report disjointness is proved by the enclosing encoder.
proc writeRecord(value: Guarantee, output: var openArray[byte], cursor: var int,
                 required: int) {.raises: [].} =
  let report = encodeOwnedReport(value.report, output.toOpenArray(cursor, required-1))
  assert report.error == OwnershipError.None
  cursor += report.value
  let slot = encodeFixed(FixedUnsigned(uint32(value.slot)), ByteWidth(4))
  # Timeslots are E4 even when their compact natural representation would be shorter.
  for i in 0..<4: output[cursor+i] = slot.encoded.bytes[i]
  cursor += 4
  output[cursor] = byte(value.credentialCount)
  inc cursor
  # Credential count two/three is canonically one octet; indices remain fixed E2.
  for j in 0..<value.credentialCount:
    let credential = value.credentials[j]
    let validator = encodeFixed(FixedUnsigned(uint16(credential.validator)), ByteWidth(2))
    for k in 0..<2: output[cursor+k] = validator.encoded.bytes[k] # Commit the proved identity width.
    let signature = array[64, byte](credential.signature)
    for k in 0..<64: output[cursor+2+k] = signature[k] # Preserve all opaque signature bytes.
    cursor += 66

proc encodeGuarantees*(values: openArray[Guarantee], config: GuaranteeConfig,
                       output: var openArray[byte]): GuaranteeResult[int] {.raises: [].} =
  ## Serialize only after complete preflight; private report storage and all source records remain stable.
  let measured = measure(values, config)
  # Failed sources expose only their reason and cannot affect destination sentinels.
  if measured.error != GuaranteeError.None: return measured
  let required = measured.value
  # All sources are valid; require the complete destination before checking or committing its bytes.
  if output.len < required: return GuaranteeResult[int](status: GuaranteeError.OutputTooSmall)
  # Guard host source extent arithmetic before checking the entire destination prefix for overlap.
  if values.len > high(int) div sizeof(Guarantee): return GuaranteeResult[int](
      status: GuaranteeError.LengthOverflow)
  if values.len > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(Guarantee), addr output[0], required):
    return GuaranteeResult[int](status: GuaranteeError.AliasedBuffers)
  # Every nested immutable report must be disjoint from the whole output, including other records' destinations.
  for value in values:
    let alias = ownedReportOverlapsOutput(value.report, output.toOpenArray(0, required-1))
    if alias.error != OwnershipError.None: return GuaranteeResult[int](
        status: GuaranteeError.InvalidReport)
    if alias.value: return GuaranteeResult[int](status: GuaranteeError.AliasedBuffers)
  let prefix = codec_natural.encode(JamNatural(values.len))
  # Commit the canonical outer count after every source and alias check has succeeded.
  for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  var cursor = int(prefix.len)
  # Preflight proves every nested owner/extent and each fixed-width conversion before commit begins.
  for value in values:
    writeRecord(value, output, cursor, required)
  GuaranteeResult[int](status: GuaranteeError.None, completed: required)

proc guaranteeAt*(owner: OwnedGuarantees, index: int): GuaranteeResult[Guarantee] {.raises: [].} =
  ## Copy a fixed record and immutable report handle without exposing the owner's mutable sequence storage.
  # Default handles and signed invalid indices must not fabricate a usable record.
  let data = owner.data
  if data == nil: return GuaranteeResult[Guarantee](status: GuaranteeError.InvalidOwner)
  # A stable checked reference retains all child reports throughout indexed access.
  if index < 0 or index >= data.values.len: return GuaranteeResult[Guarantee](
      status: GuaranteeError.InvalidIndex)
  GuaranteeResult[Guarantee](status: GuaranteeError.None, completed: data.values[index])

proc encodeOwnedGuarantees*(owner: OwnedGuarantees, output: var openArray[byte]): GuaranteeResult[
    int] {.raises: [].} =
  ## Re-emit the validated owned sequence atomically without exporting its private bytes or record sequence.
  # An uninitialized owner cannot stand in for a validated zero-record extrinsic.
  let data = owner.data
  if data == nil: return GuaranteeResult[int](status: GuaranteeError.InvalidOwner)
  encodeGuarantees(data.values, data.config, output)

proc inspectGuarantees*(input: openArray[byte], config: GuaranteeConfig): GuaranteeResult[tuple[
    count, consumed: int]] {.raises: [].} =
  ## Inspect all reports/credentials without capturing child owners; parent frames can preflight before allocation.
  let scanned = scan(input, config)
  # The existing scan owns every normative framing/order/credential rule.
  if scanned.error != GuaranteeError.None:
    return GuaranteeResult[tuple[count, consumed: int]](status: scanned.error)
  GuaranteeResult[tuple[count, consumed: int]](status: GuaranteeError.None,
    completed: (count: scanned.value.count, consumed: scanned.value.consumed))

proc inspectGuarantee*(input: openArray[byte], config: GuaranteeConfig): GuaranteeResult[tuple[
    core: CoreIndex, consumed: int]] {.raises: [].} =
  ## Inspect one standalone guarantee prefix without an extrinsic count or child-owner allocation.
  if not validConfig(config):
    return GuaranteeResult[tuple[core: CoreIndex, consumed: int]](
        status: GuaranteeError.InvalidConfig) # Configuration precedes input access.
  let scanned = scanRecord(input, 0, config)
  if scanned.error != GuaranteeError.None:
    return GuaranteeResult[tuple[core: CoreIndex, consumed: int]](
        status: scanned.error) # No partial record metadata.
  GuaranteeResult[tuple[core: CoreIndex, consumed: int]](status: GuaranteeError.None,
    completed: (CoreIndex(scanned.value.core), scanned.value.endCursor))

proc decodeGuarantee*(input: openArray[byte], config: GuaranteeConfig): GuaranteeResult[
    GuaranteeRead] {.raises: [].} =
  ## Capture one standalone guarantee only after its complete report, E4 slot and credentials validate.
  if not validConfig(config): return GuaranteeResult[GuaranteeRead](
      status: GuaranteeError.InvalidConfig) # Never inspect input under invalid policy.
  let scanned = scanRecord(input, 0, config)
  if scanned.error != GuaranteeError.None: return GuaranteeResult[GuaranteeRead](
      status: scanned.error) # No child owner after a late failure.
  let record = scanned.value
  let report = decodeOwnedReport(input.toOpenArray(record.reportOffset,
      record.reportOffset+record.reportLength-1), uint64(config.cores))
  if report.error != OwnershipError.None: return GuaranteeResult[GuaranteeRead](
      status: GuaranteeError.InvalidReport) # Preserve future owner rejections.
  GuaranteeResult[GuaranteeRead](status: GuaranteeError.None, completed: GuaranteeRead(
    value: Guarantee(report: report.value, slot: record.slot, credentials: record.credentials,
      credentialCount: record.credentialCount), consumed: record.endCursor))

proc measureGuarantee*(value: Guarantee, config: GuaranteeConfig): GuaranteeResult[int] {.raises: [].} =
  ## Measure a standalone record with the same policy as the extrinsic, excluding the outer sequence count.
  if not validConfig(config): return GuaranteeResult[int](
      status: GuaranteeError.InvalidConfig) # Default owners are inspected only under valid policy.
  var required = 0
  let checked = chargeRecord(value, config, required)
  if checked.error != GuaranteeError.None: return GuaranteeResult[int](
      status: checked.error) # No size on failure.
  GuaranteeResult[int](status: GuaranteeError.None, completed: required)

proc encodeGuaranteeValue*(value: Guarantee, config: GuaranteeConfig): GuaranteeResult[seq[
    byte]] {.raises: [].} =
  ## Return fresh standalone record bytes; no caller output can alias immutable reports or source credentials.
  let measured = measureGuarantee(value, config)
  if measured.error != GuaranteeError.None:
    return GuaranteeResult[seq[byte]](status: measured.error) # Full source preflight precedes allocation.
  var output = newSeq[byte](measured.value)
  var cursor = 0
  writeRecord(value, output, cursor, output.len)
  GuaranteeResult[seq[byte]](status: GuaranteeError.None, completed: output)
