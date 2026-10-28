# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted fixture transport and supplementary ownership/default/association guards.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/syncio
import std/strutils
import std/parseutils
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/state_consensus as codec_state_consensus
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/state_privileges as codec_state_privileges
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_service_values as codec_state_service_values
import ../../src/codec/state_requests as codec_state_requests

## Empty payloads use one explicit token; all other bytes retain exact order.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Preserve present-empty payloads in whitespace transport.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Each complete octet is parsed without normalization or silent truncation.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Trusted fixture transport contains exactly two lowercase hex digits for each complete octet.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Fixed hash/key adapters reject accidental shape changes in trusted test fixtures.
proc fixed[N: static[int]](text: string): array[N, byte] =
  result = default(array[N, byte])
  let raw = unhex(text)
  assert raw.len == N
  # Preserve every supplied fixed byte independently of the input backing sequence.
  for i in 0..<N: result[i] = raw[i]

## Return exact root bytes for comparison against an independently computed expected identity.
proc hex(root: StateRoot): string =
  result = ""
  # Leading zeroes belong to the complete fixed root.
  for b in array[32, byte](root): result.add(toHex(int(b), 2).toLowerAscii())

let broad = StateChapterPolicy(items: ElementLimit(1_000_000), maxBytes: ByteLimit(8_000_000))
var profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
  previous: ValidatorCount(6), epochSlots: EpochSlots(2))
let limits = StateTrieLimits(items: ElementLimit(1000), perValue: ByteLimit(8_000_000),
  totalValueBytes: ByteLimit(16_000_000), nodes: TrieNodeLimit(250_000))
var baseline = default(StateChapters)

## Parse a complete trusted uint64 token through the supported nonthrowing interface.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number
## Fixture indices must fit native indexing before conversion.
proc integer(text: string): int =
  let number = unsigned(text)
  assert number <= uint64(high(int))
  int(number)

