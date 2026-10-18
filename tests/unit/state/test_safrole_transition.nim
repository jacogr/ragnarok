# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute every Safrole substep from actual pinned parent chapters and signed headers, with atomic rollback.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/[safrole_transition, store, validator_state, ticket_admission,
  sealer_schedule, safrole_markers, safrole_authentication, entropy]
import ../../../src/codec/[state_safrole, state_consensus, state_disputes, state_layout,
  state_trie, header, tickets, bounded]
from ../../../src/codec/disputes import OffenderKey
import ../../support/[validator_rotation_fixture, arc_evidence]

## Reset ordinary/ring/setup observation between fully retired calls.
proc reset(flags: cint) {.importc: "bo_reset", cdecl.}
## Refuse the first or second ordinary verification after all preceding private stages.
proc refuseVerification(successful: cint) {.importc: "bo_ietf_after", cdecl.}
## Prove both seal and entropy credentials ran on successful paths.
proc verifications(): cint {.importc: "bo_ietf_calls", cdecl.}
## Native setups must be released after success and every refusal.
proc liveSetups(): cint {.importc: "bo_live_setups", cdecl.}
## Reset/refuse Blake hashes independently of Bandersnatch verification.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Count hashing to target early and late atomic publication failure.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
## Refuse after a known successful hash prefix, without replacing any successful digest.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

## Trusted fixture hexadecimal is exact; '-' represents an empty submitted batch.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty tickets are still an explicit fixture field.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    assert parseHex(text[2*i..2*i+1], result[i]) == 2 # Each trusted octet is complete.

## Tiny chain constants and independent local byte/count ceilings are never inferred from the header.
proc policy(): SafroleTransitionConfig =
  SafroleTransitionConfig(state: SafroleStateConfig(validators: rotationRosterConfig(2),
    epochSlots: EpochSlots(12), maxAccumulator: ElementLimit(12), maxBytes: ByteLimit(100000)),
    tailStart: EpochSlots(10), blockTickets: TicketLimit(3), offenders: ElementLimit(100),
    maxHeaderBytes: ByteLimit(100000), maxMarkerBytes: ByteLimit(100000))

## Complete projected maps include unrelated opaque data and unchanged staging alongside all changed chapters.
proc limits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(10), perValue: ByteLimit(100000),
    totalValueBytes: ByteLimit(1000000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(5), writeValueBytes: ByteLimit(500000))

## Header decoding independently checks full consumption and the tiny structural population ceiling.
proc capture(raw: seq[byte]): OwnedHeader =
  let decoded = decodeHeader(raw, HeaderConfig(cores: CoreCount(2),
      authorValidators: ValidatorCount(6),
    epochSlots: EpochSlots(12), maxBytes: ByteLimit(100000)))
  assert decoded.error == HeaderError.None and decoded.value.consumed == raw.len
  decoded.value.owner

## Decode trusted ticket transport without a transition algorithm or fabricated proof output.
proc tickets(raw: seq[byte]): seq[Ticket] =
  assert raw.len mod 785 == 0
  result = newSeq[Ticket](raw.len div 785)
  for i in 0..<result.len:
    result[i].attempt = TicketAttempt(raw[i*785]) # Literal E1 attempts precede exact 784-byte proofs.
    var proof = default(array[784, byte])
    for j in 0..<784: proof[j] = raw[i*785+1+j] # No proof truncation or padding.
    result[i].proof = TicketProof(proof)

## Posterior offender identities are supplied from the published disputes chapter, not guessed from markers.
proc offenders(raw: seq[byte]): seq[OffenderKey] =
  let decoded = decodeDisputeState(raw, DisputeStateConfig(perSet: ElementLimit(100),
    totalItems: ElementLimit(400), maxBytes: ByteLimit(100000)))
  assert decoded.error == DisputeStateError.None and decoded.value.consumed == raw.len
  result = newSeq[OffenderKey](disputeStateInfo(decoded.value.snapshot).value.offenders)
  for i in 0..<result.len:
    result[i] = stateOffenderAt(decoded.value.snapshot, DisputeStateIndex(uint64(
        i))).value # Preserve canonical full identities.

## Rollback means every byte and the original commitment survive, not merely the last edited chapter.
proc unchanged(snapshot: StateStoreSnapshot, source: seq[StateEntry], root: StateRoot) =
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](root)
  for entry in source:
    assert snapshot.lookup(entry.key).value.bytes == entry.value # Include C(7) and unrelated sentinel bytes.

## Copy trusted fixture octets before deliberate damage, preserving the input's ownership evidence.
proc altered(raw: seq[byte], position: int): seq[byte] =
  result = newSeq[byte](raw.len)
  for i in 0..<raw.len: result[i] = raw[i] # Never mutate the retained fixture backing sequence.
  result[position] = result[position] xor 1

