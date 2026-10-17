## Execute every Safrole substep from actual pinned parent chapters and signed headers, with atomic rollback.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/[safrole_transition, store, validator_state, ticket_admission,
  sealer_schedule, safrole_markers, safrole_authentication, entropy]
import ../../../src/codec/[state_safrole, state_consensus, state_disputes, state_layout,
  state_trie, header, tickets, bounded]
from ../../../src/codec/disputes import OffenderKey
import ../../support/validator_rotation_fixture

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
      assert liveSetups() == 0
      unchanged(state.snapshot.value, source, root)
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
