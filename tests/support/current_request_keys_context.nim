# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual nonempty configured selected logical parent and genuine identity-preserving successor.
import ./[accumulation_current_chain_context, current_checkpoint_context, current_namespace_context,
    parent_profile_context, parent_globals_context, supplied_logical_context, current_identity_context]
import ../../src/state/parent/[profile as parent_profile, globals as parent_globals,
    logical as parent_logical]
import ../../src/state/current/[identities as current_identities,
    request_keys as current_request_keys]
import ../../src/codec/[bounded, report_owned]
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