## One rejected attempt must preserve its own complete starting map/root and release all setup owners.
proc rejected(source: seq[StateEntry], header: OwnedHeader, submitted: seq[Ticket],
    punished: seq[OffenderKey], config: SafroleTransitionConfig,
    budgets: StateStoreLimits): SafroleTransitionResult =
  reset(0)
  failHash(0)
  var state = newStateStore(source, budgets).value
  let parent = state.snapshot.value
  let root = parent.commitment.root
  failHash(0) # Fixture construction is outside the operation's hash preflight evidence.
  result = advanceSafroleState(state, header, submitted, punished, config)
  assert result.error != SafroleTransitionError.None
  unchanged(state.snapshot.value, source, root)
  unchanged(parent, source, root)
  assert liveSetups() == 0

## Missing, truncated and suffixed required parent chapters reject before any authentication.
proc damaged(source: seq[StateEntry], header: OwnedHeader, submitted: seq[Ticket],
    punished: seq[OffenderKey], config: SafroleTransitionConfig) =
  for index in 0..<6:
    for mode in 0..<3:
      var broken: seq[StateEntry] = @[]
      for i, entry in source:
        if i != index:
          broken.add(entry) # Unrelated retained entries preserve every original byte.
        elif mode != 0:
          var bytes = newSeq[byte](entry.value.len+(if mode == 1: -1 else: 1))
          for j in 0..<min(bytes.len, entry.value.len): bytes[j] = entry.value[j] # Exact one-byte shape damage.
          broken.add(StateEntry(key: entry.key, value: bytes))
        else:
          discard # Remove exactly the selected required chapter; no implicit replacement.
      let outcome = rejected(broken, header, submitted, punished, config, limits())
      if index in [0, 1, 5]:
        if mode == 0:
          assert outcome.error == SafroleTransitionError.MissingState # Coordinator retains C(4)/C(6)/C(11) before rotation.
        elif index in [1, 5]:
          assert outcome.error == SafroleTransitionError.InvalidState # Fixed history/time shape is checked before copying.
        else:
          assert outcome.error == SafroleTransitionError.RotationFailure # Exact C(4) decoding belongs to the rotation substep.
      else:
        assert outcome.error == SafroleTransitionError.RotationFailure # C(7)/C(8)/C(9) validation remains in the retained rotation implementation.
      assert verifications() == 0

## Exact/one-short canonical write budgets cannot publish a successful earlier substep.
proc budgets(source: seq[StateEntry], expected: seq[StateEntry], header: OwnedHeader,
    submitted: seq[Ticket], punished: seq[OffenderKey], config: SafroleTransitionConfig) =
  var count = 0
  var bytes = 0'u64
  for entry in expected:
    for original in source:
      if array[31, byte](original.key) == array[31, byte](entry.key) and original.value != entry.value:
        inc count # Count only final changed identities; C(7)/unrelated keys are not written.
        bytes += uint64(entry.value.len)
  assert count >= 2 and bytes >= 132
  # This fixture is same-epoch, so only the final batch consumes write budgets.
  for kind in 0..<2:
    var exact = limits()
    exact.writes = ElementLimit(uint64(count))
    exact.writeValueBytes = ByteLimit(bytes)
    var small = exact
    if kind == 0:
      small.writes = ElementLimit(uint64(count-1)) # No partial prefix can satisfy the missing final write slot.
    else:
      small.writeValueBytes = ByteLimit(bytes-1) # One byte below the whole changed batch must refuse atomically.
    let outcome = rejected(source, header, submitted, punished, config, small)
    assert outcome.error == SafroleTransitionError.PublicationFailure
    assert outcome.publicationError == StateStoreError.LimitExceeded
    assert verifications() == 2
    reset(0)
    failHash(0)
    var accepted = newStateStore(source, exact).value
    assert advanceSafroleState(accepted, header, submitted, punished, config).error ==
        SafroleTransitionError.None

