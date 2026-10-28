# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine selected-view logical seed helper uses explicit independent profile/global/raw-key policies.
import ./state_parent_profile_context
import ./state_parent_globals_context
import ./codec_supplied_logical_context
import ./state_current_typed_context
import ../../src/state/parent_profile as state_parent_profile
import ../../src/state/parent_globals as state_parent_globals
import ../../src/state/parent_logical as state_parent_logical
import ../../src/chain/provider as chain_provider
proc selectedLogicalParent*(view: ChainView): ParentLogicalResult[SelectedLogicalParent] =
  ## Author no replacement map: whole logical matching verifies declarations read from the exact original complete fixture.
  let profile = captureParentProfile(view, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  captureLogicalParent(globals, currentSuppliedServices(profile.parentContext.value.state), suppliedLogicalTestLimits)
