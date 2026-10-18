# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Owned snapshots over the pinned C.1.2/C.1.3/C.2 borrowed codecs. Input must be stable during
## a call; successful snapshots retain only the consumed prefix.
##
## Exposes OwnedFrame snapshots for bytes, optionals, work, preimages and digests, with bounded
## copy and re-encoding operations.

import ./[natural, bounded, composite, work_digest]

type
  # Each snapshot has exactly one validated schema, independent of later input mutations.
  OwnedKind* {.pure.} = enum
    Bytes, Optional, Work, Preimages, Digest
  # Wire failures retain their meaning; ownership operations add missing-owner/schema/index failures.
  OwnershipError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, OutputTooSmall,
    AliasedBuffers, LengthOverflow, InvalidTag, InvalidSpan, InvalidOwner,
    WrongSchema, InvalidIndex, AllocationFailure
  # Private, acyclic ARC storage; neither wire bytes nor borrowed descriptors leave this module.
  FrameData = ref object
    kind: OwnedKind
    wire: seq[byte]
    blob: BlobSpan
    hasBlob, present: bool
    workKind: WorkKind
    records: seq[Preimage]
    digest: WorkDigest
  # Copying this opaque value retains its immutable storage through ARC, including across scopes.
  OwnedFrame* = object
    data: nil FrameData
  # Private tagged outcomes expose copied data only after success; defaults are Uninitialized.
  OwnedResult*[T] = object
    case status: OwnershipError
    of None:
      # Payload may contain an opaque owner, never private backing bytes.
      completed: T
    else:
      # Failed/default alternatives contain only their reason.
      discard
  # Common scalar metadata; blobCount is the number of payloads available through copyOwnedBlob.
  OwnedInfo* = object
    kind*: OwnedKind
    consumed*, blobCount*: int
  # Optional metadata contains a length only when a payload exists, never a detached span.
  OwnedOptionalInfo* = object
    case isPresent: bool
    of true:
      # An empty present blob still has a length of zero and one copyable payload.
      payloadLength: int
    else:
      # Absence carries no payload metadata.
      discard
  # Work errors are valid decoded values; only success contains a payload length.
  OwnedWorkInfo* = object
    case outputKind: WorkKind
    of Success:
      # Payload bytes remain private to the owner.
      payloadLength: int
    else:
      # Work errors carry their protocol tag alone.
      discard
  # All digest fields are copied values, with a length-only work output rather than a borrowed descriptor.
  OwnedDigestInfo* = object
    service*: ServiceIndex
    codeHash*: CodeHash
    payloadHash*: PayloadHash
    accumulateGas*: Gas
    output*: OwnedWorkInfo
    refine*: RefineLoad

# Read an outcome without permitting callers to mutate its discriminator.
func error*[T](value: OwnedResult[T]): OwnershipError = value.status
# Return copied metadata or a retained opaque owner only after successful completion.
func value*[T](value: OwnedResult[T]): T {.inline, requires: value.status == OwnershipError.None.} =
  value.completed
# Sibling adapters may report failures, but cannot label missing data as None/success.
func ownedFailure*[T](reason: OwnershipError): OwnedResult[T] {.requires: reason !=
    OwnershipError.None.} =
  OwnedResult[T](status: reason)
# Sibling adapters explicitly report completed values; this builder alone does not validate an owner.
func ownedSuccess*[T](value: T): OwnedResult[T] = OwnedResult[T](status: OwnershipError.None,
    completed: value)

# Read optional metadata without allowing presence to be changed.
func present*(value: OwnedOptionalInfo): bool = value.isPresent
# Only present optional metadata has a length; bytes remain accessible solely through the owner.
func length*(value: OwnedOptionalInfo): int {.inline,
    requires: value.isPresent.} = value.payloadLength
# Read a copied work tag without exposing a writable discriminator.
func kind*(value: OwnedWorkInfo): WorkKind = value.outputKind
# Work errors have no payload length, independently of a successful outer metadata query.
func length*(value: OwnedWorkInfo): int {.inline, requires: value.outputKind == WorkKind.Success.} =
  value.payloadLength
# Sibling report adapters may construct successful length-only metadata after validating a snapshot.
func successfulOwnedWorkInfo*(length: int): OwnedWorkInfo {.requires: length >= 0.} =
  OwnedWorkInfo(outputKind: WorkKind.Success, payloadLength: length)
# Payload-free work metadata may not manufacture Success, which requires an explicit length.
func failedOwnedWorkInfo*(kind: WorkKind): OwnedWorkInfo {.requires: kind != WorkKind.Success.} =
  OwnedWorkInfo(outputKind: kind)

