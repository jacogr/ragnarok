# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native preimage STF account/statistics projections and prior/post-state phase-boundary regressions.
## Hastur entry point checks ordering, bounded work, atomic rollback, retained ownership and ARC release.

import std/[assertions, envvars, strutils, parseutils, syncio]
import ../../../src/state/[preimages, store]
import ../../../src/codec/[natural, bounded, composite, owned, header, state_layout, state_trie,
  state_accounts, state_service_values, state_requests]
import ../../../src/crypto/primitives
import ../../support/arc_evidence

## Reject/count maintained provider hashes after actual fixtures have been constructed.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Allow exact namespace work before rejecting a later key/root operation.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

## Authored item inputs own their test bytes; production only accepts the captured frame.
type Item = object
  service: uint32
  blob: seq[byte]

## Small explicit complete-map budgets make late publication ceilings reachable.
proc storeLimits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1000), perValue: ByteLimit(1000000),
    totalValueBytes: ByteLimit(1000000), nodes: TrieNodeLimit(10000)),
    writes: ElementLimit(1000), writeValueBytes: ByteLimit(1000000))

## Independent admission work/copy ceilings are reapplied even if capture used a broader policy.
proc config(): PreimageLimits =
  PreimageLimits(items: ElementLimit(100), perBlob: ByteLimit(1000000), totalBlobBytes: ByteLimit(1000000))

## Trusted hexadecimal fixture transport preserves empty values explicitly as '-'.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty raw trie values are present rather than absent.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len: assert parseHex(text[i*2..i*2+1], result[i]) ==
      2 # Exact fixture octets, not a production decoder.

## Preserve full unsigned trusted scalar domains without relying on a missing returning parseUInt overload.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Convert exactly 31 trusted transport bytes into a nominal state-key value.
proc key(text: string): StateKey =
  let bytes = unhex(text)
  assert bytes.len == 31
  var raw = default(array[31, byte])
  for i in 0..<31: raw[i] = bytes[i] # Width is proved before access.
  StateKey(raw)

## Copy the complete trusted mapping segment, retaining zero-length values.
proc readEntries(lines: seq[string], cursor: var int, count: int): seq[StateEntry] =
  result = @[]
  for i in 0..<count:
    let parts = lines[cursor].splitWhitespace
    inc cursor
    result.add(StateEntry(key: key(parts[0]), value: unhex(parts[
        1]))) # Independently serialized expected bytes are not repaired.

## Assert exact complete-map root/cardinality and every serialized value.
proc matches(state: StateStoreSnapshot, entries: seq[StateEntry], root: seq[byte]) =
  let commitment = state.commitment
  let actual = array[32, byte](commitment.root)
  assert root.len == 32 and commitment.entries == entries.len
  for i in 0..<32: assert actual[i] == root[i] # Independently computed embedding root.
  for entry in entries: assert state.lookup(entry.key).value.bytes ==
      entry.value # Preserve all unrelated and requested fields.

## Replay all tiny/full published account/verdict/statistics projections without running a reference transition.
proc published() {.raises.} =
  let lines = readFile(getEnv("RAGNAROK_PREIMAGE_TRANSITION")).splitLines
  var cursor = 0
  var cases = 0
  # Consume each complete transport case, including its full before/after mapping and statistics rows.
  while cursor < lines.len and lines[cursor].len != 0:
    let fields = lines[cursor].splitWhitespace
    inc cursor
    let before = readEntries(lines, cursor, parseInt(fields[3]))
    let after = readEntries(lines, cursor, parseInt(fields[4]))
    let statistics = parseInt(fields[5])
    var state = newStateStore(before, storeLimits()).value
    let prior = state.snapshot.value
    matches(prior, before, unhex(fields[7]))
    let frame = decodeOwnedPreimages(unhex(fields[6]), config()).value
    let admitted = admitPreimages(prior, frame, config())
    assert $admitted.error == fields[2], fields[0] & " " & $admitted.error
    if admitted.error == PreimageTransitionError.None:
      let plan = admitted.value
      assert plan.preimageInfo.value.services == statistics
      for i in 0..<statistics:
        let expected = lines[cursor].splitWhitespace
        inc cursor
        let row = plan.provisionAt(ProvisionIndex(uint64(i))).value
        assert uint32(row.service) == uint32(number(expected[0]))
        assert uint64(row.count) == uint64(number(expected[1]))
        assert uint64(row.bytes) == uint64(number(expected[2]))
      let applied = integratePreimages(state, plan, HeaderSlot(uint32(number(fields[1]))))
      assert applied.error == PreimageTransitionError.None
      matches(applied.value, after, unhex(fields[8]))
      matches(prior, before, unhex(fields[7])) # Retained prior state is immutable after publication.
    else:
      assert statistics == 0 # Invalid published extrinsics preserve account/statistics projections.
      matches(state.snapshot.value, after, unhex(fields[8]))
    inc cases
  assert cases == 16

