## Real signed blocks bind exact parent headers and complete parent-state maps before atomic Safrole execution.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/[block_admission, safrole_transition, safrole_authentication, store]
import ../../../src/codec/[block_codec, header, bounded, composite, tickets, state_safrole,
  state_consensus,
  state_disputes, state_trie, state_layout]
from ../../../src/codec/disputes import OffenderKey
import ../../support/[validator_rotation_fixture, arc_evidence]

## Reset exact ordinary/ring/setup counters between fully retired invocations.
proc reset(flags: cint) {.importc: "bo_reset", cdecl.}
## Refuse an ordinary proof after an exact completed prefix.
proc refuseVerification(successful: cint) {.importc: "bo_ietf_after", cdecl.}
## Binding failures cannot reach seal/entropy verification.
proc verifications(): cint {.importc: "bo_ietf_calls", cdecl.}
## Binding failures cannot create RingVRF setup owners either.
proc setups(): cint {.importc: "bo_setup_news", cdecl.}
## All native setup owners must retire even after later commitment or signature refusal.
proc liveSetups(): cint {.importc: "bo_live_setups", cdecl.}
## Reset or immediately refuse the native Blake2b primitive.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Refuse after admission or at the final stage publication digest.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count exact commitment work independently of fixture-map construction.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}

## Trusted hexadecimal transport accepts empty state values without inventing placeholder bytes.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    assert parseHex(text[i*2..i*2+1], result[i]) == 2 # Complete known source octets only.

## Mutate only a new test-owned copy, preserving the original immutable source evidence.
proc changed(raw: seq[byte], at: int): seq[byte] =
  result = newSeq[byte](raw.len)
  for i in 0..<raw.len: result[i] = raw[i] # Every other candidate byte remains exact.
  result[at] = result[at] xor 1

## Tiny block policy is explicit and has complete-frame and per/preimage aggregate resource bounds.
proc policy(): BlockAdmissionConfig =
  BlockAdmissionConfig(frame: FrameConfig(cores: CoreCount(2), validators: ValidatorCount(6),
    epochSlots: EpochSlots(12), ticketLimit: TicketLimit(3), maxBytes: ByteLimit(2000000),
    preimages: PreimageLimits(items: ElementLimit(10000), perBlob: ByteLimit(2000000),
      totalBlobBytes: ByteLimit(2000000))), maxParentHeaderBytes: ByteLimit(2000000))

## The same chain domains apply to decoding, validator rotation, admission, markers and authentication.
proc stagePolicy(): SafroleTransitionConfig =
  SafroleTransitionConfig(state: SafroleStateConfig(validators: rotationRosterConfig(2),
    epochSlots: EpochSlots(12), maxAccumulator: ElementLimit(12), maxBytes: ByteLimit(2000000)),
    tailStart: EpochSlots(10), blockTickets: TicketLimit(3), offenders: ElementLimit(10000),
    maxHeaderBytes: ByteLimit(2000000), maxMarkerBytes: ByteLimit(2000000))

## These generous but finite full-map limits include every published raw key/value, not a partial projection.
proc limits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(100000), perValue: ByteLimit(20000000),
    totalValueBytes: ByteLimit(100000000), nodes: TrieNodeLimit(1000000)),
    writes: ElementLimit(5), writeValueBytes: ByteLimit(20000000))

## Capture exactly one signed parent header with no application-level signature verification yet.
proc parentHeader(raw: seq[byte]): OwnedHeader =
  let parsed = decodeHeader(raw, HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6),
    epochSlots: EpochSlots(12), maxBytes: ByteLimit(2000000)))
  assert parsed.error == HeaderError.None and parsed.value.consumed == raw.len
  parsed.value.owner

## A complete owner retains its own header and all five extrinsic families after source bytes are retired.
proc candidateBlock(raw: seq[byte]): OwnedBlock =
  let parsed = decodeBlock(raw, policy().frame)
  assert parsed.error == FrameError.None and parsed.value.consumed == raw.len
  parsed.value.owner

## Full raw mappings preserve unknown chapters, services and empty values verbatim.
proc entries(text: string): seq[StateEntry] =
  result = @[]
  for pair in text.split(','):
    let fields = pair.split('=')
    assert fields.len == 2
    let rawKey = unhex(fields[0])
    assert rawKey.len == 31
    var key = default(array[31, byte])
    for i in 0..<31: key[i] = rawKey[i] # Fixed key identity never derives from a chapter guess.
    result.add(StateEntry(key: StateKey(key), value: unhex(fields[1])))