## Preflight ceilings, transcript damage, canonical offenders and real proof failures preserve the whole map.
proc boundaries(source: seq[StateEntry], expected: seq[StateEntry], raw: seq[byte],
    submitted: seq[Ticket], punished: seq[OffenderKey], crossing: bool) =
  let header = capture(raw)
  let config = policy()
  for mode in 0..<5:
    var bad = config
    case mode
    of 0: bad.state.epochSlots = EpochSlots(0) # Zero epochs cannot reach division or rotation.
    of 1: bad.tailStart = bad.state.epochSlots # The closing period must start strictly within an epoch.
    of 2: bad.maxHeaderBytes = ByteLimit(uint64(raw.len-1)) # Complete signed header ceiling is checked before native work.
    of 3: bad.state.maxBytes = ByteLimit(uint64(source[0].value.len-1)) # Parent C(4) pre-copy refusal.
    else: bad.state.validators.maxBytes = ByteLimit(1) # Roster bytes must fit before native setup.
    let outcome = rejected(source, header, submitted, punished, bad, limits())
    assert outcome.error in [SafroleTransitionError.InvalidConfig,
      SafroleTransitionError.LimitExceeded,
      SafroleTransitionError.RotationFailure]
    assert verifications() == 0 and hashes() == 0 # Every policy refusal precedes rotation/root/authentication work.
  let invalidHeader = rejected(source, default(OwnedHeader), submitted, punished, config, limits())
  assert invalidHeader.error == SafroleTransitionError.InvalidHeader and verifications() == 0
  var absent = default(StateStore)
  assert advanceSafroleState(absent, header, submitted, punished, config).error ==
      SafroleTransitionError.Uninitialized
  var oversized = newSeq[Ticket](4)
  assert rejected(source, header, oversized, punished, config, limits()).error ==
      SafroleTransitionError.LimitExceeded
  var duplicate = newSeq[OffenderKey](2)
  let noncanonical = rejected(source, header, submitted, duplicate, config, limits())
  assert noncanonical.error == SafroleTransitionError.RotationFailure
  assert noncanonical.rotationError == ValidatorStateError.NonCanonical and verifications() == 0
  var noOffenders = config
  noOffenders.offenders = ElementLimit(1)
  assert rejected(source, header, submitted, duplicate, noOffenders, limits()).error ==
      SafroleTransitionError.LimitExceeded
  # A changed unsigned commitment remains structurally valid but no longer matches the seal's additional data.
  let tampered = rejected(source, capture(altered(raw, 0)), submitted, punished, config, limits())
  assert tampered.error == SafroleTransitionError.AuthenticationFailure
  assert tampered.authenticationError == SafroleAuthError.InvalidSeal
  damaged(source, header, submitted, punished, config)
  if crossing:
    # The epoch marker begins after the fixed 100-byte prefix and presence tag; changing its entropy is a marker rejection.
    assert raw[100] == 1
    let marker = rejected(source, capture(altered(raw, 101)), submitted, punished, config, limits())
    assert marker.error == SafroleTransitionError.MarkerFailure
    assert marker.markerError == SafroleMarkerError.InvalidEpochMarker and verifications() == 0
    for flags in [2, 4]:
      reset(cint(flags))
      failHash(0)
      var state = newStateStore(source, limits()).value
      let parentRoot = state.snapshot.value.commitment.root
      let refused = advanceSafroleState(state, header, submitted, punished, config)
      assert refused.error == SafroleTransitionError.RotationFailure
      assert refused.rotationError == ValidatorStateError.BackendFailure and liveSetups() == 0
      unchanged(state.snapshot.value, source, parentRoot)
  else:
    budgets(source, expected, header, submitted, punished,
        config) # Exact final write ceilings need no temporary rotation batch.
  if submitted.len != 0:
    var corrupt = newSeq[Ticket](submitted.len)
    for i in 0..<submitted.len: corrupt[i] = submitted[i] # Fixed proof records own every byte.
    corrupt[0].proof = default(TicketProof)
    let proof = rejected(source, header, corrupt, punished, config, limits())
    assert proof.error == SafroleTransitionError.AdmissionFailure
    assert proof.admissionError == TicketAdmissionError.InvalidProof and verifications() == 0
    reset(8)
    failHash(0)
    var refusedState = newStateStore(source, limits()).value
    let oldRoot = refusedState.snapshot.value.commitment.root
    let refused = advanceSafroleState(refusedState, header, submitted, punished, config)
    assert refused.error == SafroleTransitionError.AdmissionFailure
    assert refused.admissionError == TicketAdmissionError.BackendFailure and liveSetups() == 0
    unchanged(refusedState.snapshot.value, source, oldRoot)
  reset(0)
  failHash(0)

