# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime success/variant guards for global reads and planned partial-view outcomes.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_proof_global_helpers
import ../../src/state/proof_global as state_proof_global
import ../../src/state/proof_plan as state_proof_plan
import ../../src/state/planned_proof as state_planned_proof
import ../../src/state/proof_view as state_proof_view
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/state_composition as codec_state_composition
let mode = paramStr(1)
case mode
of "global-default":
  let guarded = default(GlobalProofResult[StateTime])
  discard guarded.value # A default result must not fabricate a timeslot.
of "global-missing":
  let view = globalView(@[timeEntry(StateTime(3))], [entropyEntry(default(StateEntropy)).key])
  let guarded = view.readGlobalTime
  discard guarded.value # Missing evidence is not authenticated absence or a zero time.
of "global-limit":
  let view = globalView(@[entropyEntry(default(StateEntropy))], [entropyEntry(default(
      StateEntropy)).key])
  let guarded = view.readGlobalEntropy(ByteLimit(127))
  discard guarded.value # A byte-policy refusal cannot publish a truncated entropy value.
of "plan-duplicate":
  let guarded = planProofChapters([StateChapterId.Time, StateChapterId.Time], ElementLimit(2))
  discard guarded.value # Invalid selector capture has no requested-key owner.
of "planned-default":
  let guarded = default(PlannedProofResult[ProofView])
  discard guarded.value # A default planned result has no partial-view owner.
of "planned-proof-reason":
  let guarded = default(PlannedProofResult[ProofView])
  discard guarded.proofError # Only actual ProofFailure selects a nested authentication reason.
of "planned-limit":
  let view = globalView(@[timeEntry(StateTime(3))], [timeEntry(StateTime(3)).key])
  let plan = planProofChapter(StateChapterId.Time, ElementLimit(1)).value
  let guarded = projectPlannedProofs(view, plan, ProofViewLimits())
  discard guarded.value # Projection refusal cannot publish a verified prefix.
of "ok":
  let view = globalView(@[timeEntry(StateTime(3))], [timeEntry(StateTime(3)).key])
  let plan = planProofChapter(StateChapterId.Time, ElementLimit(1)).value
  let exact = projectPlannedProofs(view, plan, viewLimits).value
  assert uint32(exact.readGlobalTime.value) == 3 # The same driver must support actual completed extraction.
  echo "state-global-read-contracts: ok"
else:
  quit(2) # Unknown cases cannot satisfy the successful control or an intended assertion failure.
