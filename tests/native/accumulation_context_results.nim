# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime selected-success probes for initial accumulation context fields and provenance.
## Each dynamic mode must terminate at its contract rather than expose a default successful context.

import std/cmdline
import ../../src/state/accumulation/[context as accumulation_context,
    invocation as accumulation_invocation]

# Dynamic selection retains a real preparation refusal without constant-invalid extraction at compilation.
let outcome = if paramStr(1) == "refused":
  prepareAccumulationContexts(default(PreparedAccumulationInvocation), default(AccumulationContextConfig))
else: default(AccumulationContextResult[PreparedAccumulationContexts]) # Default results contain no context.
let owner = default(InitialAccumulationContext)
let pair = default(PreparedAccumulationContexts)
let bound = default(BlockAccumulationContexts)
case paramStr(1)
of "info": discard owner.contextInfo.value # Missing provenance cannot be extracted.
of "self": discard owner.contextSelf.value # Missing provenance cannot be extracted.
of "invocation": discard owner.contextInvocation.value # Missing provenance cannot be extracted.
of "accounts": discard owner.contextAccounts.value # Missing provenance cannot be extracted.
of "queues": discard owner.contextQueues.value # Missing provenance cannot be extracted.
of "staging": discard owner.contextStaging.value # Missing provenance cannot be extracted.
of "privileges": discard owner.contextPrivileges.value # Missing provenance cannot be extracted.
of "dimension": discard pair.initialContext(AccumulationDimension.Regular).value # Missing provenance cannot be extracted.
of "projection": discard bound.contextProjection.value # Missing provenance cannot be extracted.
of "source": discard bound.contextBlockInvocation.value # Missing provenance cannot be extracted.
else: discard outcome.value # Actual/default refusal never exposes initial state.
