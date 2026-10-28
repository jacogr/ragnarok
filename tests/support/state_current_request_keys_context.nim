# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual nonempty configured selected logical parent and genuine identity-preserving successor.
import ./state_accumulation_current_chain_context
import ./state_current_checkpoint_context
import ./state_current_namespace_context
import ./state_parent_profile_context
import ./state_parent_globals_context
import ./codec_supplied_logical_context
import ./state_current_identity_context
import ../../src/state/parent_profile as state_parent_profile
import ../../src/state/parent_globals as state_parent_globals
import ../../src/state/parent_logical as state_parent_logical
import ../../src/state/current_identities as state_current_identities
import ../../src/state/current_request_keys as state_current_request_keys
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
const currentRequestKeyTestLimits* = CurrentRequestKeyLimits(services: ElementLimit(2),
    requests: ElementLimit(4), bytes: ByteLimit(4096))
proc namespacePreservation*(base: OwnedReport): PreservedCurrentIdentities =
  ## Complete matching consumes only original actual selected map/raw identities, never a replacement child or synthetic update.
  let seeds = namespaceSeeds()
  let fixture = currentChainFixture(base, completeState = true, serviceNamespaces = seeds)
  let profile = captureParentProfile(fixture.currentChainSeeded, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let services = currentNamespaceServices(profile.parentContext.value.state, seeds)
  let parent = captureLogicalParent(globals, services, suppliedLogicalTestLimits).value
  preserveCurrentIdentities(parent, currentCheckpointPrepared(fixture),
      currentIdentityTestLimits).value
