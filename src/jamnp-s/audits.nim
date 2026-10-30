# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JAMNP-S aa0e2b8 CE144/145 complete-message codecs. The message extent supplies the batch
## length; there is no outer compact count. Invalid judgments carry their guarantee before
## the report hash/signature. Structural decoding never authenticates VRF or Ed25519 evidence.
##
## Decoders validate the complete bounded message before allocating immutable batch storage.
## Accessors return detached fixed-size records; callers cannot mutate a batch's backing data.

import ../codec/[assurances, bounded, disputes, guarantees]

type
  AuditHeaderHash* = distinct array[32, byte] ## Identifies the audited block, independently of a disputed report.
  AuditCoreIndex* = distinct uint16 ## CE144's fixed E2 core representation is not a general GP natural.
  AuditProof* = distinct array[96, byte] ## Opaque Thin signature bytes require contextual verification before use.
  AuditIntent* {.pure.} = enum ## Initial cores are derived from the proof; a later intent names one core.
    Initial, Later
  AuditAnnouncement* = object ## Fixed owned bytes carry a structural claim, never an authenticated audit requirement.
    header*: AuditHeaderHash
    validator*: JudgeIndex
    intent*: AuditIntent
    core*: AuditCoreIndex
    proof*: AuditProof
  AuditJudgment* = object ## Positive judgments have no guarantee; invalid judgments own exactly two or three credentials.
    epoch*: DisputeEpoch
    validator*: JudgeIndex
    valid*: bool
    report*: DisputeHash
    signature*: DisputeSignature
    slot*: GuaranteeSlot
    credentialCount*: int
    credentials*: array[3, GuaranteeCredential]
  AuditLimits* = object ## Population/core ceilings cover all epochs in a batch; actual epoch membership is checked by the host.
    validators*: ValidatorCount
    cores*: CoreCount
    bytes*: ByteLimit
    records*: ElementLimit
  AuditError* {.pure.} = enum ## No failed/default result exposes a record, owner or consumed prefix.
    Uninitialized, None, InvalidPolicy, LimitExceeded, Truncated, InvalidTag,
    InvalidValidator, InvalidCore, InvalidGuarantee, InvalidOwner, InvalidIndex
  AuditResult*[T] = object ## Private success accessors enforce complete-message acceptance.
    case status: AuditError
    of None: completed: T
    else: discard          # Failures carry only their reason.
  AnnouncementData = ref object ## Acyclic backing records are private and immutable after validated capture.
    records: seq[AuditAnnouncement]
  JudgmentData = ref object ## Copies of a batch retain one immutable snapshot without exporting its mutable seq.
    records: seq[AuditJudgment]
  AnnouncementBatch* = object ## No parser offsets or borrowed caller storage escape through this handle.
    data: nil AnnouncementData
  JudgmentBatch* = object ## The immutable snapshot survives replacement of the original input buffer.
    data: nil JudgmentData

func error*[T](outcome: AuditResult[T]): AuditError =
  ## Observe a failure without exposing any partial result.
  outcome.status
func value*[T](outcome: AuditResult[T]): T {.inline, requires: outcome.status == AuditError.None.} =
  ## Read an operation's complete validated payload only after success.
  outcome.completed

proc valid(limits: AuditLimits): bool =
  ## Validate the caller's chain domains independently of attacker-controlled bytes.
  uint64(limits.validators) in 6'u64..1023'u64 and uint64(limits.validators) mod 3 == 0 and
    uint64(limits.cores) in 2'u64..341'u64 and uint64(limits.records) > 0

proc integer(input: openArray[byte], offset, width: int): uint32 =
  ## Callers prove the complete two/four-byte extent before entering this fixed-width helper.
  result = 0
  for i in 0..<width: result = result or (uint32(input[offset+i]) shl (8*i))

proc fixed[N: static[int]](input: openArray[byte], offset: int): array[N, byte] =
  ## Copy a proven fixed extent without retaining a borrow into the caller's buffer.
  result = default(array[N, byte])
  for i in 0..<N: result[i] = input[offset+i]

