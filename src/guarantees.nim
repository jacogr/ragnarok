## GP 0.8.0 C.2 guarantees: canonical reports, E4 slots and two/three E2-indexed credentials.
## Reports remain immutable owned snapshots; signatures are opaque and state eligibility is external.
import ./[natural, fixed_unsigned, bounded, composite, work_report, report_owned, owned, assurances]

type
  # A guarantee's evaluation slot is separate from anchor/lookup timeslots.
  GuaranteeSlot* = distinct uint32
  # A guarantor credential index cannot silently become an assurance-record index.
  GuarantorIndex* = distinct uint16
  # An exact Ed25519 wire encoding; no signature-validity claim is made by this codec.
  GuaranteeSignature* = distinct array[64, byte]
  # Complete owned credential bytes are independent of input lifetimes.
  GuaranteeCredential* = object
    validator*: GuarantorIndex
    signature*: GuaranteeSignature
  # A copied value retains its immutable report through ARC and owns its fixed credential array.
  Guarantee* = object
    report*: OwnedReport
    slot*: GuaranteeSlot
    credentials*: array[3, GuaranteeCredential]
    credentialCount*: int
  # Explicit structural ceilings; validator membership/rotation selection remains caller context.
  GuaranteeConfig* = object
    cores*: CoreCount
    validators*: ValidatorCount
    maxBytes*: ByteLimit
  # Failure-only reasons preserve framing errors and add owner/configuration/credential errors.
  GuaranteeError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, Truncated, NonCanonical, LimitExceeded,
    OutputTooSmall, AliasedBuffers, LengthOverflow, InvalidTag, InvalidReport,
    InvalidCredential, InvalidValidator, InvalidOwner, InvalidIndex
  # Tagged success is the only branch containing a value or progress.
  GuaranteeResult*[T] = object
    case error*: GuaranteeError
    of GuaranteeError.None:
      value*: T
    else:
      # Defaults and malformed nested reports expose no application value.
      discard
  # Private acyclic owner stores only complete owned records and their validated configuration.
  GuaranteesData = ref object
    values: seq[Guarantee]
    config: GuaranteeConfig
    consumed: int
  # Copying this opaque handle retains all reports and fixed metadata without exposing mutable storage.
  OwnedGuarantees* = object
    data: GuaranteesData
  # Successful prefix progress and its matching owner travel together.
  GuaranteesRead* = object
    owner*: OwnedGuarantees
    count*, consumed*: int
  # Preflight descriptors are private and used only while the original borrowed input is stable.
  ScannedGuarantee = object
    reportOffset, reportLength: int
    core: uint64
    slot: GuaranteeSlot
    credentials: array[3, GuaranteeCredential]
    credentialCount: int
  # A bounded local scan validates all records before any input-derived owner allocation.
  Scan = object
    values: array[341, ScannedGuarantee]
    count, consumed: int

# Validate chain ceilings before byte access; the same validator domain applies to assurances.
proc validConfig(config: GuaranteeConfig): bool {.raises: [].} =
  assurances.validConfig(AssuranceConfig(cores: config.cores, validators: config.validators))

# Preserve existing report framing/canonicality failures while keeping unrelated owner errors private.
proc reportError(error: CompositeError): GuaranteeError {.raises: [].} =
  case error
  of CompositeError.Truncated: GuaranteeError.Truncated # A required nested field is absent.
  of CompositeError.NonCanonical: GuaranteeError.NonCanonical # A nested set/count is not canonical.
  of CompositeError.LimitExceeded: GuaranteeError.LimitExceeded # Report policy failed.
  of CompositeError.LengthOverflow: GuaranteeError.LengthOverflow # A host extent cannot be represented.
  of CompositeError.InvalidTag: GuaranteeError.InvalidTag # A work-result alternative is unsupported.
  else: GuaranteeError.InvalidReport # No other status describes a usable decoded report here.

