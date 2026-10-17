## Published signed-header credentials and independent entropy-state handoff, plus authenticated ticket/fallback fixtures.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/[safrole_authentication, entropy]
import ../../../src/codec/[state_safrole, state_consensus, header, bounded]
import ../../../src/bandersnatch/bandersnatch
import ../../support/[validator_rotation_fixture, arc_evidence]

## Reset test-only ordinary-verification counters without changing production ABI behavior.
proc reset(flags: cint) {.importc: "bo_reset", cdecl.}
## Refuse the next ordinary verification after a selected successful prefix.
proc refuseAfter(successful: cint) {.importc: "bo_ietf_after", cdecl.}
## Count attempts to prove both signatures verify and malformed/preflight inputs avoid native work.
proc verifications(): cint {.importc: "bo_ietf_calls", cdecl.}

## Parse a whole trusted unsigned decimal fixture field before narrowing.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Decode exact trusted hexadecimal transport without calling a production parser.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var value = 0'u8
    assert parseHex(text[2*i..2*i+1], value) == 2 # Every supplied octet is complete.
    result[i] = value

## Append one explicit suffix byte without changing the original trusted fixture buffer.
proc suffixed(raw: seq[byte]): seq[byte] =
  result = newSeq[byte](raw.len+1)
  for i in 0..<raw.len: result[i] = raw[i] # Preserve every original byte before the extra trailing value.
  result[raw.len] = 0

## Tiny policy bounds chapter/roster and complete header storage independently.
proc policy(): SafroleAuthConfig =
  SafroleAuthConfig(state: SafroleStateConfig(validators: rotationRosterConfig(2),
    epochSlots: EpochSlots(12), maxAccumulator: ElementLimit(12), maxBytes: ByteLimit(100000)),
    maxHeaderBytes: ByteLimit(100000))

## Capture one exact complete signed header while allowing the structural author ceiling to differ from actual population.
proc capture(raw: seq[byte], config: SafroleAuthConfig, cores = 2): OwnedHeader =
  let parsed = decodeHeader(raw, HeaderConfig(cores: CoreCount(uint64(cores)),
    authorValidators: ValidatorCount(uint64(cores)*3), epochSlots: config.state.epochSlots,
    maxBytes: ByteLimit(100000)))
  assert parsed.error == HeaderError.None and parsed.value.consumed == raw.len
  parsed.value.owner

## Encode a complete owned header to prove the result retains the exact authenticated source, not detached fields.
proc fullBytes(owner: OwnedHeader): seq[byte] =
  result = newSeq[byte](100000)
  let written = encodeOwnedHeader(owner, result)
  assert written.error == HeaderError.None
  result.setLen(written.value)

## Copy literal context bytes for authored signatures; complete published credentials remain independent evidence.
proc transcript(domain: string, seed: array[32, byte], attempt = -1): seq[byte] =
  result = newSeq[byte](domain.len+32+(if attempt < 0: 0 else: 1))
  for i, ch in domain: result[i] = byte(ch) # No production transcript helper is used to generate test credentials.
  for i in 0..<32: result[domain.len+i] = seed[i] # Preserve exact input and optional E1 attempt roles.
  if attempt >= 0: result[result.high] = byte(attempt) # Authored attempt 200 distinguishes E1 from compact encoding.