proc scanAnnouncement(input: openArray[byte], offset: int,
    limits: AuditLimits): AuditResult[int] =
  ## Check one record and return its complete width, keeping failed offsets private.
  if input.len-offset < 131: return AuditResult[int](status: AuditError.Truncated)
  if uint64(integer(input, offset+32, 2)) >= uint64(limits.validators):
    return AuditResult[int](status: AuditError.InvalidValidator)
  case input[offset+34]
  of 0: return AuditResult[int](status: AuditError.None, completed: 131)
  of 1:
    # The later intent adds an E2 core before the proof; never index it from an incomplete record.
    if input.len-offset < 133: return AuditResult[int](status: AuditError.Truncated)
    if uint64(integer(input, offset+35, 2)) >= uint64(limits.cores):
      return AuditResult[int](status: AuditError.InvalidCore)
    return AuditResult[int](status: AuditError.None, completed: 133)
  else: return AuditResult[int](status: AuditError.InvalidTag) # Legacy tranche/evidence forms have no fallback.

proc scanJudgment(input: openArray[byte], offset: int,
    limits: AuditLimits): AuditResult[int] =
  ## A negative validity embeds a bounded canonical guarantee before the fixed report/signature tail.
  if input.len-offset < 103: return AuditResult[int](status: AuditError.Truncated)
  if uint64(integer(input, offset+4, 2)) >= uint64(limits.validators):
    return AuditResult[int](status: AuditError.InvalidValidator)
  case input[offset+6]
  of 1: return AuditResult[int](status: AuditError.None, completed: 103)
  of 0:
    # Two/three use their one-byte canonical GP compact encoding; longer encodings are not accepted.
    let count = int(input[offset+11])
    if count != 2 and count != 3: return AuditResult[int](status: AuditError.InvalidGuarantee)
    let width = 108 + count*66
    if input.len-offset < width: return AuditResult[int](status: AuditError.Truncated)
    var previous = 0'u32
    # GP guarantee credentials are strictly increasing, unique validator identities.
    for i in 0..<count:
      let index = integer(input, offset+12+i*66, 2)
      if uint64(index) >= uint64(limits.validators):
        return AuditResult[int](status: AuditError.InvalidValidator)
      if i > 0 and index <= previous:
        return AuditResult[int](status: AuditError.InvalidGuarantee)
      previous = index
    return AuditResult[int](status: AuditError.None, completed: width)
  else: return AuditResult[int](status: AuditError.InvalidTag)

proc scan(input: openArray[byte], limits: AuditLimits, judgments: bool): AuditResult[int] =
  ## Prove every record and the entire batch count before allocating retained storage.
  if not valid(limits): return AuditResult[int](status: AuditError.InvalidPolicy)
  if uint64(input.len) > uint64(limits.bytes): return AuditResult[int](
      status: AuditError.LimitExceeded)
  var offset = 0
  var count = 0
  # Each iteration advances by a proven complete nonzero width, bounded by the message extent.
  while offset < input.len:
    if uint64(count) >= uint64(limits.records):
      return AuditResult[int](status: AuditError.LimitExceeded)
    let checked = if judgments: scanJudgment(input, offset, limits)
      else: scanAnnouncement(input, offset, limits)
    if checked.error != AuditError.None: return AuditResult[int](status: checked.error)
    offset += checked.value
    inc count
  AuditResult[int](status: AuditError.None, completed: count)

proc decodeAnnouncements*(input: openArray[byte], limits: AuditLimits): AuditResult[
    AnnouncementBatch] =
  ## Capture a complete CE144 batch after a no-allocation validation pass.
  let checked = scan(input, limits, false)
  if checked.error != AuditError.None: return AuditResult[AnnouncementBatch](status: checked.error)
  var records = newSeq[AuditAnnouncement](checked.value)
  var offset = 0
  # The validated widths bind every field to the caller's stable synchronous input.
  for i in 0..<records.len:
    var record = AuditAnnouncement(header: AuditHeaderHash(fixed[32](input, offset)),
        validator: JudgeIndex(integer(input, offset+32, 2)), intent: AuditIntent.Initial)
    var proofOffset = offset+35
    if input[offset+34] == 1:
      record.intent = AuditIntent.Later
      record.core = AuditCoreIndex(integer(input, offset+35, 2))
      proofOffset += 2
    record.proof = AuditProof(fixed[96](input, proofOffset))
    records[i] = record
    offset = proofOffset+96
  AuditResult[AnnouncementBatch](status: AuditError.None,
      completed: AnnouncementBatch(data: AnnouncementData(records: records)))