# Convert composite wire failures without conflating an uninitialized result with success.
proc ownershipError(error: CompositeError): OwnershipError =
  case error
  of None: OwnershipError.None # The complete frame validated.
  of Uninitialized: OwnershipError.Uninitialized # No validated result exists.
  of Truncated: OwnershipError.Truncated # A required field is missing.
  of NonCanonical: OwnershipError.NonCanonical # An overlong natural is invalid.
  of LimitExceeded: OwnershipError.LimitExceeded # Caller resource policy failed.
  of OutputTooSmall: OwnershipError.OutputTooSmall # Complete storage is required.
  of AliasedBuffers: OwnershipError.AliasedBuffers # Borrowed preflight rejected overlap.
  of LengthOverflow: OwnershipError.LengthOverflow # A host extent is unrepresentable.
  of InvalidTag: OwnershipError.InvalidTag # The schema discriminator is unsupported.
  of InvalidSpan: OwnershipError.InvalidSpan # A borrowed descriptor is invalid.

proc ownershipError(error: ContainerError): OwnershipError =
  case error
  of None: OwnershipError.None # Byte framing validated.
  of Uninitialized: OwnershipError.Uninitialized # No validated result exists.
  of Truncated: OwnershipError.Truncated # Prefix or payload is incomplete.
  of NonCanonical: OwnershipError.NonCanonical # The length is overlong.
  of LimitExceeded: OwnershipError.LimitExceeded # The blob exceeds its policy.
  else: OwnershipError.InvalidSpan # Reject impossible byte-decoder statuses explicitly.

# Validate a complete prefix before copying; record allocation is bounded by policy and wire extent.
proc capture(input: openArray[byte], kind: OwnedKind, limit: ByteLimit,
             limits: PreimageLimits): OwnedResult[OwnedFrame] =
  var data = FrameData(kind: kind)
  var consumed = 0
  # Select one exact schema; every branch validates before exposing or retaining payload bytes.
  case kind
  of Bytes:
    let parsed = decodeBytesBorrowed(input, limit)
    # No snapshot survives a malformed prefix or policy violation.
    if parsed.error != ContainerError.None: return OwnedResult[OwnedFrame](status: ownershipError(parsed.error))
    consumed = parsed.consumed
    data.blob = BlobSpan(offset: parsed.offset, length: parsed.length)
    data.hasBlob = true
  of Optional:
    let parsed = decodeOptionalBorrowed(input, limit)
    # A failed discriminator/payload cannot create an owner.
    if parsed.error != CompositeError.None: return OwnedResult[OwnedFrame](status: ownershipError(parsed.error))
    consumed = parsed.consumed
    data.present = parsed.value.present
    data.hasBlob = data.present
    # Only the present variant has a borrowed descriptor to bind to the snapshot.
    if data.present: data.blob = parsed.value.blob
  of Work:
    let parsed = decodeWorkBorrowed(input, limit)
    # Work-output errors are successful values; schema errors are failed decodes.
    if parsed.error != CompositeError.None: return OwnedResult[OwnedFrame](status: ownershipError(parsed.error))
    consumed = parsed.consumed
    data.workKind = parsed.value.kind
    data.hasBlob = data.workKind == WorkKind.Success
    # Payload-free work variants need no descriptor.
    if data.hasBlob: data.blob = parsed.value.blob
  of Preimages:
    let count = natural.decode(input)
    # Validate the count before narrowing or allocating record storage.
    if not count.ok:
      return OwnedResult[OwnedFrame](status: if count.error ==
          natural.truncated: OwnershipError.Truncated else: OwnershipError.NonCanonical)
    let claimed = uint64(count.value)
    # Check policy before the minimum-wire proof, matching the borrowed decoder's precedence.
    if claimed > uint64(limits.items): return OwnedResult[OwnedFrame](
        status: OwnershipError.LimitExceeded)
    # Each record requires four service bytes and at least one length byte.
    if claimed > uint64((input.len - count.consumed) div 5): return OwnedResult[OwnedFrame](
        status: OwnershipError.Truncated)
    # Typed allocation size must fit host arithmetic even when the count fits an int.
    if claimed > uint64(high(int) div sizeof(Preimage)): return OwnedResult[OwnedFrame](
        status: OwnershipError.LengthOverflow)
    data.records = newSeq[Preimage](int(claimed))
    let parsed = decodePreimagesBorrowed(input, limits, data.records)
    # ARC discards private temporary records if any later field is invalid.
    if parsed.error != CompositeError.None: return OwnedResult[OwnedFrame](status: ownershipError(parsed.error))
    consumed = parsed.consumed
  of Digest:
    let parsed = decodeDigestBorrowed(input, limit)
    # The final metric must validate before retaining the complete digest.
    if parsed.error != CompositeError.None: return OwnedResult[OwnedFrame](status: ownershipError(parsed.error))
    consumed = parsed.consumed
    data.digest = parsed.value
    data.workKind = parsed.value.output.kind
    data.hasBlob = data.workKind == WorkKind.Success
    # Successful digest spans already use full-frame coordinates.
    if data.hasBlob: data.blob = parsed.value.output.blob
  data.wire = newSeq[byte](consumed)
  # Deep-copy only the validated prefix; trailing frames cannot inflate retained storage.
  if consumed > 0:
    # Fresh private byte storage cannot overlap caller input; the decoder proved the complete prefix exists.
    copyMem(addr data.wire[0], unsafeAddr input[0], consumed)
  OwnedResult[OwnedFrame](status: OwnershipError.None, completed: OwnedFrame(data: data))