## Posterior disputes offenders are independently supplied, without claiming to execute disputes here.
proc offenders(raw: seq[byte]): seq[OffenderKey] =
  let parsed = decodeDisputeState(raw, DisputeStateConfig(perSet: ElementLimit(10000),
    totalItems: ElementLimit(40000), maxBytes: ByteLimit(2000000)))
  assert parsed.error == DisputeStateError.None and parsed.value.consumed == raw.len
  result = newSeq[OffenderKey](disputeStateInfo(parsed.value.snapshot).value.offenders)
  for i in 0..<result.len:
    result[i] = stateOffenderAt(parsed.value.snapshot, DisputeStateIndex(uint64(
        i))).value # Exact canonical fixed identities.

## Both every original byte and its root must survive any failure, not merely C(11).
proc unchanged(snapshot: StateStoreSnapshot, source: seq[StateEntry], root: StateRoot) =
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](root)
  for entry in source:
    assert snapshot.lookup(entry.key).value.bytes == entry.value # Includes all unrelated service/chapter values.

## Wrong commitments and byte ceilings must refuse before RingVRF or ordinary signatures and preserve state.
proc reject(state: StateStore, candidate: OwnedBlock, parent: OwnedHeader, source: seq[StateEntry],
    punished: seq[OffenderKey], config: BlockAdmissionConfig, expected: BlockAdmissionError) =
  reset(0)
  failHash(0)
  var working = state
  let root = state.snapshot.value.commitment.root
  let result = advanceBlockSafrole(working, candidate, parent, punished, config, stagePolicy())
  assert result.error == BlockSafroleError.AdmissionFailure and result.admissionError == expected
  assert verifications() == 0 and setups() == 0 and liveSetups() == 0
  unchanged(working.snapshot.value, source, root)

## Reject disconnected parent-state context and caller-profile substitutions before primitive or Safrole work.
proc contextBoundaries(state: StateStore, source: seq[StateEntry], raw, parentRaw: seq[byte],
    punished: seq[OffenderKey]) =
  let candidate = candidateBlock(raw)
  let parent = parentHeader(parentRaw)
  let retained = state.snapshot.value
  let root = retained.commitment.root
  reset(0)
  failHash(0)
  assert validateBlockCommitments(default(OwnedBlock), parent, retained, policy()).error ==
      BlockAdmissionError.InvalidBlock
  assert validateBlockCommitments(candidate, default(OwnedHeader), retained, policy()).error ==
      BlockAdmissionError.InvalidParent
  assert validateBlockCommitments(candidate, parent, default(StateStoreSnapshot), policy()).error ==
      BlockAdmissionError.Uninitialized
  assert hashes() == 0 and verifications() == 0 and setups() == 0
  let timeKey = array[31, byte](chapterKey(StateChapter(11)))
  for mode in 0..<5:
    var broken: seq[StateEntry] = @[]
    var rootChanged = false
    for entry in source:
      let isTime = array[31, byte](entry.key) == timeKey
      if isTime and mode == 0:
        discard # Remove exactly C(11), preserving all service and other chapter values.
      elif isTime and mode in [1, 2, 3]:
        let size = entry.value.len+(if mode == 1: -1 elif mode == 2: 1 else: 0)
        var value = newSeq[byte](size)
        for i in 0..<min(size, entry.value.len): value[i] = entry.value[
            i] # Copy before exact one-byte shape damage.
        if mode == 3: value[0] = value[0] xor 1 # Structurally valid time belongs to another parent slot.
        broken.add(StateEntry(key: entry.key, value: value))
      elif not isTime and mode == 4 and not rootChanged:
        var value = newSeq[byte](entry.value.len+1)
        for i in 0..<entry.value.len: value[i] = entry.value[
            i] # Change one unrelated opaque state value so only its root differs.
        broken.add(StateEntry(key: entry.key, value: value))
        rootChanged = true
      else:
        broken.add(entry) # Every unrelated original byte remains retained and immutable.
    failHash(0)
    var wrong = newStateStore(broken, limits()).value
    let wrongRoot = wrong.snapshot.value.commitment.root
    failHash(0)
    let rejected = validateBlockCommitments(candidate, parent, wrong.snapshot.value, policy())
    let expected = if mode == 0: BlockAdmissionError.MissingState elif mode == 4:
      BlockAdmissionError.InvalidStateRoot else: BlockAdmissionError.InvalidState
    assert rejected.error == expected and hashes() == 0
    unchanged(wrong.snapshot.value, broken, wrongRoot)
    unchanged(retained, source, root)
  # Header timeslots are fixed E4 fields; a syntactically valid zero slot cannot wrap past this parent.
  var backward = newSeq[byte](raw.len)
  for i in 0..<raw.len: backward[i] = raw[i] # Preserve the signed header and body except the isolated time field.
  for i in 96..<100: backward[i] = 0
  reject(state, candidateBlock(backward), parent, source, punished, policy(),
      BlockAdmissionError.InvalidSlot)
  reject(state, candidate, parentHeader(changed(parentRaw, 96)), source, punished, policy(),
      BlockAdmissionError.InvalidState)
  for mode in 0..<4:
    var conflicting = policy()
    case mode
    of 0: conflicting.frame.cores = CoreCount(3) # State rotation and decoding must share one chain core domain.
    of 1: conflicting.frame.validators = ValidatorCount(
        9) # Structural author ceiling cannot silently diverge from roster policy.
    of 2: conflicting.frame.epochSlots = EpochSlots(
        13) # Schedule/marker epochs cannot use an independently selected length.
    else: conflicting.frame.ticketLimit = TicketLimit(
        2) # One block cannot use different admission/decoding ticket maxima.
    reject(state, candidate, parent, source, punished, conflicting,
        BlockAdmissionError.InvalidConfig)
    assert hashes() == 0
  var exact = policy()
  exact.frame.maxBytes = ByteLimit(uint64(raw.len))
  exact.maxParentHeaderBytes = ByteLimit(uint64(parentRaw.len))
  failHash(0)
  assert validateBlockCommitments(candidate, parent, retained, exact).error ==
      BlockAdmissionError.None
  # Public handles capture immutable bytes, not aliases into this mutable source copy.
  var mutable = newSeq[byte](raw.len)
  for i in 0..<raw.len: mutable[i] = raw[i]
  let captured = candidateBlock(mutable)
  mutable[0] = mutable[0] xor 1
  assert validateBlockCommitments(captured, parent, retained, policy()).error ==
      BlockAdmissionError.None
  # Whole binding success and first-hash refusal must retire all temporary captures within each iteration.
  for warm in 0..<25:
    discard validateBlockCommitments(candidate, parent, retained, policy()) # Exclude one-time runtime caches from occupancy evidence.
  let before = getOccupiedMem()
  for cycle in 0..<1000:
    failHash(cint(if cycle mod 2 == 0: 0 else: 1))
    let outcome = validateBlockCommitments(candidate, parent, retained, policy())
    assert outcome.error == (if cycle mod 2 == 0: BlockAdmissionError.None else: BlockAdmissionError.BackendFailure)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("block_admission", 1000, before, after)
  failHash(0)
  unchanged(retained, source, root)

