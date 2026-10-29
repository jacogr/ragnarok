# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine current children bind structural profiles/full parameter tuples to exact source identity with bounded hash-free C9 decoding.
# @@Verification={"arc": "state_current_profile_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_checkpoint_context, accumulation_current_chain_context, arc_evidence]
import ../../../src/state/current/profile as current_profile
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/store
import ../../../src/chain/[parameters, genesis]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[layout as state_layout, composition as state_composition,
    safrole as state_safrole, consensus as state_consensus]
import ../../../src/codec/assurances
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashes after genuine current preparation completes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Profile projection uses cached child facts and bounded typed decoding only.
const limits = CurrentProfileLimits(validators: ElementLimit(6), bytes: ByteLimit(2017))
proc verify(source: PreparedCurrentChainUpdate) =
  ## Compare every retained parameter and independently known six-record previous roster, then mutate only copied observations.
  let captured = captureCurrentProfile(source, limits).value
  let child = source.currentUpdateChild
  var profile = captured.derivedStateProfile.value
  assert profile.valid
  assert uint64(profile.cores) == uint64(child.cores)
  assert uint64(profile.current) == uint64(child.activeValidators)
  assert uint64(profile.previous) == 6
  assert uint64(profile.epochSlots) == uint64(child.epochSlots)
  for field in low(Parameter)..high(Parameter):
    assert captured.derivedParameters.value.get(field) == child.chainParameters.get(field)
  assert sameStateSnapshot(captured.derivedUpdate.value.currentUpdateState,
      source.currentUpdateState)
  profile.previous = ValidatorCount(0)
  assert not profile.valid
  assert uint64(captured.derivedStateProfile.value.previous) == 6
  profile = captured.derivedStateProfile.value
  profile.epochSlots = EpochSlots(0)
  assert not profile.valid
  profile = captured.derivedStateProfile.value
  profile.current = ValidatorCount(7)
  assert not profile.valid
proc cycle(source: PreparedCurrentChainUpdate) =
  ## Retire temporary decoded roster storage and copied producer/profile owners every cycle.
  let captured = captureCurrentProfile(source, limits).value
  assert captured.derivedStateProfile.value.valid
proc main() {.raises.} =
  ## Use actual current completion at ordinary and epoch-crossing children; no fabricated prepared owners.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let normal = currentCheckpointPrepared(currentChainFixture(base, available = true))
  let rotated = currentCheckpointPrepared(currentChainFixture(base, available = true,
      rotated = true))
  fail(1)
  assert captureCurrentProfile(default(PreparedCurrentChainUpdate), limits).error ==
      CurrentProfileError.InvalidUpdate
  assert default(DerivedCurrentProfile).derivedStateProfile.error ==
      CurrentProfileError.Uninitialized
  assert default(DerivedCurrentProfile).derivedParameters.error == CurrentProfileError.Uninitialized
  assert default(DerivedCurrentProfile).derivedUpdate.error == CurrentProfileError.Uninitialized
  assert captureCurrentProfile(normal, CurrentProfileLimits(validators: ElementLimit(6),
      bytes: ByteLimit(2016))).error == CurrentProfileError.LimitExceeded
  let items = captureCurrentProfile(normal, CurrentProfileLimits(validators: ElementLimit(5),
      bytes: ByteLimit(2017)))
  assert items.error == CurrentProfileError.PreviousFailure
  assert items.previousError == StateComponentError.LimitExceeded
  verify(normal)
  verify(rotated)
  assert calls() == 0
  for i in 0..<25: cycle(normal)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(normal)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_current_profile", 1000, before, finalBytes)
  fail(0)
  echo "state-current-profile: ok"
try:
  main()
except:
  quit(2) # Missing/malformed signed fixture cannot qualify producer profile evidence.
