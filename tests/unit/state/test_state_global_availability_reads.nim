# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated optional assignments retain nested guarantee/report lifetime and separate registration time.
import std/[assertions, syncio]
import ../../support/[proof_global_helpers, proof_global_report]
import ../../../src/state/proof/[global as proof_global, view as proof_view]
import ../../../src/codec/[bounded, assurances, guarantees]
import ../../../src/codec/state/[availability as state_availability, layout as state_layout,
    safrole as state_safrole, trie as state_trie]
proc main() {.raises.} =
  ## Cover present and absent core slots plus independently authenticated malformed outer framing.
  let config = AvailabilityConfig(guarantee: GuaranteeConfig(cores: CoreCount(2),
    validators: ValidatorCount(6), maxBytes: ByteLimit(60000)), maxPresent: ElementLimit(2),
        maxBytes: ByteLimit(65536))
  var guarantee = Guarantee(report: globalReport(), slot: GuaranteeSlot(21), credentialCount: 2)
  guarantee.credentials[1].validator = GuarantorIndex(1)
  let entry = availabilityStateEntry([presentAssignment(guarantee, AssignmentSlot(99)),
      absentAssignment()], config).value
  let view = globalView(@[entry], [entry.key])
  var owner = view.readGlobalAvailability(config).value
  assert owner.availabilityInfo.value.cores == 2 and owner.availabilityInfo.value.present == 1
  let retained = owner.availabilityAt(AssignmentCoreIndex(0)).value
  assert retained.present and uint32(retained.registered) == 99
  assert uint32(retained.guarantee.slot) == 21
  assert not owner.availabilityAt(AssignmentCoreIndex(1)).value.present
  owner = default(AvailabilitySnapshot)
  guarantee = default(Guarantee)
  assert uint32(retained.guarantee.slot) == 21
  assert default(ProofView).readGlobalAvailability(config).error == GlobalProofError.Uninitialized
  assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalAvailability(config).error ==
      GlobalProofError.MissingWitness
  assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalAvailability(config).error ==
      GlobalProofError.AbsentValue
  var policy = config
  policy.maxPresent = ElementLimit(0)
  assert view.readGlobalAvailability(policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.maxBytes = ByteLimit(entry.value.len-1)
  assert view.readGlobalAvailability(policy).error == GlobalProofError.LimitExceeded
  policy = config
  policy.guarantee.validators = ValidatorCount(0)
  assert view.readGlobalAvailability(policy).error == GlobalProofError.InvalidConfig
  for length in [0, 1, entry.value.len-5, entry.value.len-1]:
    # Probe the presence tag, nested guarantee, registration and final absent slot boundaries.
    var truncated = newSeq[byte](length)
    for i in 0..<length: truncated[i] = entry.value[i]
    assert globalView(@[StateEntry(key: entry.key, value: truncated)], [
        entry.key]).readGlobalAvailability(config).error == GlobalProofError.InvalidValue
  var malformed = entry.value
  malformed[0] = 2
  assert globalView(@[StateEntry(key: entry.key, value: malformed)], [
      entry.key]).readGlobalAvailability(config).error == GlobalProofError.InvalidValue
  var suffix = entry.value
  suffix.add(0)
  assert globalView(@[StateEntry(key: entry.key, value: suffix)], [
      entry.key]).readGlobalAvailability(config).error == GlobalProofError.InvalidValue
  echo "state-global-availability-reads: ok"
try:
  main()
except:
  quit(2) # Fixture/setup exceptions cannot count as the expected native success.
