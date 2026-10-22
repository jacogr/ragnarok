# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: PrivilegeCoreIndex but got: PreparedAccumulationAnnulment","early":["globalAssignerOutcomeAt(","[2] expected: PrivilegeCoreIndex but got: PreparedAccumulationAnnulment"]}

## Work and core identities cannot alias wire extents or source owners.
import ../../../src/state/[accumulation_global_roles, accumulation_annulment]
import ../../../src/codec/[bounded, state_privileges]
discard globalAssignerOutcomeAt(default(PreparedAccumulationGlobalRoles), default(PreparedAccumulationAnnulment))
