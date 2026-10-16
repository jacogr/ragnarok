## GP 0.8.0 C.2 complete extrinsic/block composition over immutable schema-bound components.
import ./[bounded, composite, owned, tickets, assurances, guarantees, disputes, header]

type
  # Static component identities prevent swapping equal-width/wire-compatible child schemas.
  ComponentKind* {.pure.} = enum
    Header, Tickets, Preimages, Guarantees, Assurances, Disputes
  # Nested failures retain the existing child's typed reason, not a parsed message or partial value.
  ComponentFailure* = object
    case kind*: ComponentKind
    of ComponentKind.Header:
      headerError*: HeaderError       # Only this selected component's failure reason exists.
    of ComponentKind.Tickets:
      ticketError*: TicketError       # Only this selected component's failure reason exists.
    of ComponentKind.Preimages:
      preimageError*: CompositeError  # Only this selected component's failure reason exists.
    of ComponentKind.Guarantees:
      guaranteeError*: GuaranteeError # Only this selected component's failure reason exists.
    of ComponentKind.Assurances:
      assuranceError*: AssuranceError # Only this selected component's failure reason exists.
    of ComponentKind.Disputes:
      disputeError*: DisputeError     # Only this selected component's failure reason exists.
                                    # Parent failures carry no value/progress; InvalidComponent adds only its checked nested reason.
  FrameError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidOwner, LimitExceeded,
    OutputTooSmall, AliasedBuffers, LengthOverflow, InvalidComponent
  # Only success contains data; structured child failures remain failure-only tagged alternatives.
  FrameResult*[T] = object
    case error*: FrameError
    of FrameError.None:
      value*: T                # Complete application values exist exclusively after success selection.
    of FrameError.InvalidComponent:
      cause*: ComponentFailure # No failed child publishes a default owner or consumed offset.
    else:
      discard                  # Default/parent failures contain only their reason.
                # Chain/resource domains are explicit; validator count is a structural ceiling, not state membership proof.
  FrameConfig* = object
    cores*: CoreCount
    validators*: ValidatorCount
    epochSlots*: EpochSlots
    ticketLimit*: TicketLimit
    preimages*: PreimageLimits
    maxBytes*: ByteLimit
  # Copied schema metadata reports complete prefix extent and total logical records, without coordinates.
  ComponentInfo* = object
    records*, consumed*: int
  # The private snapshot binds exact child bytes to the configuration under which they were captured.
  ComponentData = ref object
    wire: seq[byte]
    config: FrameConfig
    info: ComponentInfo
  # Copying a statically schema-bound handle retains an immutable child, never a mutable backing sequence.
  Component*[kind: static ComponentKind] = object
    data: ComponentData
  # Header components require complete sealed headers; unsigned snapshots have a different API/type.
  HeaderComponent* = Component[ComponentKind.Header]
  # Each complete extrinsic family has a separate nominal component type.
  TicketComponent* = Component[ComponentKind.Tickets]
  # A byte/work/optional frame cannot stand in for a validated preimage component.
  PreimageComponent* = Component[ComponentKind.Preimages]
  # Complete guarantee components include every nested report, slot and credential.
  GuaranteeComponent* = Component[ComponentKind.Guarantees]
  # Assurance components retain the exact profile bitfield width and canonical validator order.
  AssuranceComponent* = Component[ComponentKind.Assurances]
  # Dispute components contain all three complete verdict/culprit/fault sequences.
  DisputeComponent* = Component[ComponentKind.Disputes]
  # Successful component decoding binds its matching owner to exact prefix progress.
  ComponentRead*[kind: static ComponentKind] = object
    owner*: Component[kind]
    consumed*: int
  # Stable borrowed source descriptors contain only immutable schema-bound children, in normative wire order.
  Extrinsic* {.byref.} = object
    tickets*: TicketComponent
    preimages*: PreimageComponent
    guarantees*: GuaranteeComponent
    assurances*: AssuranceComponent
    disputes*: DisputeComponent
  # Parent metadata exposes cardinalities and complete extent, never detached component spans.
  ExtrinsicInfo* = object
    tickets*, preimages*, guarantees*, assurances*, disputes*, consumed*: int
  # Private scan positions are retained only until complete parent validation authorizes capture.
  ExtrinsicLayout = object
    offsets, lengths: array[5, int]
    info: ExtrinsicInfo
  # Immutable acyclic parent retains child components without another duplicate whole-extrinsic byte buffer.
  ExtrinsicData = ref object
    source: Extrinsic
    config: FrameConfig
    info: ExtrinsicInfo
  # A default handle differs from a captured seven-byte empty extrinsic.
  OwnedExtrinsic* = object
    data: ExtrinsicData
  # Successful full extrinsic decoding returns only complete ownership/progress.
  ExtrinsicRead* = object
    owner*: OwnedExtrinsic
    consumed*: int
  # A block source borrows immutable sealed-header and complete-extrinsic handles for one encode call.
  Block* {.byref.} = object
    header*: HeaderComponent
    extrinsic*: OwnedExtrinsic
  # Block metadata copies both child extents and exact total consumption without granting arbitrary extraction.
  BlockInfo* = object
    headerBytes*, extrinsicBytes*, consumed*: int
  # Private acyclic block storage retains its immutable children and captured configuration.
  BlockData = ref object
    source: Block
    config: FrameConfig
    info: BlockInfo
  # Child getters retain their own immutable storage after the final block handle is released.
  OwnedBlock* = object
    data: BlockData
  # Successful block decoding binds both complete child captures to exact prefix consumption.
  BlockRead* = object
    owner*: OwnedBlock
    consumed*: int