# Read all records without allocation or writes; private coordinates never leave the subsequent capture call.
proc scan(input: openArray[byte], config: GuaranteeConfig): GuaranteeResult[Scan] {.raises: [].} =
  # Invalid chain configuration cannot authorize an empty result or inspect attacker data.
  if not validConfig(config): return GuaranteeResult[Scan](error: GuaranteeError.InvalidConfig)
  var cursor = 0
  # Canonical numbers advance private parser state only after complete prefix validation.
  template readNumber(target: untyped) =
    block:
      let number = natural.decode(input.toOpenArray(cursor, input.high))
      # Preserve the original failure instead of narrowing a partial count.
      if not number.ok:
        return GuaranteeResult[Scan](error: if number.error ==
            natural.truncated: GuaranteeError.Truncated
          else: GuaranteeError.NonCanonical) # Overlong counts cannot select a second wire representation.
      target = uint64(number.value)
      cursor += int(number.consumed)
      # Every consumed prefix byte counts toward the explicitly supplied frame budget.
      if uint64(cursor) > uint64(config.maxBytes):
        return GuaranteeResult[Scan](error: GuaranteeError.LimitExceeded)
  var count: uint64
  readNumber(count)
  # At most one report per configured core bounds metadata before host conversion/allocation.
  if count > uint64(config.cores): return GuaranteeResult[Scan](error: GuaranteeError.LimitExceeded)
  var scanned: Scan
  scanned.count = int(count)
  # Validate all nested reports and credentials before allocating their retained owners.
  for i in 0..<scanned.count:
    let parsed = decodeReportBorrowed(input.toOpenArray(cursor, input.high), uint64(config.cores))
    # A malformed final report cannot publish any earlier guarantee owner.
    if parsed.error != CompositeError.None: return GuaranteeResult[Scan](error: reportError(parsed.error))
    let core = uint64(parsed.value.core)
    # Extrinsic report cores form a strictly increasing unique sequence.
    if i > 0 and core <= scanned.values[i-1].core:
      return GuaranteeResult[Scan](error: GuaranteeError.NonCanonical)
    scanned.values[i].reportOffset = cursor
    scanned.values[i].reportLength = parsed.consumed
    scanned.values[i].core = core
    cursor += parsed.consumed
    # Frame limits are independent of whether more borrowed trailing bytes happen to be available.
    if uint64(cursor) > uint64(config.maxBytes):
      return GuaranteeResult[Scan](error: GuaranteeError.LimitExceeded)
    # The complete E4 slot must exist before reading any of its little-endian octets.
    if input.len-cursor < 4: return GuaranteeResult[Scan](error: GuaranteeError.Truncated)
    scanned.values[i].slot = GuaranteeSlot(decodeFixed(input.toOpenArray(cursor, cursor+3),
        ByteWidth(4)).value)
    cursor += 4
    var credentials: uint64
    readNumber(credentials)
    # Credentials are exactly two or three, even when the source is otherwise syntactically decodable.
    if credentials < 2 or credentials > 3:
      return GuaranteeResult[Scan](error: GuaranteeError.InvalidCredential)
    # Divide before multiplying an untrusted extent; each record is E2 plus 64 signature bytes.
    if credentials > uint64((input.len-cursor) div 66):
      return GuaranteeResult[Scan](error: GuaranteeError.Truncated)
    let endCursor = cursor+int(credentials)*66
    # Check the complete final credential extent before copying any record metadata.
    if uint64(endCursor) > uint64(config.maxBytes):
      return GuaranteeResult[Scan](error: GuaranteeError.LimitExceeded)
    scanned.values[i].credentialCount = int(credentials)
    # Each copied credential owns exact bytes; signatures are not verified during decoding.
    for j in 0..<int(credentials):
      let validator = uint64(decodeFixed(input.toOpenArray(cursor, cursor+1), ByteWidth(2)).value)
      # An E2 representation alone does not establish membership in the caller's validator ceiling.
      if validator >= uint64(config.validators):
        return GuaranteeResult[Scan](error: GuaranteeError.InvalidValidator)
      # Duplicate or descending credential identities are not canonical input.
      if j > 0 and validator <= uint64(scanned.values[i].credentials[j-1].validator):
        return GuaranteeResult[Scan](error: GuaranteeError.NonCanonical)
      scanned.values[i].credentials[j].validator = GuarantorIndex(validator)
      var signature: array[64, byte]
      # Preserve every signature identity byte without interpreting cryptographic validity.
      for k in 0..<64: signature[k] = input[cursor+2+k]
      scanned.values[i].credentials[j].signature = GuaranteeSignature(signature)
      cursor += 66
  scanned.consumed = cursor
  GuaranteeResult[Scan](error: GuaranteeError.None, value: scanned)