## Build canonical test input framing before native owner capture; admission never receives these mutable arrays.
proc frame(items: openArray[Item]): OwnedFrame =
  var wire: seq[byte] = @[]
  let count = natural.encode(JamNatural(uint64(items.len)))
  for i in 0..<count.len: wire.add(count.bytes[i]) # General compact outer count.
  for item in items:
    for i in 0..<4: wire.add(byte((item.service shr (8*i)) and
        255)) # Service fields are E4, independent of sorting.
    let size = natural.encode(JamNatural(uint64(item.blob.len)))
    for i in 0..<size.len: wire.add(size.bytes[i]) # General compact blob length.
    for b in item.blob: wire.add(b) # Preserve exact input order and raw payload.
  decodeOwnedPreimages(wire, config()).value

## Derive a genuine request identity using the actual content hash and advertised length.
proc request(item: Item, history = requestedHistory()): StateEntry =
  let hash = ServicePreimageHash(array[32, byte](blake2b256(item.blob).value))
  serviceRequestEntry(ServiceIndex(item.service), hash, RequestLength(uint32(item.blob.len)), history,
    RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
        3), maxBytes: ByteLimit(13)))).value

## Create an authored complete map with distinct account metadata and opaque unrelated state.
proc entries(items: openArray[Item]): seq[StateEntry] =
  result = @[StateEntry(key: chapterKey(StateChapter(250)), value: @[9'u8, 4, 2])]
  var services: seq[uint32] = @[]
  for item in items:
    var seen = false
    for service in services:
      if service == item.service: seen = true # Add metadata only once per actual service identity.
    if not seen:
      services.add(item.service)
      result.add(serviceMetadataEntry(ServiceIndex(item.service), ServiceMetadata(
          balance: AccountBalance(99),
        created: AccountSlot(7), lastAccumulation: AccountSlot(8)), ByteLimit(
            89)).value) # All metadata fields must remain unchanged.
    result.add(request(item)) # Caller supplies unique request identities in these source fixtures.

## Assert immutable root equality without invoking hashing during a failure check.
proc same(a, b: StateStoreSnapshot) =
  assert array[32, byte](a.commitment.root) == array[32, byte](b.commitment.root)

## Exact ordering, resource and default/schema boundaries include valid empty blobs and full service domains.
proc boundaries(): AdmittedPreimages =
  let items: seq[Item] = @[Item(service: 0'u32, blob: newSeq[byte](0)), Item(service: 1'u32,
      blob: @[0'u8, 0, 0]),
    Item(service: 1'u32, blob: @[1'u8]), Item(service: high(uint32), blob: @[255'u8])]
  let state = newStateStore(entries(items), storeLimits()).value
  let prior = state.snapshot.value
  let source = frame(items)
  let plan = admitPreimages(prior, source, config()).value
  assert plan.preimageInfo.value.items == 4 and plan.preimageInfo.value.services == 3
  assert uint64(plan.preimageInfo.value.bytes) == 5
  assert uint64(plan.provisionAt(ProvisionIndex(1)).value.count) == 2
  assert uint64(plan.provisionAt(ProvisionIndex(1)).value.bytes) == 4
  assert plan.provisionAt(ProvisionIndex(high(uint64))).error ==
      PreimageTransitionError.InvalidIndex
  var copied = plan.provisionAt(ProvisionIndex(1)).value
  copied.count = ProvisionCount(99)
  assert uint64(plan.provisionAt(ProvisionIndex(1)).value.count) == 2
  var bytes = newSeq[byte](3)
  discard plan.preimageSource.value.copyOwnedBlob(1, bytes).value
  bytes[0] = 255
  discard plan.preimageSource.value.copyOwnedBlob(1, bytes).value
  assert bytes == @[0'u8, 0, 0]
  same(plan.preimagePrior.value, prior)
  # Raw blob ordering differs from length-prefixed framing; a proper prefix sorts first too.
  for sourceItems in [@[Item(service: 1'u32, blob: @[1'u8]), Item(service: 1'u32, blob: @[0'u8, 0,
      0])], @[Item(service: high(uint32), blob: @[255'u8]), Item(service: 0'u32, blob: newSeq[byte](0))],
      @[Item(service: 1'u32, blob: @[1'u8]), Item(service: 1'u32, blob: @[1'u8])]]:
    assert admitPreimages(prior, frame(sourceItems), config()).error ==
        PreimageTransitionError.NotOrderedUnique
  let prefix: seq[Item] = @[Item(service: 2'u32, blob: @[0'u8]), Item(service: 2'u32, blob: @[0'u8, 0])]
  assert admitPreimages(newStateStore(entries(prefix), storeLimits()).value.snapshot.value,
    frame(prefix), config()).error == PreimageTransitionError.None
  # These raw blobs ascend while their first hash octets descend; digest ordering must not select validity.
  let byBlob = @[Item(service: 2'u32, blob: @[1'u8]), Item(service: 2'u32, blob: @[2'u8])]
  assert array[32, byte](blake2b256(byBlob[0].blob).value)[0] > array[32, byte](blake2b256(byBlob[
      1].blob).value)[0]
  assert admitPreimages(newStateStore(entries(byBlob), storeLimits()).value.snapshot.value,
    frame(byBlob), config()).error == PreimageTransitionError.None
  let numeric: seq[Item] = @[Item(service: 1'u32, blob: @[1'u8]), Item(service: 256'u32, blob: @[2'u8])]
  assert admitPreimages(newStateStore(entries(numeric), storeLimits()).value.snapshot.value,
    frame(numeric), config()).error == PreimageTransitionError.None
  let exact = PreimageLimits(items: ElementLimit(4), perBlob: ByteLimit(3),
      totalBlobBytes: ByteLimit(5))
  assert admitPreimages(prior, source, exact).error == PreimageTransitionError.None
  for mode in 0..<3:
    var small = exact
    case mode
    of 0: small.items = ElementLimit(3) # Descriptor/traversal budget.
    of 1: small.perBlob = ByteLimit(2) # The later three-octet payload fails before hashing anything.
    else: small.totalBlobBytes = ByteLimit(4) # Aggregate payload charging uses subtraction.
    failHash(1)
    assert admitPreimages(prior, source, small).error == PreimageTransitionError.LimitExceeded
    failHash(0)
  assert admitPreimages(prior, default(OwnedFrame), config()).error ==
      PreimageTransitionError.InvalidInput
  assert admitPreimages(prior, decodeOwnedBytes(@[0'u8], ByteLimit(1)).value, config()).error ==
      PreimageTransitionError.InvalidInput
  assert admitPreimages(default(StateStoreSnapshot), frame([]), config()).error ==
      PreimageTransitionError.InvalidState
  let empty = default(AdmittedPreimages)
  assert empty.preimageInfo.error == PreimageTransitionError.Uninitialized
  assert empty.preimagePrior.error == PreimageTransitionError.Uninitialized
  assert empty.preimageSource.error == PreimageTransitionError.Uninitialized
  assert empty.provisionAt(ProvisionIndex(0)).error == PreimageTransitionError.Uninitialized
  var target = state
  assert integratePreimages(target, empty, HeaderSlot(0)).error ==
      PreimageTransitionError.Uninitialized
  var invalid = default(StateStore)
  assert integratePreimages(invalid, plan, HeaderSlot(0)).error ==
      PreimageTransitionError.InvalidState
  result = plan

## Distinguish missing/nonempty requests from malformed present state without accepting orphan request keys.
proc malformed() =
  let item: Item = Item(service: 42'u32, blob: @[7'u8, 8, 9])
  let raw = entries([item])
  let req = request(item)
  let input = frame([item])
  let base = newStateStore(raw, storeLimits()).value
  for mode in 0..<2:
    var missing = base
    let key = if mode == 0: chapterServiceKey(StateChapter(255), ServiceIndex(
        42)) else: req.key # Missing account versus absent request.
    discard missing.apply([StateWrite(key: key, kind: StateWriteKind.Delete)]).value
    assert admitPreimages(missing.snapshot.value, input, config()).error ==
        PreimageTransitionError.NotRequested
  # Each valid nonempty history means supplied data is not currently outstanding.
  for history in [availableHistory(RequestSlot(1)), unavailableHistory(RequestSlot(1), RequestSlot(
      2)), reavailableHistory(RequestSlot(1), RequestSlot(2), RequestSlot(3))]:
    var current = base
    let entry = request(item, history)
    discard current.apply([StateWrite(key: entry.key, kind: StateWriteKind.Put,
        value: entry.value)]).value
    assert admitPreimages(current.snapshot.value, input, config()).error ==
        PreimageTransitionError.NotRequested
  # Empty/truncated/overlong/count-invalid histories cannot masquerade as Requested.
  for value in [newSeq[byte](0), @[0'u8, 0], @[128'u8, 0], @[1'u8], @[4'u8], newSeq[byte](14)]:
    var current = base
    discard current.apply([StateWrite(key: req.key, kind: StateWriteKind.Put, value: value)]).value
    assert admitPreimages(current.snapshot.value, input, config()).error ==
        PreimageTransitionError.MalformedState
  for mode in 0..<2:
    var current = base
    var value = newSeq[byte](89)
    if mode == 0: value.setLen(88) # Exact account metadata width is mandatory.
    else: value[0] = 1 # Unknown account schema version.
    discard current.apply([StateWrite(key: chapterServiceKey(StateChapter(255), ServiceIndex(42)),
        kind: StateWriteKind.Put, value: value)]).value
    assert admitPreimages(current.snapshot.value, input, config()).error ==
        PreimageTransitionError.MalformedState

## Post-accumulation cancellation/deletion ignores no-longer-needed data but retains all admission statistics.
proc phaseBoundary() =
  let item: Item = Item(service: 42'u32, blob: @[7'u8, 8, 9])
  let base = newStateStore(entries([item]), storeLimits()).value
  let req = request(item)
  let plan = admitPreimages(base.snapshot.value, frame([item]), config()).value
  # Deleted accounts, dropped requests and fulfilled histories all cease to satisfy fnprovidable.
  for mode in 0..<3:
    var current = base
    let entry = request(item, availableHistory(RequestSlot(1)))
    let write = if mode == 0: StateWrite(key: chapterServiceKey(StateChapter(255), ServiceIndex(
        42)), kind: StateWriteKind.Delete)
      elif mode == 1: StateWrite(key: req.key, kind: StateWriteKind.Delete)
      else: StateWrite(key: req.key, kind: StateWriteKind.Put,
          value: entry.value) # A separately changed working state is intentional.
    discard current.apply([write]).value
    let before = current.snapshot.value
    failHash(1)
    let applied = integratePreimages(current, plan, HeaderSlot(99))
    assert applied.error == PreimageTransitionError.None
    same(applied.value, before) # No relevant writes require no root/hash computation.
    failHash(0)
    assert uint64(plan.provisionAt(ProvisionIndex(0)).value.count) == 1
    assert uint64(plan.provisionAt(ProvisionIndex(0)).value.bytes) == 3
  var current = base
  let before = current.snapshot.value
  let completed = integratePreimages(current, plan, HeaderSlot(high(uint32))).value
  let decoded = decodeRequestHistory(completed.lookup(req.key).value.bytes,
    RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13))).value.history
  assert decoded.state == RequestState.Available and uint32(decoded.since) == high(uint32)
  same(plan.preimagePrior.value, before)
  let repeat = integratePreimages(current, plan, HeaderSlot(0)).value
  same(repeat, completed) # An already fulfilled request is not overwritten with another supplied slot.