# Construct the full chain domains; preimage and whole-frame limits remain explicit caller resource policy.
proc fullFrameConfig*(maxBytes: ByteLimit, preimages: PreimageLimits): FrameConfig {.raises: [].} =
  FrameConfig(cores: CoreCount(341), validators: ValidatorCount(1023), epochSlots: EpochSlots(600),
    ticketLimit: TicketLimit(16), preimages: preimages, maxBytes: maxBytes)

# Validate shared domains before any count, source owner or attacker-controlled byte is inspected.
proc validConfig(config: FrameConfig): bool {.raises: [].} =
  assurances.validConfig(AssuranceConfig(cores: config.cores, validators: config.validators)) and
    uint64(config.epochSlots) > 0 and uint64(config.ticketLimit) <= 16

# Preserve a child's strongly typed failure without publishing partial parent data/progress.
proc failed[T](cause: ComponentFailure): FrameResult[T] {.raises: [].} =
  FrameResult[T](error: FrameError.InvalidComponent, cause: cause)

# Select the shared header domains without inferring pending/current validator membership from bytes.
proc headerConfig(config: FrameConfig): HeaderConfig {.raises: [].} =
  HeaderConfig(cores: config.cores, authorValidators: config.validators,
    epochSlots: config.epochSlots, maxBytes: config.maxBytes)

# Inspect exactly one child prefix using the existing authoritative family validator, without allocation.
proc inspect[kind: static ComponentKind](input: openArray[byte], config: FrameConfig): FrameResult[
    ComponentInfo] =
  # Invalid parent configuration precedes component-specific framing or source-policy decisions.
  if not validConfig(config): return FrameResult[ComponentInfo](error: FrameError.InvalidConfig)
  var info: ComponentInfo
  when kind == ComponentKind.Header:
    # This static alternative delegates all header framing and structural policy to its existing codec.
    let parsed = inspectHeader(input, headerConfig(config))
    # A child failure must remain attributed to its schema, with no partial parent value.
    if parsed.error != HeaderError.None:
      return failed[ComponentInfo](ComponentFailure(kind: kind, headerError: parsed.error))
    info = ComponentInfo(records: 1, consumed: parsed.value.consumed)
  elif kind == ComponentKind.Tickets:
    # This static alternative delegates all tickets framing and structural policy to its existing codec.
    let parsed = inspectTickets(input, config.ticketLimit)
    # A child failure must remain attributed to its schema, with no partial parent value.
    if parsed.error != TicketError.None:
      return failed[ComponentInfo](ComponentFailure(kind: kind, ticketError: parsed.error))
    info = ComponentInfo(records: parsed.count, consumed: parsed.consumed)
  elif kind == ComponentKind.Preimages:
    # This static alternative delegates all preimages framing and structural policy to its existing codec.
    let parsed = inspectPreimages(input, config.preimages, config.maxBytes)
    # A child failure must remain attributed to its schema, with no partial parent value.
    if parsed.error != CompositeError.None:
      return failed[ComponentInfo](ComponentFailure(kind: kind, preimageError: parsed.error))
    info = ComponentInfo(records: parsed.count, consumed: parsed.consumed)
  elif kind == ComponentKind.Guarantees:
    # This static alternative delegates all guarantees framing and structural policy to its existing codec.
    let parsed = inspectGuarantees(input, GuaranteeConfig(cores: config.cores,
        validators: config.validators, maxBytes: config.maxBytes))
    # A child failure must remain attributed to its schema, with no partial parent value.
    if parsed.error != GuaranteeError.None:
      return failed[ComponentInfo](ComponentFailure(kind: kind, guaranteeError: parsed.error))
    info = ComponentInfo(records: parsed.value.count, consumed: parsed.value.consumed)
  elif kind == ComponentKind.Assurances:
    # This static alternative delegates all assurances framing and structural policy to its existing codec.
    let parsed = inspectAssurances(input, AssuranceConfig(cores: config.cores,
        validators: config.validators))
    # A child failure must remain attributed to its schema, with no partial parent value.
    if parsed.error != AssuranceError.None:
      return failed[ComponentInfo](ComponentFailure(kind: kind, assuranceError: parsed.error))
    info = ComponentInfo(records: parsed.count, consumed: parsed.consumed)
  elif kind == ComponentKind.Disputes:
    # This static alternative delegates all disputes framing and structural policy to its existing codec.
    let parsed = inspectDisputes(input, DisputeConfig(validators: config.validators,
        maxBytes: config.maxBytes))
    # A child failure must remain attributed to its schema, with no partial parent value.
    if parsed.error != DisputeError.None:
      return failed[ComponentInfo](ComponentFailure(kind: kind, disputeError: parsed.error))
    info = ComponentInfo(records: parsed.value.verdicts+parsed.value.culprits+parsed.value.faults,
        consumed: parsed.value.consumed)
  # Count/payload rules can succeed while the complete serialized child exceeds the remaining parent budget.
  if uint64(info.consumed) > uint64(config.maxBytes):
    return FrameResult[ComponentInfo](error: FrameError.LimitExceeded)
  FrameResult[ComponentInfo](error: FrameError.None, value: info)

