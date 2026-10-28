# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_authorization_arc_release"}

## Genuine signed source histories bind pool use, posterior queue indexing and exact private complete-map publication.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_authorization as state_accumulation_authorization
import ../../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../../src/state/accumulation_activity as state_accumulation_activity
import ../../../src/state/accumulation_validators as state_accumulation_validators
import ../../../src/state/core_service_activity as state_core_service_activity
import ../../../src/state/preimages as state_preimages
import ../../../src/state/authorization as state_authorization
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_authorization as codec_state_authorization
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/crypto/primitives as crypto_primitives
import ../../support/state_accumulation_activity_context
import ../../support/state_accumulation_provision_integration
import ../../support/state_report_context
import ../../support/testing_arc_evidence

# Faults start only after every genuine signature, guest and earlier private candidate already exists.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

proc limits(): AccumulationAuthorizationLimits =
  ## Per-input limits admit fixed queues separately from the much smaller output pools.
  AccumulationAuthorizationLimits(guarantees: ElementLimit(2), inputHashes: ElementLimit(160),
    inputBytes: ByteLimit(5121), outputHashes: ElementLimit(16), outputBytes: ByteLimit(514))

proc lookup(source: PreparedAccumulationValidators): PreparedAccumulationPreimages =
  ## Prepare preceding stages through public APIs without replacing or forging their authority.
  let activity = prepareAccumulationActivity(source, AccumulationActivityConfig(
    componentBytes: ByteLimit(1024), preimages: PreimageLimits(items: ElementLimit(3),
      perBlob: ByteLimit(3), totalBlobBytes: ByteLimit(4)), incoming: ElementLimit(2),
    available: ElementLimit(1), digests: ElementLimit(2), assurances: ElementLimit(5),
    provisions: ElementLimit(2), accumulation: ElementLimit(2), services: ElementLimit(2),
    activityBytes: ByteLimit(4096))).value
  prepareAccumulationPreimages(activity, AccumulationPreimageLimits(items: ElementLimit(3),
    bytes: ByteLimit(4))).value

proc marker(value: byte): AuthorizerHash =
  ## Simple opaque nonzero hashes make cyclic queue positions and pool order distinguishable.
  var bytes = default(array[32, byte])
  bytes[0] = value
  AuthorizerHash(bytes: bytes)

proc queues(): seq[byte] =
  ## Literal fixed C(2) framing has no core/row counts; every position is distinct within its core.
  result = @[]
  for core in 0..<2:
    for index in 0..<80:
      result.add(byte(1+100*core+index))
      for octet in 1..<32: result.add(0) # Exactly 32 opaque octets per queue item.

proc pools(base: OwnedReport, mode: int): seq[AuthorizerRow] =
  ## All guaranteed cores contain the actual authorizer, including two occurrences in the first full pool.
  let used = base.ownedReportInfo.value.authorizer
  case mode
  of 1:
    result = @[@[used, marker(201), used, marker(202), marker(203), marker(204), marker(205),
        marker(206)],
      @[marker(206), marker(205), marker(204), marker(203), marker(202), marker(201), used, marker(207)]]
  of 2: result = @[newSeq[AuthorizerHash](), newSeq[AuthorizerHash]()] # Empty pools are valid only without incoming guarantees.
  else: result = @[@[used], @[used]] # Default singleton used pools retain their original order.

