# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit actual executed-namespace current refresh stages with independent resource policies.
import ./[current_namespace_transition_context, current_identity_context, current_logical_refresh_context]
import ../../src/state/[current_identities, current_request_keys, current_refresh_plan,
    current_logical_refresh, supplied_services, current_logical, accumulation_current_update]
import ../../src/codec/bounded
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