# Capture exact validated bytes only after the caller's whole parent scan has passed.
proc capture[kind: static ComponentKind](input: openArray[byte], config: FrameConfig,
    info: ComponentInfo): Component[kind] =
  let data = ComponentData(wire: newSeq[byte](info.consumed), config: config, info: info)
  # Snapshots exclude trailing input and retain no caller pointer or detached coordinate.
  for i in 0..<data.wire.len: data.wire[i] = input[i]
  Component[kind](data: data)

# Decode/capture one statically typed standalone component, leaving unrelated suffixes to the caller.
proc decodeComponent*[kind: static ComponentKind](input: openArray[byte],
    config: FrameConfig): FrameResult[ComponentRead[kind]] =
  let checked = inspect[kind](input, config)
  # No input-derived allocation occurs before complete child validation and byte-budget checks.
  if checked.error == FrameError.InvalidComponent: return failed[ComponentRead[kind]](checked.cause)
  # Stop before reading success-only metadata or capturing/writing any child bytes.
  if checked.error != FrameError.None: return FrameResult[ComponentRead[kind]](error: checked.error)
  FrameResult[ComponentRead[kind]](error: FrameError.None, value: ComponentRead[kind](
    owner: capture[kind](input, config, checked.value), consumed: checked.value.consumed))

# Copy component cardinality/extent metadata without revealing its private byte storage or configuration coordinates.
proc componentInfo*[kind: static ComponentKind](owner: Component[kind]): FrameResult[
    ComponentInfo] =
  # Default handles cannot fabricate a validated empty component of any schema.
  if owner.data.isNil: return FrameResult[ComponentInfo](error: FrameError.InvalidOwner)
  FrameResult[ComponentInfo](error: FrameError.None, value: owner.data.info)

# Compare address distances without overflowing endpoint arithmetic; empty output needs no element address.
proc overlaps(a: pointer, an: int, b: pointer, bn: int): bool =
  if an == 0 or bn == 0: return false # Empty ranges cannot share any written bytes.
  let left = cast[uint](a)
  let right = cast[uint](b)
  if left <= right: right-left < uint(an) # Lower source address selects its extent.
  else: left-right < uint(bn) # Lower destination address selects the written prefix extent.

# Reject overlap with any byte of an immutable component before an enclosing operation's first write.
proc aliases[kind: static ComponentKind](owner: Component[kind], output: var openArray[byte],
    size: int): bool =
  overlaps(unsafeAddr owner.data.wire[0], owner.data.wire.len, addr output[0], size)

# Commit a previously validated private component interval; parent capacity/aliases are already proved.
proc put[kind: static ComponentKind](owner: Component[kind], output: var openArray[byte],
    cursor: var int) =
  # Exact immutable child bytes preserve existing C.2 framing without another protocol encoder implementation.
  for value in owner.data.wire:
    output[cursor] = value
    inc cursor

# Re-emit an immutable component atomically, preserving all unused destination suffix capacity.
proc encodeComponent*[kind: static ComponentKind](owner: Component[kind], output: var openArray[
    byte]): FrameResult[int] =
  if owner.data.isNil: return FrameResult[int](error: FrameError.InvalidOwner) # Defaults contain no validated schema bytes.
  let size = owner.data.info.consumed
  if output.len < size: return FrameResult[int](error: FrameError.OutputTooSmall) # Complete child capacity precedes any write.
  if aliases(owner, output, size): return FrameResult[int](
      error: FrameError.AliasedBuffers) # Private retained bytes remain immutable.
  var cursor = 0
  put(owner, output, cursor)
  FrameResult[int](error: FrameError.None, value: size)

# Advance a complete child extent only after input presence/host arithmetic and parent resource bounds are proved.
proc advance(cursor: var int, length: int, config: FrameConfig): FrameError =
  if length > high(int)-cursor: return FrameError.LengthOverflow # Source composition must never wrap a host byte extent.
  cursor += length
  if uint64(cursor) > uint64(config.maxBytes): return FrameError.LimitExceeded # Whole-parent budget includes every prefix/count.
  FrameError.None

