## Published GP epoch/winner marker outputs and exact optional, entropy, ordering and attempt checks.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/safrole_markers
import ../../../src/codec/[state_safrole, state_consensus, header, bounded]
import ../../support/[validator_rotation_fixture, arc_evidence]

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

## Finite chain policy bounds every parent/posterior chapter and active roster independently.
proc policy(epoch = 12, tail = 10): SafroleMarkerConfig =
  SafroleMarkerConfig(state: SafroleStateConfig(validators: rotationRosterConfig(),
    epochSlots: EpochSlots(uint64(epoch)), maxAccumulator: ElementLimit(uint64(epoch)),
    maxBytes: ByteLimit(1000000)), tailStart: EpochSlots(uint64(tail)), maxMarkerBytes: ByteLimit(1000000))

## Encode complete immutable markers for exact comparison with independently transported vector output.
proc epochBytes(owner: OwnedEpochMarker): seq[byte] =
  result = newSeq[byte](100000)
  let written = encodeOwnedEpochMarker(owner, result)
  assert written.error == HeaderError.None
  result.setLen(written.value)

## Winning marker framing has no count and includes the original attempt for every slot.
proc winnerBytes(owner: OwnedWinnersMarker): seq[byte] =
  result = newSeq[byte](100000)
  let written = encodeOwnedWinnersMarker(owner, result)
  assert written.error == HeaderError.None
  result.setLen(written.value)

## Scope all temporary result and wire owners for ARC retirement evidence.
proc cycle(parent, staged: seq[byte], previous, target: StateTime, entropy: StateEntropy,
    config: SafroleMarkerConfig) =
  assert deriveSafroleMarkers(parent, staged, previous, target, entropy, config).error ==
      SafroleMarkerError.None

## Every accepted tiny/full case supplies both expected optional markers, independent of native predicates.
proc published(text: string) =
  let lines = text.splitLines()
  assert lines.len == 34
  for i in 0..<33:
    let f = lines[i].splitWhitespace()
    assert f.len == 19
    var config = policy(int(number(f[2])), int(number(f[3])))
    config.state.validators = rotationRosterConfig(int(number(f[1])))
    let parent = unhex(f[7])
    let staged = unhex(f[10])
    let previous = StateTime(uint32(number(f[4])))
    let target = StateTime(uint32(number(f[5])))
    let entropy = decodeStateEntropy(unhex(f[12])).value.value
    let outcome = deriveSafroleMarkers(parent, staged, previous, target, entropy, config)
    assert outcome.error == SafroleMarkerError.None
    let markers = outcome.value
    let epoch = unhex(f[17])
    let winners = unhex(f[18])
    assert epochBytes(markers.epochMarker) == epoch
    assert winnerBytes(markers.winnersMarker) == winners
    let headerPolicy = HeaderConfig(cores: config.state.validators.cores,
      authorValidators: ValidatorCount(uint64(config.state.validators.cores)*3),
          epochSlots: config.state.epochSlots, maxBytes: config.maxMarkerBytes)
    let actualEpoch = decodeEpochMarker(epoch, headerPolicy).value.owner
    let actualWinners = decodeWinnersMarker(winners, headerPolicy).value.owner
    assert validateSafroleMarkers(markers, actualEpoch, actualWinners) == SafroleMarkerError.None
    assert validateSafroleMarkers(markers, default(OwnedEpochMarker), actualWinners) ==
        SafroleMarkerError.InvalidEpochMarker
    assert validateSafroleMarkers(markers, actualEpoch, default(OwnedWinnersMarker)) ==
        SafroleMarkerError.InvalidWinnersMarker
    if epoch.len > 1:
      for position in [1, 33, epoch.len-64, epoch.len-32]:
        var changed = epoch
        changed[position] = changed[position] xor 1 # Independently corrupt both entropies and each key role.
        let damaged = decodeEpochMarker(changed, headerPolicy)
        assert damaged.error == HeaderError.None
        assert validateSafroleMarkers(markers, damaged.value.owner, actualWinners) ==
            SafroleMarkerError.InvalidEpochMarker
    if winners.len > 1:
      for position in [1, 33, winners.len-1]:
        var changed = winners
        changed[position] = changed[position] xor 1 # Corrupt identifier, first attempt and final attempt separately.
        let damaged = decodeWinnersMarker(changed, headerPolicy)
        assert damaged.error == HeaderError.None
        assert validateSafroleMarkers(markers, actualEpoch, damaged.value.owner) ==
            SafroleMarkerError.InvalidWinnersMarker
    let absentEpochOwner = decodeEpochMarker(@[0'u8], headerPolicy).value.owner
    let absentWinnersOwner = decodeWinnersMarker(@[0'u8], headerPolicy).value.owner
    if epoch.len > 1:
      assert validateSafroleMarkers(markers, absentEpochOwner, actualWinners) ==
          SafroleMarkerError.InvalidEpochMarker
    if winners.len > 1:
      assert validateSafroleMarkers(markers, actualEpoch, absentWinnersOwner) ==
          SafroleMarkerError.InvalidWinnersMarker
    assert deriveSafroleMarkers(suffixed(parent), staged, previous, target, entropy,
        config).error == SafroleMarkerError.InvalidState
    assert deriveSafroleMarkers(parent, suffixed(staged), previous, target, entropy,
        config).error == SafroleMarkerError.InvalidState
    assert deriveSafroleMarkers(parent, staged, target, target, entropy, config).error ==
        SafroleMarkerError.InvalidSlot
    let needed = max(epoch.len, winners.len)
    var bounded = config
    bounded.maxMarkerBytes = ByteLimit(uint64(needed))
    assert deriveSafroleMarkers(parent, staged, previous, target, entropy, bounded).error ==
        SafroleMarkerError.None
    bounded.maxMarkerBytes = ByteLimit(uint64(needed-1))
    assert deriveSafroleMarkers(parent, staged, previous, target, entropy, bounded).error ==
        SafroleMarkerError.LimitExceeded
    if i == 0:
      for warm in 0..<25: cycle(parent, staged, previous, target, entropy,
          config) # Warm temporary owners before measurement.
      let before = getOccupiedMem()
      for repeat in 0..<1000: cycle(parent, staged, previous, target, entropy,
          config) # Every derived pair retires within its call scope.
      let after = getOccupiedMem()
      assert before == after
      recordArcRelease("safrole_markers", 1000, before, after)
  assert validateSafroleMarkers(default(SafroleMarkers), default(OwnedEpochMarker), default(
      OwnedWinnersMarker)) == SafroleMarkerError.Uninitialized

try:
  published(readFile(getEnv("RAGNAROK_SAFROLE_MARKERS"))) # Prepared transport is mandatory; no upstream case is silently skipped.
except:
  quit(2) # Missing/corrupt transport cannot become a passing native profile.
echo "PASS Safrole markers: thirty-three published pairs, exact state binding and immutable ownership"
