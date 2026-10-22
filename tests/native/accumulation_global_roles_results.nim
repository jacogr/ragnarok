# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and refused role owners cannot expose identities, source outcomes, snapshots or wire storage.
import std/cmdline
import ../../src/state/[accumulation_global_roles, accumulation_annulment]
import ../../src/codec/state_privileges
let argument = paramStr(1)
let owner = default(PreparedAccumulationGlobalRoles)
let refused = if argument == "default": default(AccumulationGlobalRoleResult[PreparedAccumulationGlobalRoles])
  else: prepareAccumulationGlobalRoles(default(PreparedAccumulationAnnulment), default(
      AccumulationGlobalRoleLimits))
case argument
of "info": discard owner.globalRolesInfo.value # No fabricated shape.
of "source": discard owner.globalRolesSource.value # No fabricated cancellation certificate.
of "privileges": discard owner.globalRolesPrivileges.value # No default manager dictionary.
of "entry": discard owner.globalRolesEntry.value # No fabricated canonical bytes.
of "manager": discard owner.globalManagerOutcome.value # No fabricated authority outcome.
of "delegator": discard owner.globalDelegatorOutcome.value # No fabricated staging source.
of "registrar": discard owner.globalRegistrarOutcome.value # No fabricated registrar source.
of "assigner": discard owner.globalAssignerOutcomeAt(PrivilegeCoreIndex(0)).value # No fabricated queue source.
else: discard refused.value # Failure carries its reason alone.