proc decodeJudgments*(input: openArray[byte], limits: AuditLimits): AuditResult[JudgmentBatch] =
  ## Capture a CE145 batch, preserving different epochs and auditors without imposing batch-wide equality.
  let checked = scan(input, limits, true)
  if checked.error != AuditError.None: return AuditResult[JudgmentBatch](status: checked.error)
  var records = newSeq[AuditJudgment](checked.value)
  var offset = 0
  # Read only extents established by scan, without borrowing the caller's bytes after return.
  for i in 0..<records.len:
    var record = AuditJudgment(epoch: DisputeEpoch(integer(input, offset, 4)),
        validator: JudgeIndex(integer(input, offset+4, 2)), valid: input[offset+6] == 1)
    var tail = offset+7
    if not record.valid:
      record.slot = GuaranteeSlot(integer(input, tail, 4))
      record.credentialCount = int(input[tail+4])
      tail += 5
      # The scanner proved two or three complete strictly ordered credentials.
      for j in 0..<record.credentialCount:
        record.credentials[j] = GuaranteeCredential(validator: GuarantorIndex(integer(input, tail,
            2)), signature: GuaranteeSignature(fixed[64](input, tail+2)))
        tail += 66
    record.report = DisputeHash(fixed[32](input, tail))
    record.signature = DisputeSignature(fixed[64](input, tail+32))
    records[i] = record
    offset = tail+96
  AuditResult[JudgmentBatch](status: AuditError.None,
      completed: JudgmentBatch(data: JudgmentData(records: records)))

proc len*(batch: AnnouncementBatch): int =
  ## An uninitialized owner contains no accessible records.
  let data = batch.data
  if data == nil: return 0
  data.records.len
proc len*(batch: JudgmentBatch): int =
  ## Report only complete retained records; a default owner has no storage.
  let data = batch.data
  if data == nil: return 0
  data.records.len
proc announcementAt*(batch: AnnouncementBatch, index: int): AuditResult[AuditAnnouncement] =
  ## Return a detached fixed record; no mutable backing sequence is exported.
  let data = batch.data
  if data == nil: return AuditResult[AuditAnnouncement](status: AuditError.InvalidOwner)
  if index < 0 or index >= data.records.len:
    return AuditResult[AuditAnnouncement](status: AuditError.InvalidIndex)
  AuditResult[AuditAnnouncement](status: AuditError.None, completed: data.records[index])
proc judgmentAt*(batch: JudgmentBatch, index: int): AuditResult[AuditJudgment] =
  ## Bind lookup to the immutable batch and validate signed indices before access.
  let data = batch.data
  if data == nil: return AuditResult[AuditJudgment](status: AuditError.InvalidOwner)
  if index < 0 or index >= data.records.len:
    return AuditResult[AuditJudgment](status: AuditError.InvalidIndex)
  AuditResult[AuditJudgment](status: AuditError.None, completed: data.records[index])

proc charge(total: var int, width: int, limits: AuditLimits): bool =
  ## Prove host addition and the caller's byte ceiling before growing an encoder's allocation.
  if width > high(int)-total: return false
  if uint64(total+width) > uint64(limits.bytes): return false
  total += width
  true

proc writeInteger(output: var seq[byte], offset: int, value: uint32, width: int) =
  ## The complete measured output extent is allocated before writing fixed E2/E4 fields.
  for i in 0..<width: output[offset+i] = byte((value shr (8*i)) and 255)

proc writeFixed[N: static[int]](output: var seq[byte], offset: int, value: array[N, byte]) =
  ## Copy only a fixed-size field into its premeasured output range.
  for i in 0..<N: output[offset+i] = value[i]