# Own one C.1.2 variable byte string; caller input may be released or mutated after return.
proc decodeOwnedBytes*(input: openArray[byte], limit: ByteLimit): OwnedResult[OwnedFrame] =
  capture(input, OwnedKind.Bytes, limit, PreimageLimits())

# Own a C.1.3 optional blob, including a payload-free absent value.
proc decodeOwnedOptional*(input: openArray[byte], limit: ByteLimit): OwnedResult[OwnedFrame] =
  capture(input, OwnedKind.Optional, limit, PreimageLimits())

# Own a C.2 work output; work-error tags remain successful decoded values.
proc decodeOwnedWork*(input: openArray[byte], limit: ByteLimit): OwnedResult[OwnedFrame] =
  capture(input, OwnedKind.Work, limit, PreimageLimits())

# Own the complete preimage extrinsic and all nested payloads, with policy-bounded private records.
proc decodeOwnedPreimages*(input: openArray[byte], limits: PreimageLimits): OwnedResult[OwnedFrame] =
  capture(input, OwnedKind.Preimages, ByteLimit(0), limits)

# Own a complete C.2 digest, copying fixed fields and retaining successful payload bytes.
proc decodeOwnedDigest*(input: openArray[byte], limit: ByteLimit): OwnedResult[OwnedFrame] =
  capture(input, OwnedKind.Digest, limit, PreimageLimits())

# Report schema, consumed prefix and available payload count without exposing source coordinates.
proc ownedInfo*(frame: OwnedFrame): OwnedResult[OwnedInfo] =
  # A default handle contains no validated storage.
  # Retain one stable reference before the nil check so later reads share its proven lifetime.
  let data = frame.data
  if data == nil: return OwnedResult[OwnedInfo](status: OwnershipError.InvalidOwner)
  let count = if data.kind == OwnedKind.Preimages: data.records.len else: int(data.hasBlob)
  OwnedResult[OwnedInfo](status: OwnershipError.None,
      completed: OwnedInfo(kind: data.kind, consumed: data.wire.len, blobCount: count))

# Obtain optional metadata only from the optional schema; no raw span or mutable slice escapes.
proc ownedOptionalInfo*(frame: OwnedFrame): OwnedResult[OwnedOptionalInfo] =
  # Missing owners and wrong schemas are ordinary typed API errors.
  # Retain one stable reference before the nil check so later reads share its proven lifetime.
  let data = frame.data
  if data == nil: return OwnedResult[OwnedOptionalInfo](status: OwnershipError.InvalidOwner)
  if data.kind != OwnedKind.Optional: return OwnedResult[OwnedOptionalInfo](
      status: OwnershipError.WrongSchema)
  # Absence has no length field; an empty present blob remains distinguishable.
  if not data.present: return OwnedResult[OwnedOptionalInfo](status: OwnershipError.None,
      completed: OwnedOptionalInfo(isPresent: false))
  OwnedResult[OwnedOptionalInfo](status: OwnershipError.None,
      completed: OwnedOptionalInfo(isPresent: true, payloadLength: data.blob.length))

# Translate private work metadata to a value without a source-buffer descriptor.
proc workInfo(data: FrameData): OwnedWorkInfo =
  # Only successful work output contains a payload length.
  if data.workKind == WorkKind.Success: return OwnedWorkInfo(outputKind: WorkKind.Success,
      payloadLength: data.blob.length)
  OwnedWorkInfo(outputKind: data.workKind)

# Read a work schema's tag and successful payload length as copied scalar metadata.
proc ownedWorkInfo*(frame: OwnedFrame): OwnedResult[OwnedWorkInfo] =
  # Reject default owners and schema mismatches before accessing private fields.
  # Retain one stable reference before the nil check so later reads share its proven lifetime.
  let data = frame.data
  if data == nil: return OwnedResult[OwnedWorkInfo](status: OwnershipError.InvalidOwner)
  if data.kind != OwnedKind.Work: return OwnedResult[OwnedWorkInfo](
      status: OwnershipError.WrongSchema)
  OwnedResult[OwnedWorkInfo](status: OwnershipError.None, completed: workInfo(data))