# Scan all five extrinsic families before allocating a single retained component or copied typed record.
proc scanExtrinsic(input: openArray[byte], config: FrameConfig): FrameResult[ExtrinsicLayout] =
  if not validConfig(config): return FrameResult[ExtrinsicLayout](
      error: FrameError.InvalidConfig) # Configuration precedes even empty frames.
  var layout: ExtrinsicLayout
  var cursor = 0
  # Inspect tickets against the remaining whole-extrinsic budget without exposing private coordinates.
  block:
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Tickets](input.toOpenArray(cursor, input.high), remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicLayout](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicLayout](error: parsed.error)
    layout.offsets[0] = cursor
    layout.lengths[0] = parsed.value.consumed
    layout.info.tickets = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    if error != FrameError.None: return FrameResult[ExtrinsicLayout](error: error)
  # Inspect preimages against the remaining whole-extrinsic budget without exposing private coordinates.
  block:
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Preimages](input.toOpenArray(cursor, input.high), remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicLayout](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicLayout](error: parsed.error)
    layout.offsets[1] = cursor
    layout.lengths[1] = parsed.value.consumed
    layout.info.preimages = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    if error != FrameError.None: return FrameResult[ExtrinsicLayout](error: error)
  # Inspect guarantees against the remaining whole-extrinsic budget without exposing private coordinates.
  block:
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Guarantees](input.toOpenArray(cursor, input.high), remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicLayout](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicLayout](error: parsed.error)
    layout.offsets[2] = cursor
    layout.lengths[2] = parsed.value.consumed
    layout.info.guarantees = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    if error != FrameError.None: return FrameResult[ExtrinsicLayout](error: error)
  # Inspect assurances against the remaining whole-extrinsic budget without exposing private coordinates.
  block:
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Assurances](input.toOpenArray(cursor, input.high), remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicLayout](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicLayout](error: parsed.error)
    layout.offsets[3] = cursor
    layout.lengths[3] = parsed.value.consumed
    layout.info.assurances = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    if error != FrameError.None: return FrameResult[ExtrinsicLayout](error: error)
  # Inspect disputes against the remaining whole-extrinsic budget without exposing private coordinates.
  block:
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Disputes](input.toOpenArray(cursor, input.high), remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicLayout](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicLayout](error: parsed.error)
    layout.offsets[4] = cursor
    layout.lengths[4] = parsed.value.consumed
    layout.info.disputes = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    # Reject host extent or serialized-budget growth before continuing to another child.
    if error != FrameError.None: return FrameResult[ExtrinsicLayout](error: error)
  layout.info.consumed = cursor
  FrameResult[ExtrinsicLayout](error: FrameError.None, value: layout)

# Capture all child slices after complete stable-input preflight; no child owner can escape a late failure.
proc captureExtrinsic(input: openArray[byte], config: FrameConfig,
    layout: ExtrinsicLayout): OwnedExtrinsic =
  var source: Extrinsic
  source.tickets = capture[ComponentKind.Tickets](input.toOpenArray(layout.offsets[0],
    layout.offsets[0]+layout.lengths[0]-1), config,
    ComponentInfo(records: layout.info.tickets, consumed: layout.lengths[0]))
  source.preimages = capture[ComponentKind.Preimages](input.toOpenArray(layout.offsets[1],
    layout.offsets[1]+layout.lengths[1]-1), config,
    ComponentInfo(records: layout.info.preimages, consumed: layout.lengths[1]))
  source.guarantees = capture[ComponentKind.Guarantees](input.toOpenArray(layout.offsets[2],
    layout.offsets[2]+layout.lengths[2]-1), config,
    ComponentInfo(records: layout.info.guarantees, consumed: layout.lengths[2]))
  source.assurances = capture[ComponentKind.Assurances](input.toOpenArray(layout.offsets[3],
    layout.offsets[3]+layout.lengths[3]-1), config,
    ComponentInfo(records: layout.info.assurances, consumed: layout.lengths[3]))
  source.disputes = capture[ComponentKind.Disputes](input.toOpenArray(layout.offsets[4],
    layout.offsets[4]+layout.lengths[4]-1), config,
    ComponentInfo(records: layout.info.disputes, consumed: layout.lengths[4]))
  OwnedExtrinsic(data: ExtrinsicData(source: source, config: config, info: layout.info))

# Decode one complete extrinsic prefix with child owners captured only after every family validates.
proc decodeExtrinsic*(input: openArray[byte], config: FrameConfig): FrameResult[ExtrinsicRead] =
  let scanned = scanExtrinsic(input, config)
  if scanned.error == FrameError.InvalidComponent: return failed[ExtrinsicRead](
      scanned.cause) # Preserve the failing family's reason.
  if scanned.error != FrameError.None: return FrameResult[ExtrinsicRead](
      error: scanned.error) # No default/partial owner on failure.
  FrameResult[ExtrinsicRead](error: FrameError.None, value: ExtrinsicRead(
    owner: captureExtrinsic(input, config, scanned.value), consumed: scanned.value.info.consumed))