proc encodeAnnouncements*(records: openArray[AuditAnnouncement],
    limits: AuditLimits): AuditResult[seq[byte]] =
  ## Validate source claims and measure the whole CE144 batch before allocating output.
  if not valid(limits): return AuditResult[seq[byte]](status: AuditError.InvalidPolicy)
  if uint64(records.len) > uint64(limits.records):
    return AuditResult[seq[byte]](status: AuditError.LimitExceeded)
  var length = 0
  # Initial intent contains no declared cores; later intent contains exactly one E2 core.
  for record in records:
    if uint64(record.validator) >= uint64(limits.validators):
      return AuditResult[seq[byte]](status: AuditError.InvalidValidator)
    if record.intent == AuditIntent.Later and uint64(record.core) >= uint64(limits.cores):
      return AuditResult[seq[byte]](status: AuditError.InvalidCore)
    let width = if record.intent == AuditIntent.Initial: 131 else: 133
    if not charge(length, width, limits):
      return AuditResult[seq[byte]](status: AuditError.LimitExceeded)
  var output = newSeq[byte](length)
  var offset = 0
  # No outer count, tranche number, no-show list or second evidence message is serialized.
  for record in records:
    writeFixed(output, offset, array[32, byte](record.header))
    writeInteger(output, offset+32, uint32(record.validator), 2)
    output[offset+34] = byte(record.intent)
    var proofOffset = offset+35
    if record.intent == AuditIntent.Later:
      writeInteger(output, offset+35, uint32(record.core), 2)
      proofOffset += 2
    writeFixed(output, proofOffset, array[96, byte](record.proof))
    offset = proofOffset+96
  AuditResult[seq[byte]](status: AuditError.None, completed: output)

proc encodeJudgments*(records: openArray[AuditJudgment],
    limits: AuditLimits): AuditResult[seq[byte]] =
  ## Measure/validate every independent epoch/auditor/report record before producing a CE145 message.
  if not valid(limits): return AuditResult[seq[byte]](status: AuditError.InvalidPolicy)
  if uint64(records.len) > uint64(limits.records):
    return AuditResult[seq[byte]](status: AuditError.LimitExceeded)
  var length = 0
  # Positive judgments cannot smuggle a guarantee; invalid credentials follow GP canonical order.
  for record in records:
    if uint64(record.validator) >= uint64(limits.validators):
      return AuditResult[seq[byte]](status: AuditError.InvalidValidator)
    var width = 103
    if record.valid:
      if record.credentialCount != 0:
        return AuditResult[seq[byte]](status: AuditError.InvalidGuarantee)
    else:
      if record.credentialCount != 2 and record.credentialCount != 3:
        return AuditResult[seq[byte]](status: AuditError.InvalidGuarantee)
      width = 108 + record.credentialCount*66
      var previous = 0'u16
      # Check the complete credential domain before serializing its one-byte canonical count.
      for i in 0..<record.credentialCount:
        let index = uint16(record.credentials[i].validator)
        if uint64(index) >= uint64(limits.validators):
          return AuditResult[seq[byte]](status: AuditError.InvalidValidator)
        if i > 0 and index <= previous:
          return AuditResult[seq[byte]](status: AuditError.InvalidGuarantee)
        previous = index
    if not charge(length, width, limits):
      return AuditResult[seq[byte]](status: AuditError.LimitExceeded)
  var output = newSeq[byte](length)
  var offset = 0
  # Each invalid validity embeds the guarantee before the report hash and judgment signature.
  for record in records:
    writeInteger(output, offset, uint32(record.epoch), 4)
    writeInteger(output, offset+4, uint32(record.validator), 2)
    output[offset+6] = if record.valid: 1'u8 else: 0'u8
    var tail = offset+7
    if not record.valid:
      writeInteger(output, tail, uint32(record.slot), 4)
      output[tail+4] = byte(record.credentialCount)
      tail += 5
      # Previously validated counts and indices fit the measured fixed credential extents.
      for i in 0..<record.credentialCount:
        writeInteger(output, tail, uint32(record.credentials[i].validator), 2)
        writeFixed(output, tail+2, array[64, byte](record.credentials[i].signature))
        tail += 66
    writeFixed(output, tail, array[32, byte](record.report))
    writeFixed(output, tail+32, array[64, byte](record.signature))
    offset = tail+96
  AuditResult[seq[byte]](status: AuditError.None, completed: output)
