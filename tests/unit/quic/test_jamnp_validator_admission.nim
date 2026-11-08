# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent role budgets and canonical epoch/finality witnesses for validator admission.

import std/[assertions, syncio]
import ../../support/[jamnp_topology_fixture, jamnp_policy_tls]
import ../../../src/jamnp-s/[admission, topology]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/state/[safrole, consensus]

proc selected(rosters: array[3, seq[StateValidator]], seed: BlockSnapshotResult,
    atSlot = 12'u32, duration = 12, suffix = false): ChainView =
  ## Link exact parent commitment and clock through the real canonical-view admission boundary.
  let child = topologyCaptured(rosters, atSlot = atSlot, duration = duration, parent = seed,
      suffix = suffix)
  assert child.error == GenesisError.None, "child.error == GenesisError.None"
  let advanced = advanceView(genesisView(seed), child)
  assert advanced.error == ViewAdvanceError.None, "advanced.error == ViewAdvanceError.None"
  advanced.value

proc finalized(view: ChainView): ChainView =
  ## Supply explicit host finality for the retained canonical best, never derive it from progress.
  let reported = finalizeView(view, view.bestBlock.value.blockHash)
  assert reported.error == ViewFinalizeError.None, "reported.error == ViewFinalizeError.None"
  reported.value

proc initialize(seed: BlockSnapshotResult): ValidatorAdmission =
  ## Small independent quotas expose improper borrowing of reserved capacity.
  let projected = captureValidatorTopology(seed, topologyLimits())
  assert projected.error == TopologyError.None, "projected.error == TopologyError.None"
  let made = initValidatorAdmission(projected.value, topologyKey(20), 2, 1, 1)
  assert made.error == AdmissionError.None, "made.error == AdmissionError.None"
  made.value

proc reservations() =
  ## All rejected paths preserve independent desired counts and the exact native slot occupancy.
  let old = [topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)]
  let seed = topologyCaptured(old)
  var policy = initialize(seed)
  assert policy.capacity == 4, "policy.capacity == 4"
  assert policy.admitAuthenticated(PeerSlot(0), topologyKey(21), true).value == PeerClass.Validator, "policy.admitAuthenticated(PeerSlot(0), topologyKey(21), true).value == PeerClass.Validator"
  assert policy.admitAuthenticated(PeerSlot(1), topologyKey(61), false).value ==
      PeerClass.Validator, "policy.admitAuthenticated(PeerSlot(1), topologyKey(61), false).value == PeerClass.Validator"
  assert policy.admitAuthenticated(PeerSlot(2), topologyKey(101), true).error ==
      AdmissionError.Full, "policy.admitAuthenticated(PeerSlot(2), topologyKey(101), true).error == AdmissionError.Full"
  assert policy.admitAuthenticated(PeerSlot(2), topologyKey(700), false).value == PeerClass.Other, "policy.admitAuthenticated(PeerSlot(2), topologyKey(700), false).value == PeerClass.Other"
  assert policy.admitAuthenticated(PeerSlot(3), topologyKey(701), false).error ==
      AdmissionError.Full, "policy.admitAuthenticated(PeerSlot(3), topologyKey(701), false).error == AdmissionError.Full"
  assert policy.admitAuthenticated(PeerSlot(3), topologyKey(702), true).value == PeerClass.Builder, "policy.admitAuthenticated(PeerSlot(3), topologyKey(702), true).value == PeerClass.Builder"
  assert policy.count(PeerClass.Validator) == 2 and policy.count(PeerClass.Builder) == 1 and
      policy.count(PeerClass.Other) == 1, "policy.count(PeerClass.Validator) == 2 and policy.count(PeerClass.Builder) == 1 and policy.count(PeerClass.Other) == 1"
  # Plain value policy copies own independent mutable reservations while sharing immutable topology.
  var copied = policy
  assert copied.release(PeerSlot(0)), "copied policy owns an independent retained slot"
  assert copied.count(PeerClass.Validator) == 1 and policy.count(PeerClass.Validator) == 2, "copy mutation must not change original reservations"
  assert policy.announcements(PeerSlot(0)), "policy.announcements(PeerSlot(0))" # Previous-epoch indices0/1 share a row.
  assert not policy.announcements(PeerSlot(1)), "not policy.announcements(PeerSlot(1))" # Different epochs with different ordinals are not grid neighbours.
  assert policy.announcements(PeerSlot(3)), "policy.announcements(PeerSlot(3))" # Builder capacity grants no special UP0 restriction.
  assert policy.release(PeerSlot(2)) and not policy.release(PeerSlot(2)), "policy.release(PeerSlot(2)) and not policy.release(PeerSlot(2))"
  assert policy.admitAuthenticated(PeerSlot(2), topologyKey(21), false).error ==
      AdmissionError.Duplicate, "policy.admitAuthenticated(PeerSlot(2), topologyKey(21), false).error == AdmissionError.Duplicate"
  assert policy.admitAuthenticated(PeerSlot(2), topologyKey(20), false).error ==
      AdmissionError.InvalidIdentity, "policy.admitAuthenticated(PeerSlot(2), topologyKey(20), false).error == AdmissionError.InvalidIdentity"
  assert policy.admitAuthenticated(PeerSlot(2), nullValidator().ed25519, true).error ==
      AdmissionError.InvalidIdentity, "policy.admitAuthenticated(PeerSlot(2), nullValidator().ed25519, true).error == AdmissionError.InvalidIdentity"
  assert policy.admitAuthenticated(PeerSlot(high(uint64)), topologyKey(703), false).error ==
      AdmissionError.InvalidSlot, "policy.admitAuthenticated(PeerSlot(high(uint64)), topologyKey(703), false).error == AdmissionError.InvalidSlot"
  assert policy.admitAuthenticated(PeerSlot(3), topologyKey(703), false).error ==
      AdmissionError.InvalidSlot, "policy.admitAuthenticated(PeerSlot(3), topologyKey(703), false).error == AdmissionError.InvalidSlot"
  let next = [topologyRecords(3, 6), topologyRecords(4, 9), topologyRecords(5, 12)]
  let incoming = selected(next, seed)
  assert policy.advance(incoming, StateTime(1000), topologyLimits()).value == EpochUpdate.Held, "policy.advance(incoming, StateTime(1000), topologyLimits()).value == EpochUpdate.Held"
  assert policy.count(PeerClass.Validator) == 2 and policy.topology.slot ==
      7, "policy.count(PeerClass.Validator) == 2 and policy.topology.slot == 7" # Elapsed time alone cannot rotate authority.
  let known = finalizeView(incoming, seed.value.blockHash)
  assert known.error == ViewFinalizeError.None, "known.error == ViewFinalizeError.None"
  assert policy.advance(known.value, StateTime(1000), topologyLimits()).value ==
      EpochUpdate.Held, "policy.advance(known.value, StateTime(1000), topologyLimits()).value == EpochUpdate.Held" # Earlier finality does not suffice.
  assert policy.advance(finalized(incoming), StateTime(12), topologyLimits()).value ==
      EpochUpdate.Held, "policy.advance(finalized(incoming), StateTime(12), topologyLimits()).value == EpochUpdate.Held"
  assert policy.count(PeerClass.Validator) == 2, "policy.count(PeerClass.Validator) == 2" # New-epoch finality alone still waits one slot.
  let malformed = selected(next, seed, suffix = true)
  assert policy.advance(finalized(malformed), StateTime(13), topologyLimits()).error ==
      AdmissionError.InvalidState, "policy.advance(finalized(malformed), StateTime(13), topologyLimits()).error == AdmissionError.InvalidState"
  assert policy.count(PeerClass.Validator) == 2 and policy.topology.slot == 7,
      "policy.count(PeerClass.Validator) == 2 and policy.topology.slot == 7" # Refusal is atomic.
  assert policy.advance(finalized(incoming), StateTime(13), topologyLimits()).value ==
      EpochUpdate.Applied, "policy.advance(finalized(incoming), StateTime(13), topologyLimits()).value == EpochUpdate.Applied"
  assert policy.topology.slot == 12 and policy.count(PeerClass.Validator) == 0, "policy.topology.slot == 12 and policy.count(PeerClass.Validator) == 0"
  assert policy.count(PeerClass.Other) == 1 and policy.count(PeerClass.Builder) == 1, "policy.count(PeerClass.Other) == 1 and policy.count(PeerClass.Builder) == 1"
  # Native-slot order preserves each peer's original builder request during reclassification.
  assert not policy.retiring(PeerSlot(0)) and not policy.retiring(PeerSlot(1)) and policy.retiring(
      PeerSlot(3)), "demotion must preserve the original reservation request"
  assert not policy.announcements(PeerSlot(3)), "retiring peers cannot open UP0"
  assert policy.admitAuthenticated(PeerSlot(2), topologyKey(702), false).error ==
      AdmissionError.Duplicate, "retiring identity remains owned"
  assert policy.release(PeerSlot(3)) and policy.count(PeerClass.Builder) == 1, "retiring closure must not decrement the replacement's builder count"
  assert policy.release(PeerSlot(1)) and policy.count(PeerClass.Other) == 0, "ordinary closure releases its own reservation"
  assert policy.release(PeerSlot(0)) and policy.count(PeerClass.Builder) == 0, "demoted builder closure releases its reclassified reservation"
  assert policy.advance(genesisView(seed), StateTime(1000), topologyLimits()).error ==
      AdmissionError.Stale, "policy.advance(genesisView(seed), StateTime(1000), topologyLimits()).error == AdmissionError.Stale"
  assert not policy.release(PeerSlot(high(uint64))), "not policy.release(PeerSlot(high(uint64)))"
  assert default(ValidatorAdmission).capacity == 0, "default(ValidatorAdmission).capacity == 0"
  var absent = default(ValidatorAdmission)
  assert absent.admitAuthenticated(PeerSlot(0), topologyKey(21), false).error ==
      AdmissionError.Uninitialized, "absent.admitAuthenticated(PeerSlot(0), topologyKey(21), false).error == AdmissionError.Uninitialized"