# Capture only completely validated records, retaining no caller buffer or detached borrowed spans.
proc decodeGuarantees*(input: openArray[byte], config: GuaranteeConfig): GuaranteeResult[
    GuaranteesRead] {.raises: [].} =
  let scanned = scan(input, config)
  # No allocation based on an untrusted count occurs until the complete scan succeeds.
  if scanned.error != GuaranteeError.None: return GuaranteeResult[GuaranteesRead](
      error: scanned.error)
  let data = GuaranteesData(values: newSeq[Guarantee](scanned.value.count), config: config,
    consumed: scanned.value.consumed)
  # Reparse stable validated report slices into their existing private immutable owner API.
  for i in 0..<scanned.value.count:
    let record = scanned.value.values[i]
    let captured = decodeOwnedReport(input.toOpenArray(record.reportOffset,
      record.reportOffset+record.reportLength-1), uint64(config.cores))
    # Preserve a typed failure even if a future report-owner contract adds a new rejection.
    if captured.error != OwnershipError.None:
      return GuaranteeResult[GuaranteesRead](error: GuaranteeError.InvalidReport)
    data.values[i] = Guarantee(report: captured.value, slot: record.slot,
      credentials: record.credentials, credentialCount: record.credentialCount)
  GuaranteeResult[GuaranteesRead](error: GuaranteeError.None,
    value: GuaranteesRead(owner: OwnedGuarantees(data: data), count: data.values.len,
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

# Validate every report owner, credential and frame extent before authorizing a byte write.
proc measure(values: openArray[Guarantee], config: GuaranteeConfig): GuaranteeResult[
    int] {.raises: [].} =
  # Configuration and count ceilings precede access to any possibly default report owner.
  if not validConfig(config): return GuaranteeResult[int](error: GuaranteeError.InvalidConfig)
  if values.len > int(uint64(config.cores)): return GuaranteeResult[int](
      error: GuaranteeError.LimitExceeded)
  var required = int(natural.encode(JamNatural(values.len)).len)
  var previousCore = 0'u64
  # The final malformed source record must be discovered before committing an earlier record.
  for i, value in values:
    let report = ownedReportInfo(value.report)
    # Default report handles are not encodable as successfully validated empty reports.
    if report.error != OwnershipError.None: return GuaranteeResult[int](
        error: GuaranteeError.InvalidReport)
    let core = uint64(report.value.core)
    # A report captured under a broader profile must still meet this encoder's supplied ceiling.
    if core >= uint64(config.cores) or uint64(report.value.header.erasureShards) div 3 > uint64(config.cores):
      return GuaranteeResult[int](error: GuaranteeError.LimitExceeded)
    # Core order and uniqueness are required independently from any caller's earlier validation.
    if i > 0 and core <= previousCore: return GuaranteeResult[int](
        error: GuaranteeError.NonCanonical)
    previousCore = core
    # Only two or three valid, strictly ordered credential identities may be serialized.
    if value.credentialCount < 2 or value.credentialCount > 3:
      return GuaranteeResult[int](error: GuaranteeError.InvalidCredential)
    for j in 0..<value.credentialCount:
      # Fixed-width identity bytes still need membership in the caller's structural ceiling.
      if uint64(value.credentials[j].validator) >= uint64(config.validators):
        return GuaranteeResult[int](error: GuaranteeError.InvalidValidator)
      # Strict ordering rejects duplicate identities before serialization.
      if j > 0 and uint16(value.credentials[j].validator) <= uint16(value.credentials[
          j-1].validator):
        return GuaranteeResult[int](error: GuaranteeError.NonCanonical)
    let suffix = 5+66*value.credentialCount
    # Both additions are checked before the accumulated extent can overflow host arithmetic.
    if required > high(int)-suffix or report.value.consumed > high(int)-required-suffix:
      return GuaranteeResult[int](error: GuaranteeError.LengthOverflow)
    required += report.value.consumed+suffix
    # Stop measuring once a frame already exceeds the caller's byte budget.
    if uint64(required) > uint64(config.maxBytes):
      return GuaranteeResult[int](error: GuaranteeError.LimitExceeded)
  # The empty frame still consumes its one-byte count and must satisfy the same resource policy.
  if uint64(required) > uint64(config.maxBytes): return GuaranteeResult[int](
      error: GuaranteeError.LimitExceeded)
  GuaranteeResult[int](error: GuaranteeError.None, value: required)

# Serialize only after complete preflight; private report storage and all source records remain stable.
proc encodeGuarantees*(values: openArray[Guarantee], config: GuaranteeConfig,
                       output: var openArray[byte]): GuaranteeResult[int] {.raises: [].} =
  let measured = measure(values, config)
  # Failed sources expose only their reason and cannot affect destination sentinels.
  if measured.error != GuaranteeError.None: return measured
  let required = measured.value
  # All sources are valid; require the complete destination before checking or committing its bytes.
  if output.len < required: return GuaranteeResult[int](error: GuaranteeError.OutputTooSmall)
  # Guard host source extent arithmetic before checking the entire destination prefix for overlap.
  if values.len > high(int) div sizeof(Guarantee): return GuaranteeResult[int](
      error: GuaranteeError.LengthOverflow)
  if values.len > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(Guarantee), addr output[0], required):
    return GuaranteeResult[int](error: GuaranteeError.AliasedBuffers)
  # Every nested immutable report must be disjoint from the whole output, including other records' destinations.
  for value in values:
    let alias = ownedReportOverlapsOutput(value.report, output.toOpenArray(0, required-1))
    if alias.error != OwnershipError.None: return GuaranteeResult[int](
        error: GuaranteeError.InvalidReport)
    if alias.value: return GuaranteeResult[int](error: GuaranteeError.AliasedBuffers)
  let prefix = natural.encode(JamNatural(values.len))
  # Commit the canonical outer count after every source and alias check has succeeded.
  for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  var cursor = int(prefix.len)
  # Preflight proves every nested owner/extent and each fixed-width conversion before commit begins.
  for value in values:
    let report = encodeOwnedReport(value.report, output.toOpenArray(cursor, required-1))
    doAssert report.error == OwnershipError.None
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
  GuaranteeResult[int](error: GuaranteeError.None, value: required)

# Copy a fixed record and immutable report handle without exposing the owner's mutable sequence storage.
proc guaranteeAt*(owner: OwnedGuarantees, index: int): GuaranteeResult[Guarantee] {.raises: [].} =
  # Default handles and signed invalid indices must not fabricate a usable record.
  if owner.data.isNil: return GuaranteeResult[Guarantee](error: GuaranteeError.InvalidOwner)
  if index < 0 or index >= owner.data.values.len: return GuaranteeResult[Guarantee](
      error: GuaranteeError.InvalidIndex)
  GuaranteeResult[Guarantee](error: GuaranteeError.None, value: owner.data.values[index])

# Re-emit the validated owned sequence atomically without exporting its private bytes or record sequence.
proc encodeOwnedGuarantees*(owner: OwnedGuarantees, output: var openArray[byte]): GuaranteeResult[
    int] {.raises: [].} =
  # An uninitialized owner cannot stand in for a validated zero-record extrinsic.
  if owner.data.isNil: return GuaranteeResult[int](error: GuaranteeError.InvalidOwner)
  encodeGuarantees(owner.data.values, owner.data.config, output)

# Inspect all reports/credentials without capturing child owners; parent frames can preflight before allocation.
proc inspectGuarantees*(input: openArray[byte], config: GuaranteeConfig): GuaranteeResult[tuple[
    count, consumed: int]] {.raises: [].} =
  let scanned = scan(input, config)
  # The existing scan owns every normative framing/order/credential rule.
  if scanned.error != GuaranteeError.None:
    return GuaranteeResult[tuple[count, consumed: int]](error: scanned.error)
  GuaranteeResult[tuple[count, consumed: int]](error: GuaranteeError.None,
    value: (count: scanned.value.count, consumed: scanned.value.consumed))