proc expected(base: OwnedReport, mode, uses: int, slot: uint32): seq[byte] =
  ## Hand-authored final pool sequences freeze subtraction/truncation without invoking the production projector.
  let used = base.ownedReportInfo.value.authorizer
  var rows: seq[AuthorizerRow] = @[]
  case mode
  of 1:
    if uses == 2:
      rows = @[@[marker(201), used, marker(202), marker(203), marker(204), marker(205), marker(
          206)],
        @[marker(206), marker(205), marker(204), marker(203), marker(202), marker(201), marker(207)]]
    else:
      rows = @[@[marker(201), used, marker(202), marker(203), marker(204), marker(205), marker(
          206)],
        @[marker(205), marker(204), marker(203), marker(202), marker(201), used, marker(
            207)]] # No-use full pools drop only the oldest element.
  of 2: rows = @[newSeq[AuthorizerHash](), newSeq[AuthorizerHash]()]
  else: rows = if uses == 2: @[newSeq[AuthorizerHash](), newSeq[AuthorizerHash]()]
    else: @[@[used], @[used]] # Newly available reports never count as incoming guarantee use.
  result = @[]
  for core in 0..<2:
    rows[core].add(marker(byte(1+100*core+int(slot mod 80))))
    result.add(byte(rows[core].len)) # Each 1..8 count is one literal canonical natural byte.
    for hash in rows[core]:
      for octet in hash.bytes: result.add(octet) # No outer core count prefix is present.

proc valueEntry(service: uint32, bytes: seq[byte]): StateEntry =
  ## Existing namespace primitives derive keys; raw values and full-map enumeration remain independent.
  let hash = ServicePreimageHash(array[32, byte](blake2b256(bytes).value))
  servicePreimageEntry(ServiceIndex(service), hash, bytes,
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(bytes.len)))).value

