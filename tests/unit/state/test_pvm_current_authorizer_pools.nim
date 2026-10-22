# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_authorizer_pools_arc_release"}

## Genuine signed source histories bind pool use, posterior queue indexing and exact private complete-map publication.

import std/[assertions, envvars, syncio]
import ../../../src/state/[accumulation_current_authorization, accumulation_authorization,
  accumulation_current_preimages, accumulation_preimages, accumulation_current_activity,
  accumulation_activity, accumulation_current_validators, accumulation_current_driver,
  accumulation_current_round, core_service_activity, preimages, authorization, store]
import ../../../src/codec/[bounded, composite, header, report_owned, state_authorization,
  state_layout, state_trie, state_accounts, state_service_values]
import ../../../src/crypto/primitives
import ../../support/[accumulation_current_activity_context, accumulation_activity_context,
  accumulation_execution_context,
  accumulation_current_round_context, accumulation_current_driver_context,
  accumulation_provision_integration,
  report_context, arc_evidence]

# Faults start only after every genuine signature, guest and earlier private candidate already exists.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

proc limits(): AccumulationAuthorizationLimits =
  ## Per-input limits admit fixed queues separately from the much smaller output pools.
  AccumulationAuthorizationLimits(guarantees: ElementLimit(2), inputHashes: ElementLimit(160),
    inputBytes: ByteLimit(5121), outputHashes: ElementLimit(16), outputBytes: ByteLimit(514))

