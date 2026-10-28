# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit actual executed-namespace current refresh stages with independent resource policies.
import ./state_current_namespace_transition_context
import ./state_current_identity_context
import ./state_current_logical_refresh_context
import ../../src/state/current_identities as state_current_identities
import ../../src/state/current_request_keys as state_current_request_keys
import ../../src/state/current_refresh_plan as state_current_refresh_plan
import ../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../src/state/supplied_services as state_supplied_services
import ../../src/state/current_logical as state_current_logical
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/codec/bounded as codec_bounded
type NamespaceRefreshStages* = object ## Test descriptors hold only genuine successful opaque stages; no raw mutable declaration grants producer authority.
  identities*: PreservedCurrentIdentities
  keys*: CurrentRequestKeys
  reconstruction*: CurrentRefreshPlan
  complete*: CurrentLogicalRefreshPlan
const namespaceRequestLimits* = CurrentRequestKeyLimits(services: ElementLimit(2),
    requests: ElementLimit(16), bytes: ByteLimit(4096))
const namespaceRefreshLimits* = CurrentRefreshLimits(projection: SuppliedServicesLimits(
    services: ElementLimit(2), facts: ElementLimit(64), perValue: ByteLimit(65536),
    bytes: ByteLimit(262144)), checks: ElementLimit(64), wireBytes: ByteLimit(512))
proc namespaceLogicalLimits*(): CurrentLogicalRefreshLimits =
  ## Explicit scan ceiling covers complete code namespaces without deriving trust or replacing execution parameters.
  result = currentLogicalRefreshTestLimits
  result.checks = ElementLimit(128)
proc namespaceRefreshStages*(fixture: CurrentNamespaceTransition): NamespaceRefreshStages =
  ## Every stage consumes only its original successful opaque predecessor and fixed independently stated policies.
  let identities = preserveCurrentIdentities(fixture.parent, fixture.update,
      currentIdentityTestLimits).value
  let keys = captureCurrentRequestKeys(identities, namespaceRequestLimits).value
  let reconstruction = planCurrentRefresh(keys, namespaceRefreshLimits).value
  let complete = planCurrentLogicalRefresh(reconstruction, namespaceLogicalLimits()).value
  NamespaceRefreshStages(identities: identities, keys: keys, reconstruction: reconstruction,
      complete: complete)
proc namespaceRefreshStages*(prior: CurrentLogicalState,
    update: PreparedCurrentChainUpdate): NamespaceRefreshStages =
  ## A genuinely completed current source reuses the same frozen key/reconstruction/full qualification path without a startup wrapper.
  let identities = preserveCurrentIdentities(prior, update, currentIdentityTestLimits).value
  let keys = captureCurrentRequestKeys(identities, namespaceRequestLimits).value
  let reconstruction = planCurrentRefresh(keys, namespaceRefreshLimits).value
  let complete = planCurrentLogicalRefresh(reconstruction, namespaceLogicalLimits()).value
  NamespaceRefreshStages(identities: identities, keys: keys, reconstruction: reconstruction,
      complete: complete)