# Revalidate every immutable source under the newly supplied parent policy before output capacity or writes.
proc measure(source: Extrinsic, config: FrameConfig): FrameResult[ExtrinsicInfo] =
  if not validConfig(config): return FrameResult[ExtrinsicInfo](
      error: FrameError.InvalidConfig) # Defaults cannot authorize owner traversal.
  var info: ExtrinsicInfo
  var cursor = 0
  # A component captured under broader/different profile parameters must still satisfy this parent's policy.
  block:
    # An uninitialized source handle cannot supply a complete validated child.
    if source.tickets.data.isNil: return FrameResult[ExtrinsicInfo](error: FrameError.InvalidOwner)
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Tickets](source.tickets.data.wire, remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicInfo](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicInfo](error: parsed.error)
    if parsed.value.consumed != source.tickets.data.wire.len:
      return FrameResult[ExtrinsicInfo](error: FrameError.InvalidConfig) # A profile change must not reinterpret an owned child as a shorter prefix.
    info.tickets = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    if error != FrameError.None: return FrameResult[ExtrinsicInfo](error: error)
  # A component captured under broader/different profile parameters must still satisfy this parent's policy.
  block:
    # An uninitialized source handle cannot supply a complete validated child.
    if source.preimages.data.isNil: return FrameResult[ExtrinsicInfo](
        error: FrameError.InvalidOwner)
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Preimages](source.preimages.data.wire, remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicInfo](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicInfo](error: parsed.error)
    if parsed.value.consumed != source.preimages.data.wire.len:
      return FrameResult[ExtrinsicInfo](error: FrameError.InvalidConfig) # A profile change must not reinterpret an owned child as a shorter prefix.
    info.preimages = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    if error != FrameError.None: return FrameResult[ExtrinsicInfo](error: error)
  # A component captured under broader/different profile parameters must still satisfy this parent's policy.
  block:
    # An uninitialized source handle cannot supply a complete validated child.
    if source.guarantees.data.isNil: return FrameResult[ExtrinsicInfo](
        error: FrameError.InvalidOwner)
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Guarantees](source.guarantees.data.wire, remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicInfo](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicInfo](error: parsed.error)
    if parsed.value.consumed != source.guarantees.data.wire.len:
      return FrameResult[ExtrinsicInfo](error: FrameError.InvalidConfig) # A profile change must not reinterpret an owned child as a shorter prefix.
    info.guarantees = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    if error != FrameError.None: return FrameResult[ExtrinsicInfo](error: error)
  # A component captured under broader/different profile parameters must still satisfy this parent's policy.
  block:
    # An uninitialized source handle cannot supply a complete validated child.
    if source.assurances.data.isNil: return FrameResult[ExtrinsicInfo](
        error: FrameError.InvalidOwner)
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Assurances](source.assurances.data.wire, remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicInfo](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicInfo](error: parsed.error)
    if parsed.value.consumed != source.assurances.data.wire.len:
      return FrameResult[ExtrinsicInfo](error: FrameError.InvalidConfig) # A profile change must not reinterpret an owned child as a shorter prefix.
    info.assurances = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    if error != FrameError.None: return FrameResult[ExtrinsicInfo](error: error)
  # A component captured under broader/different profile parameters must still satisfy this parent's policy.
  block:
    # An uninitialized source handle cannot supply a complete validated child.
    if source.disputes.data.isNil: return FrameResult[ExtrinsicInfo](error: FrameError.InvalidOwner)
    var remaining = config
    remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(cursor))
    let parsed = inspect[ComponentKind.Disputes](source.disputes.data.wire, remaining)
    # Keep the selected child reason; failed inspection cannot authorize any parent progress.
    if parsed.error == FrameError.InvalidComponent: return failed[ExtrinsicInfo](parsed.cause)
    # Stop before reading success-only metadata or capturing/writing any child bytes.
    if parsed.error != FrameError.None: return FrameResult[ExtrinsicInfo](error: parsed.error)
    if parsed.value.consumed != source.disputes.data.wire.len:
      return FrameResult[ExtrinsicInfo](error: FrameError.InvalidConfig) # A profile change must not reinterpret an owned child as a shorter prefix.
    info.disputes = parsed.value.records
    let error = advance(cursor, parsed.value.consumed, config)
    # Reject host extent or serialized-budget growth before continuing to another child.
    if error != FrameError.None: return FrameResult[ExtrinsicInfo](error: error)
  info.consumed = cursor
  FrameResult[ExtrinsicInfo](error: FrameError.None, value: info)

# Retain already validated immutable source components without a parent encode/decode round trip.
proc ownExtrinsic*(source: Extrinsic, config: FrameConfig): FrameResult[OwnedExtrinsic] =
  let checked = measure(source, config)
  # A source captured under another profile must satisfy this complete parent policy before ownership is granted.
  if checked.error == FrameError.InvalidComponent: return failed[OwnedExtrinsic](checked.cause)
  # Stop before reading success-only metadata or capturing/writing any child bytes.
  if checked.error != FrameError.None: return FrameResult[OwnedExtrinsic](error: checked.error)
  FrameResult[OwnedExtrinsic](error: FrameError.None,
    value: OwnedExtrinsic(data: ExtrinsicData(source: source, config: config, info: checked.value)))