## Supplementary cases exercise association, late errors and private owned bytes beyond root equality.
proc selftest(baseline: StateChapters, profile: StateProfile) =
  let complete = composeState(baseline, [], limits, ByteLimit(128))
  assert complete.error == StateCompositionError.None
  let owner = complete.value
  let root = stateCommitment(owner).value.root
  var copy = stateEntryAt(owner, StateEntryIndex(0)).value
  copy.value[0] = copy.value[0] xor 255
  assert stateEntryAt(owner, StateEntryIndex(0)).value.value != copy.value
  assert array[32, byte](stateCommitment(owner).value.root) == array[32, byte](root)
  var replaced = owner
  replaced = default(StateSnapshot)
  assert stateCommitment(owner).value.entries == 16
  var parts = baseline
  parts[StateChapterId.Outputs] = default(StateChapterSnapshot)
  let absent = composeState(parts, [], limits, ByteLimit(128))
  assert absent.error == StateCompositionError.InvalidOwner
  parts = baseline
  parts[StateChapterId.Outputs] = baseline[StateChapterId.Time]
  assert composeState(parts, [], limits, ByteLimit(128)).error ==
      StateCompositionError.WrongChapter
  parts = baseline
  var other = profile
  other.cores = CoreCount(3)
  parts[StateChapterId.Entropy] = captureStateChapter(StateChapterId.Entropy, newSeq[byte](128),
      other, broad).value
  assert composeState(parts, [], limits, ByteLimit(128)).error ==
      StateCompositionError.ProfileMismatch
  var bytes = timeEntry(StateTime(1)).value # Existing typed encoders feed exact chapter capture.
  parts = baseline
  parts[StateChapterId.Time] = captureStateChapter(StateChapterId.Time, bytes, profile, broad).value
  bytes[0] = 99
  let captured = composeState(parts, [], limits, ByteLimit(128)).value
  assert stateEntryAt(captured, StateEntryIndex(10)).value.value == @[byte(1), 0, 0, 0]
  var service = StateService(service: ServiceIndex(7), storage: @[StateStorageItem(key: @[byte(1)],
      value: @[byte(42)])])
  let saved = composeState(baseline, [service], limits, ByteLimit(1)).value
  service.storage[0].value[0] = 99
  assert stateEntryAt(saved, StateEntryIndex(17)).value.value == @[byte(42)]
  var short = limits
  short.totalValueBytes = ByteLimit(0)
  assert composeState(baseline, [service], short, ByteLimit(1)).error ==
      StateCompositionError.LimitExceeded
  assert composeState(baseline, [service], limits, ByteLimit(0)).error ==
      StateCompositionError.LimitExceeded
  assert composeState(baseline, [service, service], limits, ByteLimit(1)).error ==
      StateCompositionError.DuplicateKey
  service = StateService(service: ServiceIndex(7), captured: @[default(ServiceValueSnapshot)])
  assert composeState(baseline, [service], limits, ByteLimit(1)).error ==
      StateCompositionError.InvalidOwner
  let entry = serviceStorageEntry(ServiceIndex(8), [], [], ServiceEntryLimits(keyBytes: ByteLimit(
      0), valueBytes: ByteLimit(0))).value
  service.captured[0] = captureServiceValue(ServiceIndex(8), entry.key, entry.value, ByteLimit(0)).value
  assert composeState(baseline, [service], limits, ByteLimit(1)).error ==
      StateCompositionError.InvalidComponent
  let privilege = privilegeStateEntry(PrivilegeState(assigners: @[ServiceIndex(0), ServiceIndex(0)]),
    PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(0), maxBytes: ByteLimit(21))).value
  parts = baseline
  parts[StateChapterId.Privileges] = captureStateChapter(StateChapterId.Privileges, privilege.value,
      profile, broad).value
  assert stateEntryAt(composeState(parts, [], limits, ByteLimit(0)).value, StateEntryIndex(
      11)).value.value == privilege.value
  let chapterKey = stateEntryAt(owner, StateEntryIndex(0)).value.key
  service = StateService(service: ServiceIndex(1), captured: @[
    captureServiceValue(ServiceIndex(1), chapterKey, [], ByteLimit(0)).value])
  assert composeState(baseline, [service], limits, ByteLimit(0)).error ==
      StateCompositionError.DuplicateKey
  service = StateService(service: ServiceIndex(7), preimages: @[StatePreimageItem()],
    requests: @[StateRequestItem(length: RequestLength(0xfffffffe'u32))])
  let overlap = composeState(baseline, [service], limits, ByteLimit(1))
  assert overlap.error == StateCompositionError.InvalidComponent # Current request lengths exclude both historical aliases.


## Construct a complete typed service source from fixed metadata and explicitly delimited nested items.
proc service(text: string): StateService =
  result = default(StateService)
  let fields = text.split('|')
  assert fields.len == 6
  result.service = ServiceIndex(unsigned(fields[0]))
  let metadata = unhex(fields[1])
  let decoded = decodeServiceMetadata(metadata, ByteLimit(ServiceMetadataBytes))
  assert decoded.error == ServiceMetadataError.None and decoded.value.consumed == metadata.len
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
      assert history.error == RequestError.None and history.value.consumed == raw.len
      result.requests.add(StateRequestItem(hash: ServicePreimageHash(fixed[32](pair[0])),
        length: RequestLength(unsigned(pair[1])), history: history.value.history))
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
    profile = StateProfile(cores: CoreCount(unsigned(fields[1])), current: ValidatorCount(
        unsigned(fields[2])),
      previous: ValidatorCount(unsigned(fields[3])), epochSlots: EpochSlots(
          unsigned(fields[4])))
    # Baseline bytes come from independent equations, never from production round trips.
    for chapterNumber in ord(StateChapterId.Pools)..ord(StateChapterId.Outputs):
      let chapter = StateChapterId(chapterNumber)
      baseline[chapter] = captureStateChapter(chapter, unhex(fields[ord(chapter)+4]), profile, broad).value
    selftest(baseline, profile)
    echo "selftest"
  of "C":
    # Capture probes can change profile and item/byte policy independently of raw bytes.
    let p = StateProfile(cores: CoreCount(unsigned(fields[1])), current: ValidatorCount(
        unsigned(fields[2])),
      previous: ValidatorCount(unsigned(fields[3])), epochSlots: EpochSlots(
          unsigned(fields[4])))
    let policy = StateChapterPolicy(items: ElementLimit(unsigned(fields[5])),
        maxBytes: ByteLimit(unsigned(fields[6])))
    let captured = captureStateChapter(StateChapterId(integer(fields[7])), unhex(fields[8]), p, policy)
    echo (if captured.error == StateCompositionError.None: "ok" else: (
        $captured.error).toLowerAscii())
  of "S":
    # Full composition uses exact captured chapters and typed service records with independent parent limits.
    var parts = baseline
    let selected = integer(fields[6])
    if selected != 0:
      parts[StateChapterId(selected)] = captureStateChapter(StateChapterId(selected), unhex(fields[
          7]), profile, broad).value # Replace only a trusted valid chapter.
    let policy = StateTrieLimits(items: ElementLimit(unsigned(fields[1])),
        perValue: ByteLimit(unsigned(fields[2])),
      totalValueBytes: ByteLimit(unsigned(fields[3])), nodes: TrieNodeLimit(
          unsigned(fields[4])))
    var services: seq[StateService] = @[]
    # Every listed service is retained, including duplicates that the composition API must reject.
    for i in 8..<fields.len: services.add(service(fields[i]))
    let composed = composeState(parts, services, policy, ByteLimit(unsigned(fields[5])))
    if composed.error != StateCompositionError.None:
      echo ($composed.error).toLowerAscii() # Failure has no mapping, root or intermediate count.
    else:
      let info = stateCommitment(composed.value).value
      var output = hex(info.root) & " " & $info.entries & " " & $info.nodes & " "
      # Observe every complete independent entry; root equality alone must not hide a component mismatch.
      for i in 0..<info.entries:
        let entry = stateEntryAt(composed.value, StateEntryIndex(i)).value
        for b in array[31, byte](entry.key): output.add(toHex(int(b), 2).toLowerAscii()) # Fixed key observation.
        output.add(":")
        for b in entry.value: output.add(toHex(int(b), 2).toLowerAscii()) # Complete value observation.
        output.add(";")
      echo output
  else:
    assert false # Unknown trusted transport commands are harness errors, not protocol alternatives.
