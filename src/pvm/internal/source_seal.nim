# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Shared cold source-sealing state owned by either exclusive native-code cache, never an invocation.
import ./execution_types

type
  SourceSealInfo* = object       ## Copied source-entry observations freeze before an eager stream escapes.
    sealed*: bool
    candidates*, nativeEntries*, checkedEntries*, capacityDeferred*: uint64
    when defined(pvmSourceSealingReceipt):
      compilationPasses*: uint64 # CI-only attempted passes include unsuccessful native preparation.
  SourceSealPrice* = object ## Direct source-static pricing retains neither caller memo nor CPU gas.
    cost*: uint64
    error*: StepError
  SourceSeal* = object ## Auto-managed child of the existing code owner; no allocation until eager price/class tables are built.
    info*: SourceSealInfo
    prices*: seq[SourceSealPrice]
    when defined(pvmSourceSealingReceipt):
      entryKinds*: seq[uint8] # CI-only immutable source classes, not production layout or executable authority.