## Owners captured with an unrestricted ticket ceiling must be checked again under application policy.
proc stricterTickets(state: StateStore, candidate: OwnedBlock, parent: OwnedHeader,
    source: seq[StateEntry], punished: seq[OffenderKey]) =
  var strict = policy()
  strict.frame.ticketLimit = TicketLimit(0)
  var noTickets = stagePolicy()
  noTickets.blockTickets = TicketLimit(0)
  reset(0)
  failHash(0)
  var working = state
  let refused = advanceBlockSafrole(working, candidate, parent, punished, strict, noTickets)
  assert refused.error == BlockSafroleError.AdmissionFailure
  assert refused.admissionError == BlockAdmissionError.InvalidBlock # Exact recapture rejects the captured ticket count before any hashes.
  assert hashes() == 0 and verifications() == 0 and setups() == 0
  unchanged(working.snapshot.value, source, state.snapshot.value.commitment.root)

## Published parent linkage, complete-state roots, exact block commitments and actual Safrole outputs agree together.
proc cases(text: string) =
  let lines = text.splitLines()
  assert lines.len == 11
  var emptyFamilies = default(OwnedExtrinsic)
  for index in 0..<10:
    let fields = lines[index].splitWhitespace()
    assert fields.len == 11
    let raw = unhex(fields[1])
    let parentRaw = unhex(fields[2])
    var candidate = candidateBlock(raw)
    var parent = parentHeader(parentRaw)
    let source = entries(fields[3])
    let punished = offenders(unhex(fields[9]))
    reset(0)
    failHash(0)
    var original = newStateStore(source, limits()).value
    let before = original.snapshot.value
    let root = before.commitment.root
    let expectedRoot = unhex(fields[10])
    assert array[32, byte](root) == expectedRoot # Complete published raw state reproduces its recorded root.
    failHash(0)
    let binding = validateBlockCommitments(candidate, parent, before, policy())
    assert binding.error == BlockAdmissionError.None
    assert verifications() == 0 and setups() == 0
    let admissionHashes = hashes()
    assert admissionHashes >= 7
    unchanged(before, source, root)
    # Admission-only primitive failures cannot create a partial bound owner or touch state.
    for prefix in [0, int(admissionHashes)-1]:
      hashAfter(cint(prefix))
      assert validateBlockCommitments(candidate, parent, before, policy()).error ==
          BlockAdmissionError.BackendFailure
      assert hashes() == cint(prefix+1) and verifications() == 0 and setups() == 0
      unchanged(before, source, root)
    if index == 0:
      contextBoundaries(original, source, raw, parentRaw,
          punished) # One full mapping exercises independent context and ownership boundaries.
    elif index == 5:
      stricterTickets(original, candidate, parent, source,
          punished) # The first Safrole trace carries real submitted proofs.
    reset(0)
    failHash(0)
    let result = advanceBlockSafrole(original, candidate, parent, punished, policy(), stagePolicy())
    assert result.error == BlockSafroleError.None and verifications() == 2 and liveSetups() == 0
    let totalHashes = hashes()
    for i, chapter in [4, 6, 8, 9, 11]:
      assert result.value.transition.snapshot.lookup(chapterKey(StateChapter(
          chapter))).value.bytes == unhex(fields[
          4+i]) # Complete actual Safrole outputs, without posterior inputs.
    unchanged(before, source, root)
    for entry in source:
      let key = array[31, byte](entry.key)
      if key[0] notin [4'u8, 6, 8, 9, 11] or key != array[31, byte](chapterKey(StateChapter(key[0]))):
        assert result.value.transition.snapshot.lookup(entry.key).value.bytes ==
            entry.value # Every service and other chapter is preserved.
    # Failure after successful admission must preserve the canonical parent, even after both ordinary signatures.
    for prefix in [0, 1]:
      reset(0)
      failHash(0)
      var working = newStateStore(source, limits()).value
      refuseVerification(cint(prefix))
      let refused = advanceBlockSafrole(working, candidate, parent, punished, policy(), stagePolicy())
      assert refused.error == BlockSafroleError.SafroleFailure
      assert refused.safroleError.error == SafroleTransitionError.AuthenticationFailure
      assert refused.safroleError.authenticationError == SafroleAuthError.BackendFailure
      assert verifications() == cint(prefix+1) and liveSetups() == 0
      unchanged(working.snapshot.value, source, root)
    reset(0)
    failHash(0)
    var last = newStateStore(source, limits()).value
    hashAfter(cint(totalHashes-1))
    let refused = advanceBlockSafrole(last, candidate, parent, punished, policy(), stagePolicy())
    assert refused.error == BlockSafroleError.SafroleFailure
    assert refused.safroleError.error == SafroleTransitionError.PublicationFailure
    assert refused.safroleError.publicationError == StateStoreError.BackendFailure
    unchanged(last.snapshot.value, source, root)
    reject(last, candidateBlock(changed(raw, 0)), parent, source, punished, policy(),
        BlockAdmissionError.InvalidParentHash)
    reject(last, candidateBlock(changed(raw, 32)), parent, source, punished, policy(),
        BlockAdmissionError.InvalidStateRoot)
    reject(last, candidateBlock(changed(raw, 64)), parent, source, punished, policy(),
        BlockAdmissionError.InvalidExtrinsicHash)
    reject(last, candidate, parentHeader(changed(parentRaw, parentRaw.len-1)), source, punished,
        policy(), BlockAdmissionError.InvalidParentHash)
    for kind in 0..<2:
      var small = policy()
      if kind == 0:
        small.frame.maxBytes = ByteLimit(uint64(raw.len-1)) # Whole block is bounded before recapture or commitment hashing.
      else:
        small.maxParentHeaderBytes = ByteLimit(uint64(
            parentRaw.len-1)) # Full sealed parent is separately bounded.
      reject(last, candidate, parent, source, punished, small, BlockAdmissionError.LimitExceeded)
    if index == 0:
      emptyFamilies = blockExtrinsic(candidate).value # Used later to prove another block's tickets cannot be substituted.
    elif index == 5:
      var swapped = newSeq[byte](raw.len)
      let written = encodeBlock(Block(header: blockHeader(candidate).value,
          extrinsic: emptyFamilies), policy().frame, swapped)
      assert written.error == FrameError.None
      swapped.setLen(written.value)
      reject(last, candidateBlock(swapped), parent, source, punished, policy(),
          BlockAdmissionError.InvalidExtrinsicHash)
    reset(0)
    failHash(0)
    candidate = default(OwnedBlock)
    parent = default(OwnedHeader)
    original = default(StateStore)
    unchanged(binding.value.admittedState, source, root)
    assert blockInfo(binding.value.admittedBlock).value.consumed == raw.len
    assert headerInfo(binding.value.admittedParent).value.consumed == parentRaw.len
    assert headerInfo(result.value.admitted.admittedHeader).error ==
        HeaderError.None # Escaped binding/header/state owners outlive all original caller handles.
  reset(0)
  failHash(0)

try:
  cases(readFile(getEnv("RAGNAROK_BLOCK_ADMISSION"))) # Missing or modified pinned evidence is never a skipped integration suite.
except:
  quit(2) # An incomplete source corpus must fail the native runner.
echo "PASS block admission: ten signed blocks, complete parent roots and atomic same-block Safrole"