proc lookup(source: PreparedCurrentAccumulationValidators): PreparedCurrentAccumulationPreimages =
  ## Prepare preceding stages through public APIs without replacing or forging their authority.
  let activity = prepareCurrentAccumulationActivity(source, AccumulationActivityConfig(
    componentBytes: ByteLimit(1024), preimages: PreimageLimits(items: ElementLimit(3),
      perBlob: ByteLimit(3), totalBlobBytes: ByteLimit(4)), incoming: ElementLimit(2),
    available: ElementLimit(1), digests: ElementLimit(2), assurances: ElementLimit(5),
    provisions: ElementLimit(2), accumulation: ElementLimit(2), services: ElementLimit(2),
    activityBytes: ByteLimit(4096))).value
  prepareCurrentAccumulationPreimages(activity, AccumulationPreimageLimits(items: ElementLimit(3),
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

proc oracle(fixture: CurrentActivityFixture, prior: StateStoreSnapshot, bytes: seq[byte],
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
  newStateStore(entries, report_context.limits()).value.snapshot.value

proc witness(base: OwnedReport, mode = 0, uses = 0, slot = 2'u32, available = false,
    blobs = false, provided = false): PreparedCurrentAccumulationAuthorization =
  ## Exact entry and full-map comparisons preserve every prior chapter, metadata, request and preimage byte.
  let fixture = currentActivityFixture(base, guarantees = uses, slot = slot, available = available,
    blobs = blobs, provided = provided, parentPools = pools(base, mode),
        authorizationQueue = queues())
  let source = lookup(fixture.source)
  let prior = source.currentPreimagesState.value
  let bytes = expected(base, mode, uses, slot)
  let independent = oracle(fixture, prior, bytes, blobs, provided)
  let resultOwner = prepareCurrentAccumulationAuthorization(source, limits())
  assert resultOwner.error == CurrentAccumulationAuthorizationError.None
  result = resultOwner.value
  let state = result.currentAuthorizationState.value
  let entry = result.currentAuthorizationEntry.value
  assert array[31, byte](entry.key) == array[31, byte](chapterKey(StateChapter(1)))
  assert entry.value == bytes
  assert state.lookup(entry.key).value.bytes == bytes
  assert array[32, byte](state.commitment.root) == array[32, byte](independent.commitment.root)
  assert state.commitment.entries == prior.commitment.entries
  assert sameStateSnapshot(prior, result.currentAuthorizationSource.value.currentPreimagesState.value)
  assert not sameStateSnapshot(prior, state), "private pool candidate owns its successor"
  for number in [2'u8, 3, 13, 14, 15, 16, 250]:
    let key = chapterKey(StateChapter(number))
    assert state.lookup(key).value.bytes == prior.lookup(key).value.bytes, "all earlier chapters survive"
  let facts = result.currentAuthorizationInfo.value
  assert uint32(facts.slot) == slot and uint64(facts.cores) == 2 and facts.guarantees == uses
  assert facts.encodedBytes == bytes.len
  let again = prepareCurrentAccumulationAuthorization(source, limits()).value.currentAuthorizationState.value
  assert array[32, byte](again.commitment.root) == array[32, byte](state.commitment.root)

proc policies(source: PreparedCurrentAccumulationPreimages) =
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
    let refused = prepareCurrentAccumulationAuthorization(source, short)
    case mode
    of 0, 1: assert refused.error == CurrentAccumulationAuthorizationError.LimitExceeded
    of 2:
      assert refused.error == CurrentAccumulationAuthorizationError.CodecFailure
      assert refused.codecError == AuthorizationError.LimitExceeded
    else:
      assert refused.error == CurrentAccumulationAuthorizationError.AuthorizationFailure
      assert refused.authorizationError == AuthorizationTransitionError.LimitExceeded
    assert hashCalls() == 0
  failHash(0)
  var exact = limits()
  exact.inputBytes = ByteLimit(5120)
  exact.outputHashes = ElementLimit(2)
  exact.outputBytes = ByteLimit(66)
  assert prepareCurrentAccumulationAuthorization(source, exact).error ==
      CurrentAccumulationAuthorizationError.None
  let full = AccumulationAuthorizationLimits(guarantees: ElementLimit(high(uint64)),
    inputHashes: ElementLimit(high(uint64)), inputBytes: ByteLimit(high(uint64)),
    outputHashes: ElementLimit(high(uint64)), outputBytes: ByteLimit(high(uint64)))
  assert prepareCurrentAccumulationAuthorization(source, full).error ==
      CurrentAccumulationAuthorizationError.None

proc malformed(base: OwnedReport) =
  ## Current idle global phases already require canonical C2; no artificial later source bypasses that stronger boundary.
  for mode in 0..<3:
    var bytes = queues()
    if mode == 0: bytes.setLen(bytes.len-1) # Truncated fixed queue refuses before current ownership.
    if mode == 1: bytes.add(0) # Exact whole C2 consumption excludes trailing octets.
    let options = activityOptions(parentPools = pools(base, 0), authorizationQueue = bytes,
      omitAuthorizationQueue = mode == 2)
    let fixture = executionFixture(base, options)
    failHash(1)
    let refused = runCurrentBlockAccumulationSequence(fixture.round, currentRoundParameters(),
        currentSequenceDriverLimits())
    assert refused.error == CurrentSequenceDriverError.InitialFailure
    assert refused.initialFailure.error == CurrentAccumulationRoundError.GlobalFailure
    assert hashCalls() == 0, "malformed C2 cannot authorize private current state writes"
    failHash(0)

proc backend(source: PreparedCurrentAccumulationPreimages) =
  ## A failed first/final Merkle hash cannot alter original pools or the exact retained posterior map.
  let prior = source.currentPreimagesState.value
  let key = chapterKey(StateChapter(1))
  let original = prior.lookup(key).value.bytes
  let root = array[32, byte](prior.commitment.root)
  failHash(0)
  discard prepareCurrentAccumulationAuthorization(source, limits()).value
  let total = hashCalls()
  assert total > 1
  for after in [0.cint, total-1]:
    failAfter(after)
    let refused = prepareCurrentAccumulationAuthorization(source, limits())
    assert refused.error == CurrentAccumulationAuthorizationError.StateFailure
    assert refused.stateError == StateStoreError.BackendFailure
    assert prior.lookup(key).value.bytes == original
    assert array[32, byte](source.currentPreimagesState.value.commitment.root) == root
  failHash(0)
  assert prepareCurrentAccumulationAuthorization(source, limits()).error ==
      CurrentAccumulationAuthorizationError.None

proc cycle(source: PreparedCurrentAccumulationPreimages) =
  ## Scoped successful/private failed owners release every new map and encoding before the next cycle.
  failHash(0)
  let candidate = prepareCurrentAccumulationAuthorization(source, limits()).value
  assert candidate.currentAuthorizationInfo.value.guarantees == 2
  let total = hashCalls()
  failAfter(0)
  assert prepareCurrentAccumulationAuthorization(source, limits()).stateError ==
      StateStoreError.BackendFailure
  failAfter(total-1)
  assert prepareCurrentAccumulationAuthorization(source, limits()).stateError ==
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
  let source = lookup(currentActivityFixture(base, guarantees = 2, parentPools = pools(base, 0),
    authorizationQueue = queues(), blobs = true).source)
  policies(source)
  malformed(base)
  backend(source)
  failHash(1)
  let invalid = prepareCurrentAccumulationAuthorization(default(
      PreparedCurrentAccumulationPreimages), limits())
  assert invalid.error == CurrentAccumulationAuthorizationError.InvalidSource
  assert hashCalls() == 0
  failHash(0)
  let empty = default(PreparedCurrentAccumulationAuthorization)
  assert empty.currentAuthorizationSource.error ==
      CurrentAccumulationAuthorizationError.Uninitialized
  assert empty.currentAuthorizationInfo.error == CurrentAccumulationAuthorizationError.Uninitialized
  assert empty.currentAuthorizationEntry.error == CurrentAccumulationAuthorizationError.Uninitialized
  assert empty.currentAuthorizationState.error == CurrentAccumulationAuthorizationError.Uninitialized
  var retained = default(PreparedCurrentAccumulationAuthorization)
  block:
    let local = lookup(currentActivityFixture(base, guarantees = 2, parentPools = pools(base, 0),
      authorizationQueue = queues()).source)
    retained = prepareCurrentAccumulationAuthorization(local, limits()).value
  var entry = retained.currentAuthorizationEntry.value
  entry.value[0] = 0
  assert retained.currentAuthorizationEntry.value.value == expected(base, 0, 2, 2)
  var facts = retained.currentAuthorizationInfo.value
  facts.guarantees = 99
  assert retained.currentAuthorizationInfo.value.guarantees == 2
  let detached = retained.currentAuthorizationState.value
  retained = default(PreparedCurrentAccumulationAuthorization)
  assert detached.lookup(chapterKey(StateChapter(1))).value.bytes == expected(base, 0, 2, 2)
  cycle(source)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(source) # Fixed genuine source; all derived owners are scoped.
  let after = getOccupiedMem()
  assert before == after, "source-bound authorization ARC release"
  recordArcRelease("pvm_current_authorizer_pools", 1000, before, after)
  echo "PVM current authorizer pools passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O failures remain strict native failures.
except:
  quit(2)