# Check descriptors and every child's whole immutable wire against the whole written destination.
proc extrinsicAlias(source: Extrinsic, output: var openArray[byte], size: int): bool =
  if overlaps(unsafeAddr source, sizeof(source), addr output[0],
      size): return true # Borrowed handle descriptors must remain valid.
  if aliases(source.tickets, output, size): return true # Protect all tickets bytes, including later source intervals.
  if aliases(source.preimages, output, size): return true # Protect all preimages bytes, including later source intervals.
  if aliases(source.guarantees, output, size): return true # Protect all guarantees bytes, including later source intervals.
  if aliases(source.assurances, output, size): return true # Protect all assurances bytes, including later source intervals.
  if aliases(source.disputes, output, size): return true # Protect all disputes bytes, including later source intervals.
  false

# Commit exactly the five immutable children in the normative extrinsic order after full parent preflight.
proc putExtrinsic(source: Extrinsic, output: var openArray[byte], cursor: var int) =
  put(source.tickets, output, cursor)
  put(source.preimages, output, cursor)
  put(source.guarantees, output, cursor)
  put(source.assurances, output, cursor)
  put(source.disputes, output, cursor)

# Encode a complete extrinsic atomically without a temporary whole-frame staging allocation.
proc encodeExtrinsic*(source: Extrinsic, config: FrameConfig, output: var openArray[
    byte]): FrameResult[int] =
  let measured = measure(source, config)
  if measured.error == FrameError.InvalidComponent: return failed[int](
      measured.cause) # Late nested policy failures precede output sizing.
  if measured.error != FrameError.None: return FrameResult[int](
      error: measured.error) # No partial prefix can be emitted.
  let size = measured.value.consumed
  if output.len < size: return FrameResult[int](error: FrameError.OutputTooSmall) # Complete output before any address access.
  if extrinsicAlias(source, output, size): return FrameResult[int](
      error: FrameError.AliasedBuffers) # Include all later source bytes.
  var cursor = 0
  putExtrinsic(source, output, cursor)
  doAssert cursor == size
  FrameResult[int](error: FrameError.None, value: size)

# Copy parent cardinalities without exposing mutable child buffers or source descriptors.
proc extrinsicInfo*(owner: OwnedExtrinsic): FrameResult[ExtrinsicInfo] =
  if owner.data.isNil: return FrameResult[ExtrinsicInfo](
      error: FrameError.InvalidOwner) # Defaults differ from a validated empty frame.
  FrameResult[ExtrinsicInfo](error: FrameError.None, value: owner.data.info)

# Re-emit an immutable extrinsic using the policy captured with its exact schema-bound children.
proc encodeOwnedExtrinsic*(owner: OwnedExtrinsic, output: var openArray[byte]): FrameResult[int] =
  if owner.data.isNil: return FrameResult[int](error: FrameError.InvalidOwner) # Uninitialized owners cannot encode empty children.
  encodeExtrinsic(owner.data.source, owner.data.config, output)

# Retain the original tickets snapshot after the extrinsic/block owner is released.
proc extrinsicTickets*(owner: OwnedExtrinsic): FrameResult[TicketComponent] =
  if owner.data.isNil: return FrameResult[TicketComponent](
      error: FrameError.InvalidOwner) # No child exists for an absent owner.
  FrameResult[TicketComponent](error: FrameError.None, value: owner.data.source.tickets)

# Retain the original preimages snapshot after the extrinsic/block owner is released.
proc extrinsicPreimages*(owner: OwnedExtrinsic): FrameResult[PreimageComponent] =
  if owner.data.isNil: return FrameResult[PreimageComponent](
      error: FrameError.InvalidOwner) # No child exists for an absent owner.
  FrameResult[PreimageComponent](error: FrameError.None, value: owner.data.source.preimages)

# Retain the original guarantees snapshot after the extrinsic/block owner is released.
proc extrinsicGuarantees*(owner: OwnedExtrinsic): FrameResult[GuaranteeComponent] =
  if owner.data.isNil: return FrameResult[GuaranteeComponent](
      error: FrameError.InvalidOwner) # No child exists for an absent owner.
  FrameResult[GuaranteeComponent](error: FrameError.None, value: owner.data.source.guarantees)

# Retain the original assurances snapshot after the extrinsic/block owner is released.
proc extrinsicAssurances*(owner: OwnedExtrinsic): FrameResult[AssuranceComponent] =
  if owner.data.isNil: return FrameResult[AssuranceComponent](
      error: FrameError.InvalidOwner) # No child exists for an absent owner.
  FrameResult[AssuranceComponent](error: FrameError.None, value: owner.data.source.assurances)

# Retain the original disputes snapshot after the extrinsic/block owner is released.
proc extrinsicDisputes*(owner: OwnedExtrinsic): FrameResult[DisputeComponent] =
  if owner.data.isNil: return FrameResult[DisputeComponent](
      error: FrameError.InvalidOwner) # No child exists for an absent owner.
  FrameResult[DisputeComponent](error: FrameError.None, value: owner.data.source.disputes)