## Build real ordinary VRF credentials: output is independent of additional data, breaking the apparent signing cycle.
## The provisional seal is verified before its output seeds entropy; the final seal binds the complete unsigned header.
proc authored(ticketed: bool, previous, target: StateTime, parentEntropy: StateEntropy,
    config: SafroleAuthConfig, sealDollar = false, entropyDollar = false,
    entropyAdditional = false, wrongEntropyKey = false, author = 2): tuple[raw, schedule,
        active: seq[byte], output: array[32, byte]] =
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let key = importScalar(scalar).value
  let public = publicKey(key).value
  let crossed = uint32(target) div 12 > uint32(previous) div 12
  let seed = array[32, byte](parentEntropy[if crossed: 2 else: 3])
  let domain = (if sealDollar: "$" else: "") & (if ticketed: "jam_ticket_seal" else: "jam_fallback_seal")
  let input = transcript(domain, seed, (if ticketed: 200 else: -1))
  let provisional = sign(key, input, []).value
  let output = verify(public, provisional, input, []).value
  let entropyInput = transcript((if entropyDollar: "$jam_entropy" else: "jam_entropy"), array[32,
      byte](output))
  let additional = if entropyAdditional: @[7'u8] else: newSeq[byte](
      0) # A nonempty entropy AD must be rejected even if its proof is valid elsewhere.
  var entropyKey = key
  if wrongEntropyKey:
    scalar[0] = 2
    entropyKey = importScalar(scalar).value # Entropy must verify under the indexed seal author, not another valid key.
  let proof = sign(entropyKey, entropyInput, additional).value
  var source = default(Header)
  source.unsigned.slot = HeaderSlot(uint32(target))
  source.unsigned.author = AuthorIndex(uint16(author))
  source.unsigned.epoch = absentEpoch()
  source.unsigned.winners = absentWinners()
  source.unsigned.entropyProof = HeaderEntropyProof(array[96, byte](proof))
  let headerPolicy = HeaderConfig(cores: CoreCount(4), authorValidators: ValidatorCount(12),
      epochSlots: EpochSlots(12), maxBytes: ByteLimit(100000))
  var unsigned = newSeq[byte](100000)
  let measured = encodeUnsignedHeader(source.unsigned, headerPolicy, unsigned).value
  unsigned.setLen(measured)
  source.seal = HeaderSeal(array[96, byte](sign(key, input, unsigned).value))
  var wire = newSeq[byte](100000)
  let size = encodeHeader(source, headerPolicy, wire).value
  wire.setLen(size)
  var records = rotationRecords(6, 1)
  for i in 0..<records.len:
    records[i].bandersnatch = StateBsKey(array[32, byte](
        public)) # Actual posterior roster contains the signing key at the indexed author.
  let active = validatorEntry(ValidatorChapter.Active, records, config.state.validators).value.value
  var state = SafroleState(pending: records, root: default(StateRingRoot), accumulator: @[],
      schedule: keySchedule(newSeq[StateBsKey](12)))
  if ticketed:
    var selected = newSeq[WinningTicket](12)
    for i in 0..<12: selected[i] = WinningTicket(id: WinningTicketId(array[32, byte](output)),
        attempt: TicketAttempt(200)) # Full E1 values remain legal schedule records.
    state.schedule = ticketSchedule(selected)
  else:
    var selected = newSeq[StateBsKey](12)
    for i in 0..<12: selected[i] = StateBsKey(array[32, byte](
        public)) # Fallback selection requires exact key equality.
    state.schedule = keySchedule(selected)
  if wrongEntropyKey: close(entropyKey) # Release the independent authored secret after all signatures are copied.
  close(key)
  (wire, safroleStateEntry(state, config.state).value.value, active, array[32, byte](output))

## Retire temporary successful result owners and refused signing-copy candidates within each call scope.
proc cycle(raw, schedule, active: seq[byte], previous: StateTime, entropy: StateEntropy,
    config: SafroleAuthConfig) =
  let owner = capture(raw, config)
  reset(0)
  refuseAfter(0)
  assert authenticateSafroleSeal(owner, schedule, active, previous, entropy, config).error ==
      SafroleAuthError.BackendFailure