## All hash, late-root, store-policy and malformed-post-state refusals leave the target map unchanged.
proc rollback() =
  let item: Item = Item(service: 42'u32, blob: @[7'u8, 8, 9])
  let raw = entries([item])
  let base = newStateStore(raw, storeLimits()).value
  let source = frame([item])
  let before = base.snapshot.value
  let plan = admitPreimages(before, source, config()).value
  # Admission hash and request-namespace hash failures remain backend refusals rather than NotRequested.
  for successful in 0..1:
    hashAfter(cint(successful))
    assert admitPreimages(before, source, config()).error == PreimageTransitionError.BackendFailure
    failHash(0)
  # The first two integration hashes derive namespaces; rejecting the next hash exercises root rollback.
  for successful in 0..2:
    var current = base
    hashAfter(cint(successful))
    assert integratePreimages(current, plan, HeaderSlot(10)).error ==
        PreimageTransitionError.BackendFailure
    failHash(0)
    same(current.snapshot.value, before)
  for mode in 0..<3:
    var bounds = storeLimits()
    case mode
    of 0: bounds.writes = ElementLimit(1) # Two updates must publish together.
    of 1: bounds.writeValueBytes = ByteLimit(7) # Three raw blob bytes plus five history bytes require eight.
    else: bounds.trie.nodes = TrieNodeLimit(before.commitment.nodes) # A new lookup leaf grows the exact trie topology.
    var current = newStateStore(raw, bounds).value
    assert integratePreimages(current, plan, HeaderSlot(10)).error ==
        PreimageTransitionError.LimitExceeded
    same(current.snapshot.value, before)
  let pair: seq[Item] = @[item, Item(service: 43'u32, blob: @[9'u8])]
  var current = newStateStore(entries(pair), storeLimits()).value
  let both = admitPreimages(current.snapshot.value, frame(pair), config()).value
  let bad = request(pair[1])
  discard current.apply([StateWrite(key: bad.key, kind: StateWriteKind.Put, value: @[1'u8])]).value
  let changed = current.snapshot.value
  assert integratePreimages(current, both, HeaderSlot(10)).error ==
      PreimageTransitionError.MalformedState
  same(current.snapshot.value, changed) # A later malformed request cannot publish earlier staged writes.

## Successful and refused admissions/publications release all retained buffers and map candidates.
proc lifetime() =
  let item: Item = Item(service: 42'u32, blob: @[7'u8, 8, 9])
  let state = newStateStore(entries([item]), storeLimits()).value
  let source = frame([item])
  let duplicate = frame([item, item])
  let plan = admitPreimages(state.snapshot.value, source, config()).value
  var warm = state
  discard integratePreimages(warm, plan, HeaderSlot(10))
  discard admitPreimages(state.snapshot.value, duplicate, config())
  let before = getOccupiedMem()
  for i in 0..<1000:
    var current = state
    let admitted = admitPreimages(state.snapshot.value, source, config()).value
    assert integratePreimages(current, admitted, HeaderSlot(10)).error ==
        PreimageTransitionError.None
    assert admitPreimages(state.snapshot.value, duplicate, config()).error ==
        PreimageTransitionError.NotOrderedUnique
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("preimage_transition", 1000, before, after)

## Run the complete focused suite and retain captured sources beyond construction scopes.
proc main() {.raises.} =
  published()
  let retained = boundaries()
  assert uint32(retained.preimageSource.value.ownedService(0).value) == 0
  malformed()
  phaseBoundary()
  rollback()
  lifetime()
  echo "PASS preimage transition: published projections, phase checks, atomic rollback and ARC"
try:
  main() # Execute through the pinned native Hastur runner.
except:
  quit(2) # Fixture transport and unexpected exceptions remain failing processes.