# Copy all fixed digest fields and tag/length metadata; payload access stays bound to the frame owner.
proc ownedDigestInfo*(frame: OwnedFrame): OwnedResult[OwnedDigestInfo] =
  # A missing or differently typed frame cannot yield a default digest.
  # Retain one stable reference before the nil check so later reads share its proven lifetime.
  let data = frame.data
  if data == nil: return OwnedResult[OwnedDigestInfo](status: OwnershipError.InvalidOwner)
  if data.kind != OwnedKind.Digest: return OwnedResult[OwnedDigestInfo](
      status: OwnershipError.WrongSchema)
  let value = data.digest
  OwnedResult[OwnedDigestInfo](status: OwnershipError.None, completed: OwnedDigestInfo(
      service: value.service, codeHash: value.codeHash, payloadHash: value.payloadHash,
      accumulateGas: value.accumulateGas, output: workInfo(data), refine: value.refine))

# Select a preimage's nominal service ID without returning its borrowed payload descriptor.
proc ownedService*(frame: OwnedFrame, index: int): OwnedResult[ServiceIndex] =
  # Schema and index checks precede any private-record access.
  # Retain one stable reference before the nil check so later reads share its proven lifetime.
  let data = frame.data
  if data == nil: return OwnedResult[ServiceIndex](status: OwnershipError.InvalidOwner)
  if data.kind != OwnedKind.Preimages: return OwnedResult[ServiceIndex](
      status: OwnershipError.WrongSchema)
  if index < 0 or index >= data.records.len: return OwnedResult[ServiceIndex](
      status: OwnershipError.InvalidIndex)
  OwnedResult[ServiceIndex](status: OwnershipError.None, completed: data.records[index].service)

# Query one owner's payload length before allocating caller-owned copy storage; indices never escape as spans.
proc ownedBlobLength*(frame: OwnedFrame, index: int): OwnedResult[int] =
  # Default owners and payload-free values cannot expose a fabricated zero length.
  # Retain one stable reference before the nil check so later reads share its proven lifetime.
  let data = frame.data
  if data == nil: return OwnedResult[int](status: OwnershipError.InvalidOwner)
  let count = if data.kind == OwnedKind.Preimages: data.records.len else: int(data.hasBlob)
  # An empty present blob is valid, while an absent or out-of-range blob is an error.
  if index < 0 or index >= count: return OwnedResult[int](status: OwnershipError.InvalidIndex)
  let span = if data.kind == OwnedKind.Preimages: data.records[index].blob else: data.blob
  OwnedResult[int](status: OwnershipError.None, completed: span.length)

# Copy bytes into caller storage atomically; no mutable alias to the snapshot is ever returned.
proc copyOwnedBlob*(frame: OwnedFrame, index: int, output: var openArray[byte]): OwnedResult[int] =
  # A default owner has neither a schema nor payloads.
  # Retain one stable reference before the nil check so later reads share its proven lifetime.
  let data = frame.data
  if data == nil: return OwnedResult[int](status: OwnershipError.InvalidOwner)
  let count = if data.kind == OwnedKind.Preimages: data.records.len else: int(data.hasBlob)
  # Payload-free values and out-of-range indices cannot manufacture an empty blob.
  if index < 0 or index >= count: return OwnedResult[int](status: OwnershipError.InvalidIndex)
  let span = if data.kind == OwnedKind.Preimages: data.records[index].blob else: data.blob
  # Require the whole payload before writing any destination byte.
  if output.len < span.length: return OwnedResult[int](status: OwnershipError.OutputTooSmall)
  # Bounds were validated against the stable copied prefix; caller supplies no second source buffer.
  if span.length > 0:
    # Safe callers cannot access private snapshot bytes; source coordinates and output capacity are proved.
    copyMem(addr output[0], unsafeAddr data.wire[span.offset], span.length)
  OwnedResult[int](status: OwnershipError.None, completed: span.length)

# Emit the validated canonical frame from its private snapshot, preserving output on insufficient capacity.
proc encodeOwned*(frame: OwnedFrame, output: var openArray[byte]): OwnedResult[int] =
  # Uninitialized owners must not serialize default data.
  # Retain one stable reference before the nil check so later reads share its proven lifetime.
  let data = frame.data
  if data == nil: return OwnedResult[int](status: OwnershipError.InvalidOwner)
  # All required bytes must fit before the first write.
  if output.len < data.wire.len: return OwnedResult[int](status: OwnershipError.OutputTooSmall)
  # The internal bytes are inaccessible to safe callers, so output cannot alias the snapshot.
  if data.wire.len > 0:
    # Nonempty private byte storage and a complete destination permit an allocation-free standard copy.
    copyMem(addr output[0], unsafeAddr data.wire[0], data.wire.len)
  OwnedResult[int](status: OwnershipError.None, completed: data.wire.len)
