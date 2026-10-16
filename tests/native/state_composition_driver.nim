## Trusted fixture transport and supplementary ownership/default/association guards.
import std/[os, strutils]
import ../../src/codec/[state_composition, state_trie, state_layout, bounded, assurances,
  state_consensus, state_safrole, state_privileges, state_accounts, state_service_values, state_requests]

## Empty payloads use one explicit token; all other bytes retain exact order.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Preserve present-empty payloads in whitespace transport.
  doAssert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Each complete octet is parsed without normalization or silent truncation.
  for i in 0..<result.len: result[i] = byte(parseHexInt(text[2*i..2*i+1]))

## Fixed hash/key adapters reject accidental shape changes in trusted test fixtures.
proc fixed[N: static int](text: string): array[N, byte] =
  let raw = unhex(text)
  doAssert raw.len == N
  # Preserve every supplied fixed byte independently of the input backing sequence.
  for i in 0..<N: result[i] = raw[i]

## Return exact root bytes for comparison against an independently computed expected identity.
proc hex(root: StateRoot): string =
  # Leading zeroes belong to the complete fixed root.
  for b in array[32, byte](root): result.add(toHex(b, 2).toLowerAscii())

## Default/failed results cannot expose a fabricated application value with field checks enabled.
proc guarded[T](value: StateCompositionResult[T]) =
  var caught = false
  try:
    discard value.value # Invalid variant access must trap before application use.
  except FieldDefect:
    caught = true # This expected guard is part of the public failure-only contract.
  doAssert caught

let broad = StateChapterPolicy(items: ElementLimit(1_000_000), maxBytes: ByteLimit(8_000_000))
var profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
  previous: ValidatorCount(6), epochSlots: EpochSlots(2))
let limits = StateTrieLimits(items: ElementLimit(1000), perValue: ByteLimit(8_000_000),
  totalValueBytes: ByteLimit(16_000_000), nodes: TrieNodeLimit(250_000))
var baseline: array[StateChapterId, StateChapterSnapshot]