proc oracle(fixture: ActivityFixture, prior: StateStoreSnapshot, bytes: seq[byte],
    blobs, provided: bool): StateStoreSnapshot =
  ## Enumerate every known source key and replace only the independently framed C(1) entry.
  var entries: seq[StateEntry] = @[]
  for original in fixture.entries:
    let value = if array[31, byte](original.key) == array[31, byte](chapterKey(StateChapter(1))):
      bytes else: prior.lookup(original.key).value.bytes
    entries.add(StateEntry(key: original.key, value: value))
  entries.add(StateEntry(key: chapterKey(StateChapter(16)),
    value: prior.lookup(chapterKey(StateChapter(16))).value.bytes)) # Finalization added this originally absent chapter.
  if blobs:
    for entry in [valueEntry(42, @[73'u8]), valueEntry(99, @[]), valueEntry(99, @[81'u8, 82, 83])]:
      entries.add(StateEntry(key: entry.key, value: prior.lookup(
          entry.key).value.bytes)) # Lookup integration already supplied these values.
  if provided:
    entries.add(valueEntry(99, @[81'u8])) # The earlier guest's independent provision remains present.
  assert entries.len == prior.commitment.entries, "known source keys exhaust the complete mapping"
  newStateStore(entries, state_report_context.limits()).value.snapshot.value

proc witness(base: OwnedReport, mode = 0, uses = 0, slot = 2'u32, available = false,
    blobs = false, provided = false): PreparedAccumulationAuthorization =
  ## Exact entry and full-map comparisons preserve every prior chapter, metadata, request and preimage byte.
  let fixture = activityFixture(base, guarantees = uses, slot = slot, available = available,
    blobs = blobs, provided = provided, parentPools = pools(base, mode),
        authorizationQueue = queues())
  let source = lookup(fixture.source)
  let prior = source.accumulationPreimagesState.value
  let bytes = expected(base, mode, uses, slot)
  let independent = oracle(fixture, prior, bytes, blobs, provided)
  let resultOwner = prepareAccumulationAuthorization(source, limits())
  assert resultOwner.error == AccumulationAuthorizationError.None
  result = resultOwner.value
  let state = result.accumulationAuthorizationState.value
  let entry = result.accumulationAuthorizationEntry.value
  assert array[31, byte](entry.key) == array[31, byte](chapterKey(StateChapter(1)))
  assert entry.value == bytes
  assert state.lookup(entry.key).value.bytes == bytes
  assert array[32, byte](state.commitment.root) == array[32, byte](independent.commitment.root)
  assert state.commitment.entries == prior.commitment.entries
  assert sameStateSnapshot(prior, result.accumulationAuthorizationSource.value.accumulationPreimagesState.value)
  assert not sameStateSnapshot(prior, state), "private pool candidate owns its successor"
  for number in [2'u8, 3, 13, 14, 15, 16, 250]:
    let key = chapterKey(StateChapter(number))
    assert state.lookup(key).value.bytes == prior.lookup(key).value.bytes, "all earlier chapters survive"
  let facts = result.accumulationAuthorizationInfo.value
  assert uint32(facts.slot) == slot and uint64(facts.cores) == 2 and facts.guarantees == uses
  assert facts.encodedBytes == bytes.len
  let again = prepareAccumulationAuthorization(source, limits()).value.accumulationAuthorizationState.value
  assert array[32, byte](again.commitment.root) == array[32, byte](state.commitment.root)

proc policies(source: PreparedAccumulationPreimages) =
  ## Independent input/output ceilings preserve selected reasons and reject before private hashing.
  for mode in 0..<5:
    var short = limits()
    case mode
    of 0: short.guarantees = ElementLimit(1)
    of 1: short.inputBytes = ByteLimit(5119)
    of 2: short.inputHashes = ElementLimit(159)
    of 3: short.outputHashes = ElementLimit(1)
    else: short.outputBytes = ByteLimit(65)
    failHash(1)
    let refused = prepareAccumulationAuthorization(source, short)
    case mode
    of 0, 1: assert refused.error == AccumulationAuthorizationError.LimitExceeded
    of 2:
      assert refused.error == AccumulationAuthorizationError.CodecFailure
      assert refused.codecError == AuthorizationError.LimitExceeded
    else:
      assert refused.error == AccumulationAuthorizationError.AuthorizationFailure
      assert refused.authorizationError == AuthorizationTransitionError.LimitExceeded
    assert hashCalls() == 0
  failHash(0)
  var exact = limits()
  exact.inputBytes = ByteLimit(5120)
  exact.outputHashes = ElementLimit(2)
  exact.outputBytes = ByteLimit(66)
  assert prepareAccumulationAuthorization(source, exact).error ==
      AccumulationAuthorizationError.None
  let full = AccumulationAuthorizationLimits(guarantees: ElementLimit(high(uint64)),
    inputHashes: ElementLimit(high(uint64)), inputBytes: ByteLimit(high(uint64)),
    outputHashes: ElementLimit(high(uint64)), outputBytes: ByteLimit(high(uint64)))
  assert prepareAccumulationAuthorization(source, full).error == AccumulationAuthorizationError.None

proc malformed(base: OwnedReport) =
  ## Earlier stages need not inspect C(2) in an idle history; this stage refuses exact latent chapter defects.
  for mode in 0..<3:
    var bytes = queues()
    if mode == 0: bytes.setLen(bytes.len-1) # The fixed queue is truncated by one octet.
    if mode == 1: bytes.add(0) # A valid prefix with trailing bytes is not a canonical whole chapter.
    let source = lookup(activityFixture(base, parentPools = pools(base, 0),
      authorizationQueue = bytes, omitAuthorizationQueue = mode == 2).source)
    failHash(1)
    let refused = prepareAccumulationAuthorization(source, limits())
    if mode == 2:
      assert refused.error == AccumulationAuthorizationError.StateFailure
      assert refused.stateError == StateStoreError.MissingKey
    else:
      assert refused.error == AccumulationAuthorizationError.CodecFailure
      assert refused.codecError == (if mode == 0: AuthorizationError.Truncated else: AuthorizationError.NonCanonical)
    assert hashCalls() == 0
    failHash(0)

proc backend(source: PreparedAccumulationPreimages) =
  ## A failed first/final Merkle hash cannot alter original pools or the exact retained posterior map.
  let prior = source.accumulationPreimagesState.value
  let key = chapterKey(StateChapter(1))
  let original = prior.lookup(key).value.bytes
  let root = array[32, byte](prior.commitment.root)
  failHash(0)
  discard prepareAccumulationAuthorization(source, limits()).value
  let total = hashCalls()
  assert total > 1
  for after in [0.cint, total-1]:
    failAfter(after)
    let refused = prepareAccumulationAuthorization(source, limits())
    assert refused.error == AccumulationAuthorizationError.StateFailure
    assert refused.stateError == StateStoreError.BackendFailure
    assert prior.lookup(key).value.bytes == original
    assert array[32, byte](source.accumulationPreimagesState.value.commitment.root) == root
  failHash(0)
  assert prepareAccumulationAuthorization(source, limits()).error ==
      AccumulationAuthorizationError.None

proc cycle(source: PreparedAccumulationPreimages) =
  ## Scoped successful/private failed owners release every new map and encoding before the next cycle.
  failHash(0)
  let candidate = prepareAccumulationAuthorization(source, limits()).value
  assert candidate.accumulationAuthorizationInfo.value.guarantees == 2
  let total = hashCalls()
  failAfter(0)
  assert prepareAccumulationAuthorization(source, limits()).stateError ==
      StateStoreError.BackendFailure
  failAfter(total-1)
  assert prepareAccumulationAuthorization(source, limits()).stateError ==
      StateStoreError.BackendFailure
  failHash(0)

proc main() {.raises.} =
  ## Static report bytes feed genuine source constructors, signed blocks and real prior guest effects.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  discard witness(base)
  discard witness(base, uses = 2)
  discard witness(base, available = true)
  discard witness(base, mode = 1, uses = 2, blobs = true, provided = true, available = true)
  discard witness(base, mode = 1)
  discard witness(base, mode = 2)
  for slot in [79'u32, 80, 81]: discard witness(base,
      slot = slot) # Last, first and second cyclic queue positions.
  let source = lookup(activityFixture(base, guarantees = 2, parentPools = pools(base, 0),
    authorizationQueue = queues(), blobs = true).source)
  policies(source)
  malformed(base)
  backend(source)
  failHash(1)
  assert prepareAccumulationAuthorization(default(PreparedAccumulationPreimages), limits()).error ==
      AccumulationAuthorizationError.InvalidSource
  assert hashCalls() == 0
  failHash(0)
  let empty = default(PreparedAccumulationAuthorization)
  assert empty.accumulationAuthorizationSource.error == AccumulationAuthorizationError.Uninitialized
  assert empty.accumulationAuthorizationInfo.error == AccumulationAuthorizationError.Uninitialized
  assert empty.accumulationAuthorizationEntry.error == AccumulationAuthorizationError.Uninitialized
  assert empty.accumulationAuthorizationState.error == AccumulationAuthorizationError.Uninitialized
  var retained = default(PreparedAccumulationAuthorization)
  block:
    let local = lookup(activityFixture(base, guarantees = 2, parentPools = pools(base, 0),
      authorizationQueue = queues()).source)
    retained = prepareAccumulationAuthorization(local, limits()).value
  var entry = retained.accumulationAuthorizationEntry.value
  entry.value[0] = 0
  assert retained.accumulationAuthorizationEntry.value.value == expected(base, 0, 2, 2)
  var facts = retained.accumulationAuthorizationInfo.value
  facts.guarantees = 99
  assert retained.accumulationAuthorizationInfo.value.guarantees == 2
  let detached = retained.accumulationAuthorizationState.value
  retained = default(PreparedAccumulationAuthorization)
  assert detached.lookup(chapterKey(StateChapter(1))).value.bytes == expected(base, 0, 2, 2)
  cycle(source)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(source) # Fixed genuine source; all derived owners are scoped.
  let after = getOccupiedMem()
  assert before == after, "source-bound authorization ARC release"
  recordArcRelease("state_accumulation_authorization", 1000, before, after)
  echo "Accumulation-bound authorization passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O failures remain strict native failures.
except:
  quit(2)