# Measure a complete block before capacity/aliases; the header and all extrinsic children share one byte budget.
proc measureBlock(source: Block, config: FrameConfig): FrameResult[BlockInfo] =
  if not validConfig(config): return FrameResult[BlockInfo](
      error: FrameError.InvalidConfig) # Configuration precedes owner access.
  if source.header.data.isNil or source.extrinsic.data.isNil:
    return FrameResult[BlockInfo](error: FrameError.InvalidOwner) # Both children must be initialized validated snapshots.
  let h = inspect[ComponentKind.Header](source.header.data.wire, config)
  if h.error == FrameError.InvalidComponent: return failed[BlockInfo](
      h.cause) # Never publish an unsigned/partial block header.
  # Stop before reading success-only metadata or capturing/writing any child bytes.
  if h.error != FrameError.None: return FrameResult[BlockInfo](error: h.error)
  if h.value.consumed != source.header.data.wire.len:
    return FrameResult[BlockInfo](error: FrameError.InvalidConfig) # Profile changes must preserve exact owned header extent.
  var remaining = config
  remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(h.value.consumed))
  let e = measure(source.extrinsic.data.source, remaining)
  if e.error == FrameError.InvalidComponent: return failed[BlockInfo](
      e.cause) # Late extrinsic failures cannot write the header.
  # Stop before reading success-only metadata or capturing/writing any child bytes.
  if e.error != FrameError.None: return FrameResult[BlockInfo](error: e.error)
  var total = h.value.consumed
  let error = advance(total, e.value.consumed, config)
  if error != FrameError.None: return FrameResult[BlockInfo](
      error: error) # Guard final host arithmetic before output allocation/access.
  FrameResult[BlockInfo](error: FrameError.None, value: BlockInfo(headerBytes: h.value.consumed,
    extrinsicBytes: e.value.consumed, consumed: total))

# Encode complete immutable block sources atomically; hashes/signatures/state relationships are separate validation.
proc encodeBlock*(source: Block, config: FrameConfig, output: var openArray[byte]): FrameResult[int] =
  let measured = measureBlock(source, config)
  if measured.error == FrameError.InvalidComponent: return failed[int](
      measured.cause) # Validate the final child before header writes.
  # Stop before reading success-only metadata or capturing/writing any child bytes.
  if measured.error != FrameError.None: return FrameResult[int](error: measured.error)
  let size = measured.value.consumed
  if output.len < size: return FrameResult[int](error: FrameError.OutputTooSmall) # Whole capacity precedes pointer access.
  if overlaps(unsafeAddr source, sizeof(source), addr output[0], size):
    return FrameResult[int](error: FrameError.AliasedBuffers) # Protect borrowed block descriptors and their ARC handles.
  if aliases(source.header, output, size) or extrinsicAlias(source.extrinsic.data.source, output, size):
    return FrameResult[int](error: FrameError.AliasedBuffers) # Whole destination includes cross-component overlaps.
  var cursor = 0
  put(source.header, output, cursor)
  putExtrinsic(source.extrinsic.data.source, output, cursor)
  doAssert cursor == size
  FrameResult[int](error: FrameError.None, value: size)

# Decode/capture both block children only after the complete sealed-header/extrinsic scan succeeds.
proc decodeBlock*(input: openArray[byte], config: FrameConfig): FrameResult[BlockRead] =
  let h = inspect[ComponentKind.Header](input, config)
  if h.error == FrameError.InvalidComponent: return failed[BlockRead](
      h.cause) # Header framing failures remain correctly attributed.
  # Stop before reading success-only metadata or capturing/writing any child bytes.
  if h.error != FrameError.None: return FrameResult[BlockRead](error: h.error)
  var remaining = config
  remaining.maxBytes = ByteLimit(uint64(config.maxBytes)-uint64(h.value.consumed))
  let e = scanExtrinsic(input.toOpenArray(h.value.consumed, input.high), remaining)
  if e.error == FrameError.InvalidComponent: return failed[BlockRead](
      e.cause) # Late failures allocate no parent/child snapshots.
  # Stop before reading success-only metadata or capturing/writing any child bytes.
  if e.error != FrameError.None: return FrameResult[BlockRead](error: e.error)
  let total = h.value.consumed+e.value.info.consumed
  let source = Block(header: capture[ComponentKind.Header](input, config, h.value),
    extrinsic: captureExtrinsic(input.toOpenArray(h.value.consumed, input.high), remaining, e.value))
  let info = BlockInfo(headerBytes: h.value.consumed, extrinsicBytes: e.value.info.consumed,
      consumed: total)
  FrameResult[BlockRead](error: FrameError.None, value: BlockRead(
    owner: OwnedBlock(data: BlockData(source: source, config: config, info: info)),
        consumed: total))

