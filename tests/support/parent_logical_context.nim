# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine selected-view logical seed helper uses explicit independent profile/global/raw-key policies.
import ./[parent_profile_context, parent_globals_context, supplied_logical_context, current_typed_context]
import ../../src/state/[parent_profile, parent_globals, parent_logical]
import ../../src/chain/provider
proc selectedLogicalParent*(view: ChainView): ParentLogicalResult[SelectedLogicalParent] =
  ## Author no replacement map: whole logical matching verifies declarations read from the exact original complete fixture.
  let profile = captureParentProfile(view, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  captureLogicalParent(globals, currentSuppliedServices(profile.parentContext.value.state), suppliedLogicalTestLimits)