proc delay() =
  ## Non-tiny E exercises E div30 rather than only the minimum one-slot delay.
  let rosters = [topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)]
  let seed = topologyCaptured(rosters, duration = 90)
  assert seed.error == GenesisError.None, "seed.error == GenesisError.None"
  let projected = captureValidatorTopology(seed, topologyLimits(duration = 90))
  assert projected.error == TopologyError.None, "projected.error == TopologyError.None"
  var policy = initValidatorAdmission(projected.value, topologyKey(20), 2).value
  let view = finalized(selected(rosters, seed, atSlot = 90, duration = 90))
  assert policy.advance(view, StateTime(92), topologyLimits(duration = 90)).value ==
      EpochUpdate.Held, "policy.advance(view, StateTime(92), topologyLimits(duration = 90)).value == EpochUpdate.Held"
  assert policy.topology.slot == 7, "policy.topology.slot == 7"
  assert policy.advance(view, StateTime(93), topologyLimits(duration = 90)).value ==
      EpochUpdate.Applied, "policy.advance(view, StateTime(93), topologyLimits(duration = 90)).value == EpochUpdate.Applied"

proc epochBoundaries() =
  ## Finalized descendants cover the first epoch block, and maximum clocks cannot wrap delay arithmetic.
  let rosters = [topologyRecords(0, 6), topologyRecords(1, 9), topologyRecords(2, 12)]
  let seed = topologyCaptured(rosters)
  let first = selected(rosters, seed)
  let child = topologyCaptured(rosters, atSlot = 13, parent = first.bestBlock)
  let advanced = advanceView(first, child)
  assert advanced.error == ViewAdvanceError.None, "same-epoch descendant must link exactly"
  var policy = initialize(seed)
  assert policy.advance(finalized(advanced.value), StateTime(12), topologyLimits()).value ==
      EpochUpdate.Held, "future best must not change connectivity"
  assert policy.advance(finalized(advanced.value), StateTime(13), topologyLimits()).value ==
      EpochUpdate.Applied, "finalized descendant establishes first-block finality"
  var skipped = initialize(seed)
  let far = finalized(selected(rosters, seed, atSlot = high(uint32)))
  assert skipped.advance(far, StateTime(high(uint32)), topologyLimits()).value ==
      EpochUpdate.Applied, "maximum clock and skipped epochs retain checked delay arithmetic"

reservations()
delay()
epochBoundaries()
try:
  policyTls()
except:
  quit 2 # Native fixture IO/setup exceptions cannot satisfy admission evidence.
echo "validator admission: isolated budgets, grid eligibility and finalized epoch delay passed"