## Pin all successful chapter outputs and exercise backend failures after actual completed private work.
proc published(text: string) =
  let lines = text.splitLines()
  assert lines.len == 21
  for index in 0..<20:
    let f = lines[index].splitWhitespace()
    assert f.len == 15
    let config = policy()
    let rawHeader = unhex(f[1])
    let header = capture(rawHeader)
    let submitted = tickets(unhex(f[2]))
    let punished = offenders(unhex(f[3]))
    var source: seq[StateEntry] = @[]
    for i, chapter in [4, 6, 7, 8, 9, 11]:
      source.add(StateEntry(key: chapterKey(StateChapter(chapter)), value: unhex(f[
          4+i]))) # Only parent inputs, never posterior projections.
    source.add(StateEntry(key: chapterKey(StateChapter(1)), value: @[91'u8, 92, 93]))
    failHash(0)
    reset(0)
    var state = newStateStore(source, limits()).value
    let parent = state.snapshot.value
    let root = parent.commitment.root
    failHash(0)
    let outcome = advanceSafroleState(state, header, submitted, punished, config)
    assert outcome.error == SafroleTransitionError.None
    assert verifications() == 2 and liveSetups() == 0
    let count = hashes()
    assert count > 1
    for i, chapter in [4, 6, 8, 9, 11]:
      assert outcome.value.snapshot.lookup(chapterKey(StateChapter(chapter))).value.bytes ==
        unhex(f[10+i]) # Exact complete posterior bytes from the real signed trace.
    unchanged(parent, source, root)
    if index in [0, 2]:
      var expected: seq[StateEntry] = @[]
      for i, chapter in [4, 6, 8, 9, 11]:
        expected.add(StateEntry(key: chapterKey(StateChapter(chapter)), value: unhex(f[
            10+i]))) # Complete published posterior fields.
      boundaries(source, expected, rawHeader, submitted, punished, index == 2)
    assert state.snapshot.value.lookup(source[2].key).value.bytes == source[2].value
    assert state.snapshot.value.lookup(source[^1].key).value.bytes == source[^1].value
    # Replay cannot rotate twice or update entropy again once canonical time has advanced.
    let completedRoot = state.snapshot.value.commitment.root
    assert advanceSafroleState(state, header, submitted, punished, config).error ==
        SafroleTransitionError.InvalidSlot
    assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](completedRoot)
    for prefix in [0, 1]:
      failHash(0)
      reset(0)
      state = newStateStore(source, limits()).value
      refuseVerification(cint(prefix))
      let rejected = advanceSafroleState(state, header, submitted, punished, config)
      assert rejected.error == SafroleTransitionError.AuthenticationFailure
      assert rejected.authenticationError == SafroleAuthError.BackendFailure
      assert verifications() == cint(prefix+1) and liveSetups() == 0
      unchanged(state.snapshot.value, source, root)
    # First/last digest refusal includes already-completed rotation/admission on crossing records.
    for prefix in [0, int(count)-1]:
      reset(0)
      failHash(0)
      state = newStateStore(source, limits()).value
      hashAfter(cint(prefix))
      let rejected = advanceSafroleState(state, header, submitted, punished, config)
      assert rejected.error in [SafroleTransitionError.RotationFailure,
        SafroleTransitionError.ScheduleFailure, SafroleTransitionError.EntropyFailure,
        SafroleTransitionError.PublicationFailure]
      if prefix == int(count)-1:
        assert rejected.error == SafroleTransitionError.PublicationFailure
        assert rejected.publicationError == StateStoreError.BackendFailure # The last root digest cannot publish a completed stage.
      elif uint32(decodeStateTime(source[5].value).value.value) div 12 ==
          uint32(headerInfo(header).value.unsigned.slot) div 12:
        assert rejected.error == SafroleTransitionError.EntropyFailure
        assert rejected.entropyError == EntropyTransitionError.BackendFailure # Same-epoch first hash follows both valid credentials.
      else:
        assert rejected.error == SafroleTransitionError.RotationFailure
        assert rejected.rotationError == ValidatorStateError.BackendFailure # Crossing first hash is still private rotation publication.
      assert liveSetups() == 0
      unchanged(state.snapshot.value, source, root)
    if index == 0:
      reset(0)
      failHash(0)
      var temporary = newStateStore(source, limits()).value
      refuseVerification(0)
      discard advanceSafroleState(temporary, header, submitted, punished,
          config) # Warm caches before measuring owner retirement.
      let before = getOccupiedMem()
      for cycle in 0..<1000:
        let refused = advanceSafroleState(temporary, header, submitted, punished, config)
        assert refused.error == SafroleTransitionError.AuthenticationFailure # Each temporary private candidate retires within the cycle.
      let after = getOccupiedMem()
      assert before == after
      recordArcRelease("safrole_transition", 1000, before, after)
      unchanged(temporary.snapshot.value, source, root)
    reset(0)
    failHash(0)
    state = default(StateStore)
    assert outcome.value.snapshot.lookup(chapterKey(StateChapter(6))).value.bytes == unhex(f[11])
    assert headerInfo(outcome.value.authentication.header).error ==
        HeaderError.None # Retained success outlives store and private working handle.
  reset(0)
  failHash(0)

let fixture = getEnv("RAGNAROK_SAFROLE_TRANSITION")
assert fixture.len != 0
try:
  published(readFile(fixture)) # Missing fixture IO must fail the suite instead of skipping a corpus.
except:
  quit(2) # No partial result is a successful native test.
echo "PASS Safrole transition: twenty authenticated traces, exact chapters and atomic rollback"