## Supplementary cases exercise association, late errors and private owned bytes beyond root equality.
proc selftest() =
  let complete = composeState(baseline, [], limits, ByteLimit(128))
  doAssert complete.error == StateCompositionError.None
  let owner = complete.value
  let root = stateCommitment(owner).value.root
  var copy = stateEntryAt(owner, StateEntryIndex(0)).value
  copy.value[0] = copy.value[0] xor 255
  doAssert stateEntryAt(owner, StateEntryIndex(0)).value.value != copy.value
  doAssert array[32, byte](stateCommitment(owner).value.root) == array[32, byte](root)
  guarded(stateEntryAt(owner, StateEntryIndex(high(uint64))))
  guarded(stateCommitment(default(StateSnapshot)))
  guarded(default(StateCompositionResult[StateSnapshot]))
  var replaced = owner
  replaced = default(StateSnapshot)
  guarded(stateCommitment(replaced))
  doAssert stateCommitment(owner).value.entries == 16
  var parts = baseline
  parts[StateChapterId.Outputs] = default(StateChapterSnapshot)
  let absent = composeState(parts, [], limits, ByteLimit(128))
  doAssert absent.error == StateCompositionError.InvalidOwner
  guarded(absent)
  parts = baseline
  parts[StateChapterId.Outputs] = baseline[StateChapterId.Time]
  doAssert composeState(parts, [], limits, ByteLimit(128)).error ==
      StateCompositionError.WrongChapter
  parts = baseline
  var other = profile
  other.cores = CoreCount(3)
  parts[StateChapterId.Entropy] = captureStateChapter(StateChapterId.Entropy, newSeq[byte](128),
      other, broad).value
  doAssert composeState(parts, [], limits, ByteLimit(128)).error ==
      StateCompositionError.ProfileMismatch
  var bytes = timeEntry(StateTime(1)).value # Existing typed encoders feed exact chapter capture.
  parts = baseline
  parts[StateChapterId.Time] = captureStateChapter(StateChapterId.Time, bytes, profile, broad).value
  bytes[0] = 99
  let captured = composeState(parts, [], limits, ByteLimit(128)).value
  doAssert stateEntryAt(captured, StateEntryIndex(10)).value.value == @[byte(1), 0, 0, 0]
  var service = StateService(service: ServiceIndex(7), storage: @[StateStorageItem(key: @[byte(1)],
      value: @[byte(42)])])
  let saved = composeState(baseline, [service], limits, ByteLimit(1)).value
  service.storage[0].value[0] = 99
  doAssert stateEntryAt(saved, StateEntryIndex(17)).value.value == @[byte(42)]
  var short = limits
  short.totalValueBytes = ByteLimit(0)
  doAssert composeState(baseline, [service], short, ByteLimit(1)).error ==
      StateCompositionError.LimitExceeded
  doAssert composeState(baseline, [service], limits, ByteLimit(0)).error ==
      StateCompositionError.LimitExceeded
  doAssert composeState(baseline, [service, service], limits, ByteLimit(1)).error ==
      StateCompositionError.DuplicateKey
  service = StateService(service: ServiceIndex(7), captured: @[default(ServiceValueSnapshot)])
  doAssert composeState(baseline, [service], limits, ByteLimit(1)).error ==
      StateCompositionError.InvalidOwner
  let entry = serviceStorageEntry(ServiceIndex(8), [], [], ServiceEntryLimits(keyBytes: ByteLimit(
      0), valueBytes: ByteLimit(0))).value
  service.captured[0] = captureServiceValue(ServiceIndex(8), entry.key, entry.value, ByteLimit(0)).value
  doAssert composeState(baseline, [service], limits, ByteLimit(1)).error ==
      StateCompositionError.InvalidComponent
  let privilege = privilegeStateEntry(PrivilegeState(assigners: @[ServiceIndex(0), ServiceIndex(0)]),
    PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(0), maxBytes: ByteLimit(21))).value
  parts = baseline
  parts[StateChapterId.Privileges] = captureStateChapter(StateChapterId.Privileges, privilege.value,
      profile, broad).value
  doAssert stateEntryAt(composeState(parts, [], limits, ByteLimit(0)).value, StateEntryIndex(
      11)).value.value == privilege.value
  let chapterKey = stateEntryAt(owner, StateEntryIndex(0)).value.key
  service = StateService(service: ServiceIndex(1), captured: @[
    captureServiceValue(ServiceIndex(1), chapterKey, [], ByteLimit(0)).value])
  doAssert composeState(baseline, [service], limits, ByteLimit(0)).error ==
      StateCompositionError.DuplicateKey
  guarded(captureStateChapter(StateChapterId.Time, [], profile, broad))
  service = StateService(service: ServiceIndex(7), preimages: @[StatePreimageItem()],
    requests: @[StateRequestItem(length: RequestLength(0xfffffffe'u32))])
  let overlap = composeState(baseline, [service], limits, ByteLimit(1))
  doAssert overlap.error == StateCompositionError.DuplicateKey
  guarded(overlap)

## Construct a complete typed service source from fixed metadata and explicitly delimited nested items.
proc service(text: string): StateService =
  let fields = text.split('|')
  doAssert fields.len == 6
  result.service = ServiceIndex(parseBiggestUInt(fields[0]))
  let metadata = unhex(fields[1])
  let decoded = decodeServiceMetadata(metadata, ByteLimit(89))
  doAssert decoded.error == ServiceMetadataError.None and decoded.value.consumed == metadata.len
  result.metadata = decoded.value.metadata
  # Empty lists carry no synthetic entry, unlike a listed item with an empty value token.
  if fields[2] != "-":
    for item in fields[2].split(','):
      let pair = item.split(':')
      result.storage.add(StateStorageItem(key: unhex(pair[0]), value: unhex(pair[1])))
  # Hash identities remain independent of raw content in the structural preimage source.
  if fields[3] != "-":
    for item in fields[3].split(','):
      let pair = item.split(':')
      result.preimages.add(StatePreimageItem(hash: ServicePreimageHash(fixed[32](pair[0])),
          value: unhex(pair[1])))
  # Decode fixed tagged histories solely to build the typed source transported by these trusted fixtures.
  if fields[4] != "-":
    for item in fields[4].split(','):
      let pair = item.split(':')
      let raw = unhex(pair[2])
      let history = decodeRequestHistory(raw, RequestHistoryConfig(items: ElementLimit(3),
          maxBytes: ByteLimit(13)))
      doAssert history.error == RequestError.None and history.value.consumed == raw.len
      result.requests.add(StateRequestItem(hash: ServicePreimageHash(fixed[32](pair[0])),
        length: RequestLength(parseBiggestUInt(pair[1])), history: history.value.history))
  # Existing opaque handles are explicitly tied to the original service and full 31-byte key.
  if fields[5] != "-":
    for item in fields[5].split(','):
      let pair = item.split(':')
      result.captured.add(captureServiceValue(result.service, StateKey(fixed[31](pair[0])),
        unhex(pair[1]), ByteLimit(8_000_000)).value)

# Each trusted request observes either exact entry bytes/root/counts or a failure-only reason.
for line in lines(paramStr(1)):
  let fields = line.splitWhitespace()
  case fields[0]
  of "B":
    # Each baseline declares its own chain profile, including the published twelve-slot tiny epoch.
    profile = StateProfile(cores: CoreCount(parseBiggestUInt(fields[1])), current: ValidatorCount(
        parseBiggestUInt(fields[2])),
      previous: ValidatorCount(parseBiggestUInt(fields[3])), epochSlots: EpochSlots(
          parseBiggestUInt(fields[4])))
    # Baseline bytes come from independent equations, never from production round trips.
    for chapter in StateChapterId:
      baseline[chapter] = captureStateChapter(chapter, unhex(fields[ord(chapter)+4]), profile, broad).value
    selftest()
    echo "selftest"
  of "C":
    # Capture probes can change profile and item/byte policy independently of raw bytes.
    let p = StateProfile(cores: CoreCount(parseBiggestUInt(fields[1])), current: ValidatorCount(
        parseBiggestUInt(fields[2])),
      previous: ValidatorCount(parseBiggestUInt(fields[3])), epochSlots: EpochSlots(
          parseBiggestUInt(fields[4])))
    let policy = StateChapterPolicy(items: ElementLimit(parseBiggestUInt(fields[5])),
        maxBytes: ByteLimit(parseBiggestUInt(fields[6])))
    let captured = captureStateChapter(StateChapterId(parseInt(fields[7])), unhex(fields[8]), p, policy)
    echo (if captured.error == StateCompositionError.None: "ok" else: (
        $captured.error).toLowerAscii())
  of "S":
    # Full composition uses exact captured chapters and typed service records with independent parent limits.
    var parts = baseline
    let selected = parseInt(fields[6])
    if selected != 0:
      parts[StateChapterId(selected)] = captureStateChapter(StateChapterId(selected), unhex(fields[
          7]), profile, broad).value # Replace only a trusted valid chapter.
    let policy = StateTrieLimits(items: ElementLimit(parseBiggestUInt(fields[1])),
        perValue: ByteLimit(parseBiggestUInt(fields[2])),
      totalValueBytes: ByteLimit(parseBiggestUInt(fields[3])), nodes: TrieNodeLimit(
          parseBiggestUInt(fields[4])))
    var services: seq[StateService]
    # Every listed service is retained, including duplicates that the composition API must reject.
    for i in 8..<fields.len: services.add(service(fields[i]))
    let composed = composeState(parts, services, policy, ByteLimit(parseBiggestUInt(fields[5])))
    if composed.error != StateCompositionError.None:
      echo ($composed.error).toLowerAscii() # Failure has no mapping, root or intermediate count.
    else:
      let info = stateCommitment(composed.value).value
      var output = hex(info.root) & " " & $info.entries & " " & $info.nodes & " "
      # Observe every complete independent entry; root equality alone must not hide a component mismatch.
      for i in 0..<info.entries:
        let entry = stateEntryAt(composed.value, StateEntryIndex(i)).value
        for b in array[31, byte](entry.key): output.add(toHex(b, 2).toLowerAscii()) # Fixed key observation.
        output.add(":")
        for b in entry.value: output.add(toHex(b, 2).toLowerAscii()) # Complete value observation.
        output.add(";")
      echo output
  else:
    doAssert false # Unknown trusted transport commands are harness errors, not protocol alternatives.