# Copy block metadata without publishing private child positions or mutable storage.
proc blockInfo*(owner: OwnedBlock): FrameResult[BlockInfo] =
  if owner.data.isNil: return FrameResult[BlockInfo](
      error: FrameError.InvalidOwner) # Default handles have no complete block.
  FrameResult[BlockInfo](error: FrameError.None, value: owner.data.info)

# Retain the exact complete sealed header component after releasing its enclosing block.
proc blockHeader*(owner: OwnedBlock): FrameResult[HeaderComponent] =
  if owner.data.isNil: return FrameResult[HeaderComponent](
      error: FrameError.InvalidOwner) # No child for default blocks.
  FrameResult[HeaderComponent](error: FrameError.None, value: owner.data.source.header)

# Retain all exact extrinsic children after releasing their enclosing block.
proc blockExtrinsic*(owner: OwnedBlock): FrameResult[OwnedExtrinsic] =
  if owner.data.isNil: return FrameResult[OwnedExtrinsic](
      error: FrameError.InvalidOwner) # No fabricated empty frame.
  FrameResult[OwnedExtrinsic](error: FrameError.None, value: owner.data.source.extrinsic)

# Re-emit a captured block atomically using its captured configuration and immutable child bytes.
proc encodeOwnedBlock*(owner: OwnedBlock, output: var openArray[byte]): FrameResult[int] =
  if owner.data.isNil: return FrameResult[int](error: FrameError.InvalidOwner) # Default snapshots contain no valid header/extrinsic.
  encodeBlock(owner.data.source, owner.data.config, output)

# Return independent copied ticket records, never the component's immutable backing wire/storage.
proc readTickets*(owner: TicketComponent): FrameResult[seq[Ticket]] =
  if owner.data.isNil: return FrameResult[seq[Ticket]](
      error: FrameError.InvalidOwner) # Defaults cannot supply record counts.
  var values = newSeq[Ticket](owner.data.info.records)
  let parsed = decodeTickets(owner.data.wire, owner.data.config.ticketLimit, values)
  # A child failure must remain attributed to its schema, with no partial parent value.
  if parsed.error != TicketError.None:
    return failed[seq[Ticket]](ComponentFailure(kind: ComponentKind.Tickets,
        ticketError: parsed.error)) # Preserve future child-contract errors.
  FrameResult[seq[Ticket]](error: FrameError.None, value: values)

# Return independent copied assurance records under the exact component profile, without exposing mutable snapshots.
proc readAssurances*(owner: AssuranceComponent): FrameResult[seq[Assurance]] =
  if owner.data.isNil: return FrameResult[seq[Assurance]](
      error: FrameError.InvalidOwner) # Default owners have no validator population.
  var values = newSeq[Assurance](owner.data.info.records)
  let config = owner.data.config
  let parsed = decodeAssurances(owner.data.wire, AssuranceConfig(cores: config.cores,
      validators: config.validators), values)
  # A child failure must remain attributed to its schema, with no partial parent value.
  if parsed.error != AssuranceError.None:
    return failed[seq[Assurance]](ComponentFailure(kind: ComponentKind.Assurances,
        assuranceError: parsed.error)) # No partial records on failure.
  FrameResult[seq[Assurance]](error: FrameError.None, value: values)

# Materialize an existing immutable preimage-family owner on demand from the exact retained component bytes.
proc readPreimages*(owner: PreimageComponent): OwnedResult[OwnedFrame] =
  if owner.data.isNil: return ownedFailure[OwnedFrame](
      OwnershipError.InvalidOwner) # No schema reinterpretation for defaults.
  decodeOwnedPreimages(owner.data.wire, owner.data.config.preimages)

# Materialize the existing report/credential owner API on demand, keeping JAM report logic in its original codec.
proc readGuarantees*(owner: GuaranteeComponent): GuaranteeResult[GuaranteesRead] =
  if owner.data.isNil: return guaranteeFailure[GuaranteesRead](
      GuaranteeError.InvalidOwner) # Defaults carry no reports.
  let config = owner.data.config
  decodeGuarantees(owner.data.wire, GuaranteeConfig(cores: config.cores,
      validators: config.validators, maxBytes: config.maxBytes))

# Materialize the existing immutable disputes API without exporting raw wire or detached spans.
proc readDisputes*(owner: DisputeComponent): DisputeResult[DisputesRead] =
  if owner.data.isNil: return DisputeResult[DisputesRead](
      error: DisputeError.InvalidOwner) # Missing snapshots carry no verdicts.
  let config = owner.data.config
  decodeDisputes(owner.data.wire, DisputeConfig(validators: config.validators,
      maxBytes: config.maxBytes))

# Materialize the existing sealed-header/marker API on demand; an unsigned component has no matching type.
proc readHeader*(owner: HeaderComponent): HeaderResult[HeaderRead] =
  if owner.data.isNil: return HeaderResult[HeaderRead](
      error: HeaderError.InvalidOwner) # Defaults cannot fabricate a seal.
  decodeHeader(owner.data.wire, headerConfig(owner.data.config))
