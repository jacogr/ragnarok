# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every reusable phase keeps inactive success and parent reason payloads guarded.
import std/cmdline
import ../../src/state/accumulation/account/phase as accumulation_account_phase
import ../../src/state/accumulation/provision/phase as accumulation_provision_phase
import ../../src/state/accumulation/global/phase as accumulation_global_phase
import ../../src/state/accumulation/[coverage as accumulation_coverage,
    provisions as accumulation_provisions]
case paramStr(1)
of "account":
  let owner = default(AccumulationAccountPhaseResult[PreparedAccumulationAccountPhase])
  let refused = prepareAccumulationAccountPhase(default(PreparedAccumulationCoverage), default(AccumulationAccountPhaseLimits))
  let phase = default(PreparedAccumulationAccountPhase)
  case paramStr(2)
  of "refused": discard refused.value # Only actual selected alternatives authorize extraction.
  of "selection": discard owner.selectionFailure # Only actual selected alternatives authorize extraction.
  of "creation": discard owner.creationFailure # Only actual selected alternatives authorize extraction.
  of "write": discard owner.writeFailure # Only actual selected alternatives authorize extraction.
  of "store": discard owner.storeFailure # Only actual selected alternatives authorize extraction.
  of "info": discard phase.accountPhaseInfo.value # Only actual selected alternatives authorize extraction.
  of "coverage": discard phase.accountPhaseCoverage.value # Only actual selected alternatives authorize extraction.
  of "selection-owner": discard phase.accountPhaseSelection.value # Only actual selected alternatives authorize extraction.
  of "creation-owner": discard phase.accountPhaseCreation.value # Only actual selected alternatives authorize extraction.
  of "writes": discard phase.accountPhaseWrites.value # Only actual selected alternatives authorize extraction.
  of "snapshot": discard phase.accountPhaseSnapshot.value # Only actual selected alternatives authorize extraction.
  else: discard owner.value # Default reusable owners are not successful empty phases.
of "provision":
  let owner = default(AccumulationProvisionPhaseResult[PreparedAccumulationProvisionPhase])
  let refused = prepareAccumulationProvisionPhase(default(PreparedAccumulationAccountPhase),
      default(AccumulationProvisionUnionLimits))
  let phase = default(PreparedAccumulationProvisionPhase)
  case paramStr(2)
  of "refused": discard refused.value # Only actual selected alternatives authorize extraction.
  of "provision": discard owner.provisionFailure # Only actual selected alternatives authorize extraction.
  of "store": discard owner.storeFailure # Only actual selected alternatives authorize extraction.
  of "accounts": discard phase.provisionPhaseAccounts.value # Only actual selected alternatives authorize extraction.
  of "plan": discard phase.provisionPhasePlan.value # Only actual selected alternatives authorize extraction.
  of "snapshot": discard phase.provisionPhaseSnapshot.value # Only actual selected alternatives authorize extraction.
  else: discard owner.value # Default reusable owners are not successful empty phases.
of "global":
  let owner = default(AccumulationGlobalPhaseResult[PreparedAccumulationGlobalPhase])
  let refused = prepareAccumulationGlobalPhase(default(PreparedAccumulationProvisionPhase), default(AccumulationGlobalPhaseLimits))
  let phase = default(PreparedAccumulationGlobalPhase)
  case paramStr(2)
  of "refused": discard refused.value # Only actual selected alternatives authorize extraction.
  of "role": discard owner.roleFailure # Only actual selected alternatives authorize extraction.
  of "queue": discard owner.queueFailure # Only actual selected alternatives authorize extraction.
  of "staging": discard owner.stagingFailure # Only actual selected alternatives authorize extraction.
  of "store": discard owner.storeFailure # Only actual selected alternatives authorize extraction.
  of "info": discard phase.globalPhaseInfo.value # Only actual selected alternatives authorize extraction.
  of "provisions": discard phase.globalPhaseProvisions.value # Only actual selected alternatives authorize extraction.
  of "roles": discard phase.globalPhaseRoles.value # Only actual selected alternatives authorize extraction.
  of "snapshot": discard phase.globalPhaseSnapshot.value # Only actual selected alternatives authorize extraction.
  else: discard owner.value # Default reusable owners are not successful empty phases.
else: discard # The maintained plan names every intentional phase/refusal case.