## Real authored ticket proofs complement the independently supplied trace corpus; exact failure causes remain asserted.
proc boundaries() =
  let config = policy()
  var entropy = default(StateEntropy)
  for i in 0..<4:
    var word = default(array[32, byte])
    word[0] = byte(10+i) # Distinct historical words detect wrong epoch/history selection.
    entropy[i] = StateEntropyWord(word)
  for ticketed in [false, true]:
    for slots in [(0'u32, 1'u32), (11'u32, 12'u32), (1'u32, 37'u32)]:
      reset(0)
      let previous = StateTime(slots[0])
      let target = StateTime(slots[1])
      let fixture = authored(ticketed, previous, target, entropy, config)
      let owner = capture(fixture.raw, config, 4)
      reset(0)
      let outcome = authenticateSafroleSeal(owner, fixture.schedule, fixture.active, previous,
          entropy, config)
      assert outcome.error == SafroleAuthError.None and outcome.value.ticketed == ticketed
      assert array[32, byte](outcome.value.sealOutput) == fixture.output and verifications() == 2
      assert fullBytes(outcome.value.header) == fixture.raw
      for prefix in [0, 1]:
        reset(0)
        refuseAfter(cint(prefix))
        assert authenticateSafroleSeal(owner, fixture.schedule, fixture.active, previous, entropy,
            config).error == SafroleAuthError.BackendFailure
        assert verifications() == cint(prefix+1) # First seal/second entropy backend failure publishes no prefix.
      reset(0)
      var changed = fixture.raw
      changed[0] = changed[0] xor 1 # Every unsigned header field is additional data, without an implicit hash.
      assert authenticateSafroleSeal(capture(changed, config, 4), fixture.schedule, fixture.active,
          previous, entropy, config).error == SafroleAuthError.InvalidSeal
      var changedSchedule = fixture.schedule
      # Corrupt the selected slot explicitly after the six fixed pending records and ring root.
      let start = 1+6*336+144+1+int(uint32(target) mod 12)*(if ticketed: 33 else: 32)
      changedSchedule = fixture.schedule
      changedSchedule[start] = changedSchedule[start] xor 1
      let wrong = authenticateSafroleSeal(owner, changedSchedule, fixture.active, previous, entropy, config)
      assert wrong.error == (if ticketed: SafroleAuthError.InvalidTicket else: SafroleAuthError.InvalidAuthor)
      for mode in 0..<4:
        reset(0)
        let bad = authored(ticketed, previous, target, entropy, config, mode == 0, mode == 1,
            mode == 2, mode == 3)
        reset(0)
        assert authenticateSafroleSeal(capture(bad.raw, config, 4), bad.schedule, bad.active,
            previous, entropy, config).error ==
          (if mode == 0: SafroleAuthError.InvalidSeal else: SafroleAuthError.InvalidEntropy)
      reset(0)
      let tooLargeAuthor = authored(ticketed, previous, target, entropy, config, author = 8)
      reset(0)
      assert authenticateSafroleSeal(capture(tooLargeAuthor.raw, config, 4),
          tooLargeAuthor.schedule, tooLargeAuthor.active, previous, entropy, config).error ==
          SafroleAuthError.InvalidAuthor
      assert verifications() == 0
      assert authenticateSafroleSeal(owner, suffixed(fixture.schedule), fixture.active, previous,
          entropy, config).error == SafroleAuthError.InvalidState
      assert authenticateSafroleSeal(owner, fixture.schedule, suffixed(fixture.active), previous,
          entropy, config).error == SafroleAuthError.InvalidState
      assert authenticateSafroleSeal(owner, fixture.schedule, fixture.active, target, entropy,
          config).error == SafroleAuthError.InvalidSlot
      for limit in 0..<3:
        var small = config
        if limit == 0:
          small.maxHeaderBytes = ByteLimit(uint64(fixture.raw.len-1)) # Complete header ceiling includes the seal.
        elif limit == 1:
          small.state.maxBytes = ByteLimit(uint64(fixture.schedule.len-1)) # C(4) ceiling precedes any capture.
        else:
          small.state.validators.maxBytes = ByteLimit(uint64(
              fixture.active.len-1)) # Active roster has an independent byte ceiling.
        reset(0)
        assert authenticateSafroleSeal(owner, fixture.schedule, fixture.active, previous, entropy,
            small).error == SafroleAuthError.LimitExceeded
        assert verifications() == 0
      if not ticketed and slots[0] == 0:
        for warm in 0..<25: cycle(fixture.raw, fixture.schedule, fixture.active, previous, entropy,
            config) # Warm temporary owner paths.
        let before = getOccupiedMem()
        for repeat in 0..<1000: cycle(fixture.raw, fixture.schedule, fixture.active, previous,
            entropy, config) # Failed result/copy owners retire within each scope.
        let after = getOccupiedMem()
        assert before == after
        recordArcRelease("safrole_authentication", 1000, before, after)
  reset(0)

## Published headers and parent/posterior state bytes are supplied independently; no signing keys are generated for this evidence.
proc published(text: string) =
  let lines = text.splitLines()
  assert lines.len == 21
  let config = policy()
  for i in 0..<20:
    let f = lines[i].splitWhitespace()
    assert f.len == 7
    let raw = unhex(f[1])
    let previous = decodeStateTime(unhex(f[2])).value.value
    let entropy = decodeStateEntropy(unhex(f[3])).value.value
    let schedule = unhex(f[4])
    let active = unhex(f[5])
    let expected = unhex(f[6])
    let owner = capture(raw, config)
    reset(0)
    let outcome = authenticateSafroleSeal(owner, schedule, active, previous, entropy, config)
    assert outcome.error == SafroleAuthError.None and verifications() == 2
    assert outcome.value.ticketed == (f[0] in ["safrole/48",
        "safrole/49"]) # Explicit published schedule classification: eighteen fallback, two ticket records.
    let target = StateTime(uint32(headerInfo(owner).value.unsigned.slot))
    let advanced = advanceEntropyTime(entropy, previous, target, outcome.value.entropy, EpochSlots(12))
    assert advanced.error == EntropyTransitionError.None
    assert entropyEntry(advanced.value.entropy).value ==
        expected # Independent published posterior accumulator/history binds the authenticated output.
    assert fullBytes(outcome.value.header) == raw
  reset(0)

boundaries()
try:
  published(readFile(getEnv("RAGNAROK_SAFROLE_AUTHENTICATION"))) # Missing published credential transport must fail explicitly.
except:
  quit(2) # Do not substitute self-generated signatures for absent external evidence.
echo "PASS Safrole authentication: twenty published credentials, ticket/fallback proofs and verified entropy handoff"
