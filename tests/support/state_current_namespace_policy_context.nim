# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit independently stated CLI producer/continuation policies supplement existing source qualification and execution configuration.
import ./state_current_identity_context
import ./state_current_namespace_refresh_context
import ../../src/app/current_download_policy as app_current_download_policy
import ../../src/state/logical_continuation as state_logical_continuation
import ../../src/state/accumulation_effects as state_accumulation_effects
import ../../src/state/accumulation_storage_history as state_accumulation_storage_history
import ../../src/state/request_identity_history as state_request_identity_history
import ../../src/codec/bounded as codec_bounded
proc namespacePolicyTestLimits*(): CurrentNamespacePolicy =
  ## Complete reviewed policy values permit two service namespaces while leaving service membership tracing explicitly disabled.
  let logical = namespaceLogicalLimits()
  result = CurrentNamespacePolicy(continuation: LogicalContinuationLimits(
    identity: currentIdentityTestLimits,
    checks: ElementLimit(16384), scratchBytes: ByteLimit(262144),
        projection: namespaceRefreshLimits.projection,
    profile: logical.profile, globals: logical.globals, logical: logical.logical),
    initial: NamespaceHostLimits(storage: AccumulationStorageFactLimits(items: ElementLimit(4),
        perKey: ByteLimit(8), totalKeyBytes: ByteLimit(32)), requests: ElementLimit(8)),
    storage: StorageHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(16),
        facts: ElementLimit(32), bytes: ByteLimit(65536)),
    requests: RequestIdentityHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(16),
        facts: ElementLimit(32), bytes: ByteLimit(65536)))
  result.round = result.initial
