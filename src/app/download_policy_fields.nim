# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen v1 startup policy schema; include privately to share exact read/write field coverage.
## Every leaf is an existing public uint32/uint64 nominal policy; changes require version review.

template policyFields(policy, context, visit: untyped) {.untyped.} =
  ## Apply a typed visitor to every explicit v1 leaf; this contains no runtime reflection or inferred defaults.
  visit(context, "schedule.peers", policy.schedule.peers)
  visit(context, "schedule.attempts", policy.schedule.attempts)
  visit(context, "schedule.retryDelay", policy.schedule.retryDelay)
  visit(context, "input.blockBytes", policy.input.blockBytes)
  visit(context, "input.ancestorBytes", policy.input.ancestorBytes)
  visit(context, "input.ancestors", policy.input.ancestors)
  visit(context, "candidate.reporting.admission.frame.cores",
      policy.candidate.reporting.admission.frame.cores)
  visit(context, "candidate.reporting.admission.frame.validators",
      policy.candidate.reporting.admission.frame.validators)
  visit(context, "candidate.reporting.admission.frame.epochSlots",
      policy.candidate.reporting.admission.frame.epochSlots)
  visit(context, "candidate.reporting.admission.frame.ticketLimit",
      policy.candidate.reporting.admission.frame.ticketLimit)
  visit(context, "candidate.reporting.admission.frame.preimages.items",
      policy.candidate.reporting.admission.frame.preimages.items)
  visit(context, "candidate.reporting.admission.frame.preimages.perBlob",
      policy.candidate.reporting.admission.frame.preimages.perBlob)
  visit(context, "candidate.reporting.admission.frame.preimages.totalBlobBytes",
      policy.candidate.reporting.admission.frame.preimages.totalBlobBytes)
  visit(context, "candidate.reporting.admission.frame.maxBytes",
      policy.candidate.reporting.admission.frame.maxBytes)
  visit(context, "candidate.reporting.admission.maxParentHeaderBytes",
      policy.candidate.reporting.admission.maxParentHeaderBytes)
  visit(context, "candidate.reporting.disputes.rosters.cores",
      policy.candidate.reporting.disputes.rosters.cores)
  visit(context, "candidate.reporting.disputes.rosters.validators",
      policy.candidate.reporting.disputes.rosters.validators)
  visit(context, "candidate.reporting.disputes.rosters.maxBytes",
      policy.candidate.reporting.disputes.rosters.maxBytes)
  visit(context, "candidate.reporting.disputes.state.perSet",
      policy.candidate.reporting.disputes.state.perSet)
  visit(context, "candidate.reporting.disputes.state.totalItems",
      policy.candidate.reporting.disputes.state.totalItems)
  visit(context, "candidate.reporting.disputes.state.maxBytes",
      policy.candidate.reporting.disputes.state.maxBytes)
  visit(context, "candidate.reporting.disputes.availability.guarantee.cores",
      policy.candidate.reporting.disputes.availability.guarantee.cores)
  visit(context, "candidate.reporting.disputes.availability.guarantee.validators",
      policy.candidate.reporting.disputes.availability.guarantee.validators)
  visit(context, "candidate.reporting.disputes.availability.guarantee.maxBytes",
      policy.candidate.reporting.disputes.availability.guarantee.maxBytes)
  visit(context, "candidate.reporting.disputes.availability.maxPresent",
      policy.candidate.reporting.disputes.availability.maxPresent)
  visit(context, "candidate.reporting.disputes.availability.maxBytes",
      policy.candidate.reporting.disputes.availability.maxBytes)
  visit(context, "candidate.reporting.disputes.epochSlots",
      policy.candidate.reporting.disputes.epochSlots)
  visit(context, "candidate.reporting.disputes.maxExtrinsicBytes",
      policy.candidate.reporting.disputes.maxExtrinsicBytes)
  visit(context, "candidate.reporting.safrole.state.validators.cores",
      policy.candidate.reporting.safrole.state.validators.cores)
  visit(context, "candidate.reporting.safrole.state.validators.validators",
      policy.candidate.reporting.safrole.state.validators.validators)
  visit(context, "candidate.reporting.safrole.state.validators.maxBytes",
      policy.candidate.reporting.safrole.state.validators.maxBytes)
  visit(context, "candidate.reporting.safrole.state.epochSlots",
      policy.candidate.reporting.safrole.state.epochSlots)
  visit(context, "candidate.reporting.safrole.state.maxAccumulator",
      policy.candidate.reporting.safrole.state.maxAccumulator)
  visit(context, "candidate.reporting.safrole.state.maxBytes",
      policy.candidate.reporting.safrole.state.maxBytes)
  visit(context, "candidate.reporting.safrole.tailStart",
      policy.candidate.reporting.safrole.tailStart)
  visit(context, "candidate.reporting.safrole.blockTickets",
      policy.candidate.reporting.safrole.blockTickets)
  visit(context, "candidate.reporting.safrole.offenders",
      policy.candidate.reporting.safrole.offenders)
  visit(context, "candidate.reporting.safrole.maxHeaderBytes",
      policy.candidate.reporting.safrole.maxHeaderBytes)
  visit(context, "candidate.reporting.safrole.maxMarkerBytes",
      policy.candidate.reporting.safrole.maxMarkerBytes)
  visit(context, "candidate.reporting.availability.rosters.cores",
      policy.candidate.reporting.availability.rosters.cores)
  visit(context, "candidate.reporting.availability.rosters.validators",
      policy.candidate.reporting.availability.rosters.validators)
  visit(context, "candidate.reporting.availability.rosters.maxBytes",
      policy.candidate.reporting.availability.rosters.maxBytes)
  visit(context, "candidate.reporting.availability.assignments.guarantee.cores",
      policy.candidate.reporting.availability.assignments.guarantee.cores)
  visit(context, "candidate.reporting.availability.assignments.guarantee.validators",
      policy.candidate.reporting.availability.assignments.guarantee.validators)
  visit(context, "candidate.reporting.availability.assignments.guarantee.maxBytes",
      policy.candidate.reporting.availability.assignments.guarantee.maxBytes)
  visit(context, "candidate.reporting.availability.assignments.maxPresent",
      policy.candidate.reporting.availability.assignments.maxPresent)
  visit(context, "candidate.reporting.availability.assignments.maxBytes",
      policy.candidate.reporting.availability.assignments.maxBytes)
  visit(context, "candidate.reporting.availability.availableReports",
      policy.candidate.reporting.availability.availableReports)
  visit(context, "candidate.reporting.reports.credentials.assignments.roster.cores",
      policy.candidate.reporting.reports.credentials.assignments.roster.cores)
  visit(context, "candidate.reporting.reports.credentials.assignments.roster.validators",
      policy.candidate.reporting.reports.credentials.assignments.roster.validators)
  visit(context, "candidate.reporting.reports.credentials.assignments.roster.maxBytes",
      policy.candidate.reporting.reports.credentials.assignments.roster.maxBytes)
  visit(context, "candidate.reporting.reports.credentials.assignments.epochSlots",
      policy.candidate.reporting.reports.credentials.assignments.epochSlots)
  visit(context, "candidate.reporting.reports.credentials.assignments.rotationSlots",
      policy.candidate.reporting.reports.credentials.assignments.rotationSlots)
  visit(context, "candidate.reporting.reports.credentials.assignments.offenders",
      policy.candidate.reporting.reports.credentials.assignments.offenders)
  visit(context, "candidate.reporting.reports.credentials.maxBytes",
      policy.candidate.reporting.reports.credentials.maxBytes)
  visit(context, "candidate.reporting.reports.credentials.reporters",
      policy.candidate.reporting.reports.credentials.reporters)
  visit(context, "candidate.reporting.reports.policy.pools.cores",
      policy.candidate.reporting.reports.policy.pools.cores)
  visit(context, "candidate.reporting.reports.policy.pools.maxHashes",
      policy.candidate.reporting.reports.policy.pools.maxHashes)
  visit(context, "candidate.reporting.reports.policy.pools.maxBytes",
      policy.candidate.reporting.reports.policy.pools.maxBytes)
  visit(context, "candidate.reporting.reports.policy.accountBytes",
      policy.candidate.reporting.reports.policy.accountBytes)
  visit(context, "candidate.reporting.reports.policy.reportGas",
      policy.candidate.reporting.reports.policy.reportGas)
  visit(context, "candidate.reporting.reports.anchors.history.cores",
      policy.candidate.reporting.reports.anchors.history.cores)
  visit(context, "candidate.reporting.reports.anchors.history.blocks",
      policy.candidate.reporting.reports.anchors.history.blocks)
  visit(context, "candidate.reporting.reports.anchors.history.perBlock",
      policy.candidate.reporting.reports.anchors.history.perBlock)
  visit(context, "candidate.reporting.reports.anchors.history.totalPackages",
      policy.candidate.reporting.reports.anchors.history.totalPackages)
  visit(context, "candidate.reporting.reports.anchors.history.peaks",
      policy.candidate.reporting.reports.anchors.history.peaks)
  visit(context, "candidate.reporting.reports.anchors.history.maxBytes",
      policy.candidate.reporting.reports.anchors.history.maxBytes)
  visit(context, "candidate.reporting.reports.anchors.lookupAge",
      policy.candidate.reporting.reports.anchors.lookupAge)
  visit(context, "candidate.reporting.reports.ancestors.header.cores",
      policy.candidate.reporting.reports.ancestors.header.cores)
  visit(context, "candidate.reporting.reports.ancestors.header.authorValidators",
      policy.candidate.reporting.reports.ancestors.header.authorValidators)
  visit(context, "candidate.reporting.reports.ancestors.header.epochSlots",
      policy.candidate.reporting.reports.ancestors.header.epochSlots)
  visit(context, "candidate.reporting.reports.ancestors.header.maxBytes",
      policy.candidate.reporting.reports.ancestors.header.maxBytes)
  visit(context, "candidate.reporting.reports.ancestors.headers",
      policy.candidate.reporting.reports.ancestors.headers)
  visit(context, "candidate.reporting.reports.ancestors.maxBytes",
      policy.candidate.reporting.reports.ancestors.maxBytes)
  visit(context, "candidate.reporting.reports.packages.availability.guarantee.cores",
      policy.candidate.reporting.reports.packages.availability.guarantee.cores)
  visit(context, "candidate.reporting.reports.packages.availability.guarantee.validators",
      policy.candidate.reporting.reports.packages.availability.guarantee.validators)
  visit(context, "candidate.reporting.reports.packages.availability.guarantee.maxBytes",
      policy.candidate.reporting.reports.packages.availability.guarantee.maxBytes)
  visit(context, "candidate.reporting.reports.packages.availability.maxPresent",
      policy.candidate.reporting.reports.packages.availability.maxPresent)
  visit(context, "candidate.reporting.reports.packages.availability.maxBytes",
      policy.candidate.reporting.reports.packages.availability.maxBytes)
  visit(context, "candidate.reporting.reports.packages.queues.epochSlots",
      policy.candidate.reporting.reports.packages.queues.epochSlots)
  visit(context, "candidate.reporting.reports.packages.queues.cores",
      policy.candidate.reporting.reports.packages.queues.cores)
  visit(context, "candidate.reporting.reports.packages.queues.perSlot",
      policy.candidate.reporting.reports.packages.queues.perSlot)
  visit(context, "candidate.reporting.reports.packages.queues.totalItems",
      policy.candidate.reporting.reports.packages.queues.totalItems)
  visit(context, "candidate.reporting.reports.packages.queues.perDependencies",
      policy.candidate.reporting.reports.packages.queues.perDependencies)
  visit(context, "candidate.reporting.reports.packages.queues.totalDependencies",
      policy.candidate.reporting.reports.packages.queues.totalDependencies)
  visit(context, "candidate.reporting.reports.packages.queues.reportBytes",
      policy.candidate.reporting.reports.packages.queues.reportBytes)
  visit(context, "candidate.reporting.reports.packages.queues.maxBytes",
      policy.candidate.reporting.reports.packages.queues.maxBytes)
  visit(context, "candidate.reporting.reports.packages.indexItems",
      policy.candidate.reporting.reports.packages.indexItems)
  visit(context, "candidate.reporting.reports.judgments.perSet",
      policy.candidate.reporting.reports.judgments.perSet)
  visit(context, "candidate.reporting.reports.judgments.totalItems",
      policy.candidate.reporting.reports.judgments.totalItems)
  visit(context, "candidate.reporting.reports.judgments.maxBytes",
      policy.candidate.reporting.reports.judgments.maxBytes)
  visit(context, "candidate.queue.queues.epochSlots", policy.candidate.queue.queues.epochSlots)
  visit(context, "candidate.queue.queues.cores", policy.candidate.queue.queues.cores)
  visit(context, "candidate.queue.queues.perSlot", policy.candidate.queue.queues.perSlot)
  visit(context, "candidate.queue.queues.totalItems", policy.candidate.queue.queues.totalItems)
  visit(context, "candidate.queue.queues.perDependencies",
      policy.candidate.queue.queues.perDependencies)
  visit(context, "candidate.queue.queues.totalDependencies",
      policy.candidate.queue.queues.totalDependencies)
  visit(context, "candidate.queue.queues.reportBytes", policy.candidate.queue.queues.reportBytes)
  visit(context, "candidate.queue.queues.maxBytes", policy.candidate.queue.queues.maxBytes)
  visit(context, "candidate.queue.items", policy.candidate.queue.items)
  visit(context, "candidate.queue.dependencies", policy.candidate.queue.dependencies)
  visit(context, "candidate.round.reportGas", policy.candidate.round.reportGas)
  visit(context, "candidate.round.blockGas", policy.candidate.round.blockGas)
  visit(context, "candidate.round.privileges.cores", policy.candidate.round.privileges.cores)
  visit(context, "candidate.round.privileges.maxAlways",
      policy.candidate.round.privileges.maxAlways)
  visit(context, "candidate.round.privileges.maxBytes", policy.candidate.round.privileges.maxBytes)
  visit(context, "candidate.round.operands.reports", policy.candidate.round.operands.reports)
  visit(context, "candidate.round.operands.operands", policy.candidate.round.operands.operands)
  visit(context, "candidate.round.operands.services", policy.candidate.round.operands.services)
  visit(context, "candidate.round.operands.totalBlobBytes",
      policy.candidate.round.operands.totalBlobBytes)
  visit(context, "candidate.round.operands.totalBytes", policy.candidate.round.operands.totalBytes)
  visit(context, "candidate.round.operands.operand.outputBytes",
      policy.candidate.round.operands.operand.outputBytes)
  visit(context, "candidate.round.operands.operand.authBytes",
      policy.candidate.round.operands.operand.authBytes)
  visit(context, "candidate.round.operands.operand.totalBlobBytes",
      policy.candidate.round.operands.operand.totalBlobBytes)
  visit(context, "candidate.round.operands.operand.maxBytes",
      policy.candidate.round.operands.operand.maxBytes)
  visit(context, "candidate.round.inputs.inputs", policy.candidate.round.inputs.inputs)
  visit(context, "candidate.round.inputs.allowances", policy.candidate.round.inputs.allowances)
  visit(context, "candidate.round.inputs.services", policy.candidate.round.inputs.services)
  visit(context, "candidate.execution.completion.services",
      policy.candidate.execution.completion.services)
  visit(context, "candidate.execution.completion.batch.accounts",
      policy.candidate.execution.completion.batch.accounts)
  visit(context, "candidate.execution.completion.batch.deletedAccounts",
      policy.candidate.execution.completion.batch.deletedAccounts)
  visit(context, "candidate.execution.completion.batch.createdAccounts",
      policy.candidate.execution.completion.batch.createdAccounts)
  visit(context, "candidate.execution.completion.batch.selfWrites",
      policy.candidate.execution.completion.batch.selfWrites)
  visit(context, "candidate.execution.completion.batch.selfValueBytes",
      policy.candidate.execution.completion.batch.selfValueBytes)
  visit(context, "candidate.execution.completion.batch.assignCores",
      policy.candidate.execution.completion.batch.assignCores)
  visit(context, "candidate.execution.completion.batch.assignBytes",
      policy.candidate.execution.completion.batch.assignBytes)
  visit(context, "candidate.execution.completion.batch.managerEntries",
      policy.candidate.execution.completion.batch.managerEntries)
  visit(context, "candidate.execution.completion.batch.managerBytes",
      policy.candidate.execution.completion.batch.managerBytes)
  visit(context, "candidate.execution.completion.batch.stagingValidators",
      policy.candidate.execution.completion.batch.stagingValidators)
  visit(context, "candidate.execution.completion.batch.stagingBytes",
      policy.candidate.execution.completion.batch.stagingBytes)
  visit(context, "candidate.execution.completion.batch.provisions.contexts",
      policy.candidate.execution.completion.batch.provisions.contexts)
  visit(context, "candidate.execution.completion.batch.provisions.values.items",
      policy.candidate.execution.completion.batch.provisions.values.items)
  visit(context, "candidate.execution.completion.batch.provisions.values.perBlob",
      policy.candidate.execution.completion.batch.provisions.values.perBlob)
  visit(context, "candidate.execution.completion.batch.provisions.values.totalBlobBytes",
      policy.candidate.execution.completion.batch.provisions.values.totalBlobBytes)
  visit(context, "candidate.execution.completion.batch.provisions.encodedBytes",
      policy.candidate.execution.completion.batch.provisions.encodedBytes)
  visit(context, "candidate.execution.preimageBytes", policy.candidate.execution.preimageBytes)
  visit(context, "candidate.execution.probes", policy.candidate.execution.probes)
  visit(context, "candidate.execution.initialization.envelope",
      policy.candidate.execution.initialization.envelope)
  visit(context, "candidate.execution.initialization.program",
      policy.candidate.execution.initialization.program)
  visit(context, "candidate.execution.initialization.jumps",
      policy.candidate.execution.initialization.jumps)
  visit(context, "candidate.execution.initialization.pages",
      policy.candidate.execution.initialization.pages)
  visit(context, "candidate.execution.contexts.validators",
      policy.candidate.execution.contexts.validators)
  visit(context, "candidate.execution.contexts.queues.cores",
      policy.candidate.execution.contexts.queues.cores)
  visit(context, "candidate.execution.contexts.queues.maxHashes",
      policy.candidate.execution.contexts.queues.maxHashes)
  visit(context, "candidate.execution.contexts.queues.maxBytes",
      policy.candidate.execution.contexts.queues.maxBytes)
  visit(context, "candidate.execution.contexts.staging.cores",
      policy.candidate.execution.contexts.staging.cores)
  visit(context, "candidate.execution.contexts.staging.validators",
      policy.candidate.execution.contexts.staging.validators)
  visit(context, "candidate.execution.contexts.staging.maxBytes",
      policy.candidate.execution.contexts.staging.maxBytes)
  visit(context, "candidate.execution.contexts.privileges.cores",
      policy.candidate.execution.contexts.privileges.cores)
  visit(context, "candidate.execution.contexts.privileges.maxAlways",
      policy.candidate.execution.contexts.privileges.maxAlways)
  visit(context, "candidate.execution.contexts.privileges.maxBytes",
      policy.candidate.execution.contexts.privileges.maxBytes)
  visit(context, "candidate.execution.contexts.totalBytes",
      policy.candidate.execution.contexts.totalBytes)
  visit(context, "candidate.execution.fetch.items", policy.candidate.execution.fetch.items)
  visit(context, "candidate.execution.fetch.bytes", policy.candidate.execution.fetch.bytes)
  visit(context, "candidate.execution.fetch.operand.outputBytes",
      policy.candidate.execution.fetch.operand.outputBytes)
  visit(context, "candidate.execution.fetch.operand.authBytes",
      policy.candidate.execution.fetch.operand.authBytes)
  visit(context, "candidate.execution.fetch.operand.totalBlobBytes",
      policy.candidate.execution.fetch.operand.totalBlobBytes)
  visit(context, "candidate.execution.fetch.operand.maxBytes",
      policy.candidate.execution.fetch.operand.maxBytes)
  visit(context, "candidate.execution.copyBytes", policy.candidate.execution.copyBytes)
  visit(context, "candidate.execution.steps", policy.candidate.execution.steps)
  visit(context, "candidate.execution.calls", policy.candidate.execution.calls)
  visit(context, "candidate.execution.cycles", policy.candidate.execution.cycles)
  visit(context, "candidate.execution.provisions.items",
      policy.candidate.execution.provisions.items)
  visit(context, "candidate.execution.provisions.perBlob",
      policy.candidate.execution.provisions.perBlob)
  visit(context, "candidate.execution.provisions.totalBlobBytes",
      policy.candidate.execution.provisions.totalBlobBytes)
  visit(context, "candidate.execution.transfers", policy.candidate.execution.transfers)
  visit(context, "candidate.execution.accountWriteKeys",
      policy.candidate.execution.accountWriteKeys)
  visit(context, "candidate.execution.createdAccounts", policy.candidate.execution.createdAccounts)
  visit(context, "candidate.execution.deletedAccounts", policy.candidate.execution.deletedAccounts)
  visit(context, "candidate.driver.preparation.selection.executions",
      policy.candidate.driver.preparation.selection.executions)
  visit(context, "candidate.driver.preparation.selection.transfers",
      policy.candidate.driver.preparation.selection.transfers)
  visit(context, "candidate.driver.preparation.selection.memoBytes",
      policy.candidate.driver.preparation.selection.memoBytes)
  visit(context, "candidate.driver.preparation.selection.reports",
      policy.candidate.driver.preparation.selection.reports)
  visit(context, "candidate.driver.preparation.selection.digests",
      policy.candidate.driver.preparation.selection.digests)
  visit(context, "candidate.driver.preparation.operands.reports",
      policy.candidate.driver.preparation.operands.reports)
  visit(context, "candidate.driver.preparation.operands.operands",
      policy.candidate.driver.preparation.operands.operands)
  visit(context, "candidate.driver.preparation.operands.services",
      policy.candidate.driver.preparation.operands.services)
  visit(context, "candidate.driver.preparation.operands.totalBlobBytes",
      policy.candidate.driver.preparation.operands.totalBlobBytes)
  visit(context, "candidate.driver.preparation.operands.totalBytes",
      policy.candidate.driver.preparation.operands.totalBytes)
  visit(context, "candidate.driver.preparation.operands.operand.outputBytes",
      policy.candidate.driver.preparation.operands.operand.outputBytes)
  visit(context, "candidate.driver.preparation.operands.operand.authBytes",
      policy.candidate.driver.preparation.operands.operand.authBytes)
  visit(context, "candidate.driver.preparation.operands.operand.totalBlobBytes",
      policy.candidate.driver.preparation.operands.operand.totalBlobBytes)
  visit(context, "candidate.driver.preparation.operands.operand.maxBytes",
      policy.candidate.driver.preparation.operands.operand.maxBytes)
  visit(context, "candidate.driver.preparation.inputs.inputs",
      policy.candidate.driver.preparation.inputs.inputs)
  visit(context, "candidate.driver.preparation.inputs.allowances",
      policy.candidate.driver.preparation.inputs.allowances)
  visit(context, "candidate.driver.preparation.inputs.services",
      policy.candidate.driver.preparation.inputs.services)
  visit(context, "candidate.driver.execution.completion.services",
      policy.candidate.driver.execution.completion.services)
  visit(context, "candidate.driver.execution.completion.batch.accounts",
      policy.candidate.driver.execution.completion.batch.accounts)
  visit(context, "candidate.driver.execution.completion.batch.deletedAccounts",
      policy.candidate.driver.execution.completion.batch.deletedAccounts)
  visit(context, "candidate.driver.execution.completion.batch.createdAccounts",
      policy.candidate.driver.execution.completion.batch.createdAccounts)
  visit(context, "candidate.driver.execution.completion.batch.selfWrites",
      policy.candidate.driver.execution.completion.batch.selfWrites)
  visit(context, "candidate.driver.execution.completion.batch.selfValueBytes",
      policy.candidate.driver.execution.completion.batch.selfValueBytes)
  visit(context, "candidate.driver.execution.completion.batch.assignCores",
      policy.candidate.driver.execution.completion.batch.assignCores)
  visit(context, "candidate.driver.execution.completion.batch.assignBytes",
      policy.candidate.driver.execution.completion.batch.assignBytes)
  visit(context, "candidate.driver.execution.completion.batch.managerEntries",
      policy.candidate.driver.execution.completion.batch.managerEntries)
  visit(context, "candidate.driver.execution.completion.batch.managerBytes",
      policy.candidate.driver.execution.completion.batch.managerBytes)
  visit(context, "candidate.driver.execution.completion.batch.stagingValidators",
      policy.candidate.driver.execution.completion.batch.stagingValidators)
  visit(context, "candidate.driver.execution.completion.batch.stagingBytes",
      policy.candidate.driver.execution.completion.batch.stagingBytes)
  visit(context, "candidate.driver.execution.completion.batch.provisions.contexts",
      policy.candidate.driver.execution.completion.batch.provisions.contexts)
  visit(context, "candidate.driver.execution.completion.batch.provisions.values.items",
      policy.candidate.driver.execution.completion.batch.provisions.values.items)
  visit(context, "candidate.driver.execution.completion.batch.provisions.values.perBlob",
      policy.candidate.driver.execution.completion.batch.provisions.values.perBlob)
  visit(context, "candidate.driver.execution.completion.batch.provisions.values.totalBlobBytes",
      policy.candidate.driver.execution.completion.batch.provisions.values.totalBlobBytes)
  visit(context, "candidate.driver.execution.completion.batch.provisions.encodedBytes",
      policy.candidate.driver.execution.completion.batch.provisions.encodedBytes)
  visit(context, "candidate.driver.execution.preimageBytes",
      policy.candidate.driver.execution.preimageBytes)
  visit(context, "candidate.driver.execution.probes", policy.candidate.driver.execution.probes)
  visit(context, "candidate.driver.execution.initialization.envelope",
      policy.candidate.driver.execution.initialization.envelope)
  visit(context, "candidate.driver.execution.initialization.program",
      policy.candidate.driver.execution.initialization.program)
  visit(context, "candidate.driver.execution.initialization.jumps",
      policy.candidate.driver.execution.initialization.jumps)
  visit(context, "candidate.driver.execution.initialization.pages",
      policy.candidate.driver.execution.initialization.pages)
  visit(context, "candidate.driver.execution.contexts.validators",
      policy.candidate.driver.execution.contexts.validators)
  visit(context, "candidate.driver.execution.contexts.queues.cores",
      policy.candidate.driver.execution.contexts.queues.cores)
  visit(context, "candidate.driver.execution.contexts.queues.maxHashes",
      policy.candidate.driver.execution.contexts.queues.maxHashes)
  visit(context, "candidate.driver.execution.contexts.queues.maxBytes",
      policy.candidate.driver.execution.contexts.queues.maxBytes)
  visit(context, "candidate.driver.execution.contexts.staging.cores",
      policy.candidate.driver.execution.contexts.staging.cores)
  visit(context, "candidate.driver.execution.contexts.staging.validators",
      policy.candidate.driver.execution.contexts.staging.validators)
  visit(context, "candidate.driver.execution.contexts.staging.maxBytes",
      policy.candidate.driver.execution.contexts.staging.maxBytes)
  visit(context, "candidate.driver.execution.contexts.privileges.cores",
      policy.candidate.driver.execution.contexts.privileges.cores)
  visit(context, "candidate.driver.execution.contexts.privileges.maxAlways",
      policy.candidate.driver.execution.contexts.privileges.maxAlways)
  visit(context, "candidate.driver.execution.contexts.privileges.maxBytes",
      policy.candidate.driver.execution.contexts.privileges.maxBytes)
  visit(context, "candidate.driver.execution.contexts.totalBytes",
      policy.candidate.driver.execution.contexts.totalBytes)
  visit(context, "candidate.driver.execution.fetch.items",
      policy.candidate.driver.execution.fetch.items)
  visit(context, "candidate.driver.execution.fetch.bytes",
      policy.candidate.driver.execution.fetch.bytes)
  visit(context, "candidate.driver.execution.fetch.operand.outputBytes",
      policy.candidate.driver.execution.fetch.operand.outputBytes)
  visit(context, "candidate.driver.execution.fetch.operand.authBytes",
      policy.candidate.driver.execution.fetch.operand.authBytes)
  visit(context, "candidate.driver.execution.fetch.operand.totalBlobBytes",
      policy.candidate.driver.execution.fetch.operand.totalBlobBytes)
  visit(context, "candidate.driver.execution.fetch.operand.maxBytes",
      policy.candidate.driver.execution.fetch.operand.maxBytes)
  visit(context, "candidate.driver.execution.copyBytes",
      policy.candidate.driver.execution.copyBytes)
  visit(context, "candidate.driver.execution.steps", policy.candidate.driver.execution.steps)
  visit(context, "candidate.driver.execution.calls", policy.candidate.driver.execution.calls)
  visit(context, "candidate.driver.execution.cycles", policy.candidate.driver.execution.cycles)
  visit(context, "candidate.driver.execution.provisions.items",
      policy.candidate.driver.execution.provisions.items)
  visit(context, "candidate.driver.execution.provisions.perBlob",
      policy.candidate.driver.execution.provisions.perBlob)
  visit(context, "candidate.driver.execution.provisions.totalBlobBytes",
      policy.candidate.driver.execution.provisions.totalBlobBytes)
  visit(context, "candidate.driver.execution.transfers",
      policy.candidate.driver.execution.transfers)
  visit(context, "candidate.driver.execution.accountWriteKeys",
      policy.candidate.driver.execution.accountWriteKeys)
  visit(context, "candidate.driver.execution.createdAccounts",
      policy.candidate.driver.execution.createdAccounts)
  visit(context, "candidate.driver.execution.deletedAccounts",
      policy.candidate.driver.execution.deletedAccounts)
  visit(context, "candidate.driver.depth", policy.candidate.driver.depth)
  visit(context, "candidate.finalization.rounds", policy.candidate.finalization.rounds)
  visit(context, "candidate.finalization.executions", policy.candidate.finalization.executions)
  visit(context, "candidate.finalization.log.items", policy.candidate.finalization.log.items)
  visit(context, "candidate.finalization.log.maxBytes", policy.candidate.finalization.log.maxBytes)
  visit(context, "composition.history.reports", policy.composition.history.reports)
  visit(context, "composition.history.queues.epochSlots",
      policy.composition.history.queues.epochSlots)
  visit(context, "composition.history.queues.cores", policy.composition.history.queues.cores)
  visit(context, "composition.history.queues.perSlot", policy.composition.history.queues.perSlot)
  visit(context, "composition.history.queues.totalItems",
      policy.composition.history.queues.totalItems)
  visit(context, "composition.history.queues.perDependencies",
      policy.composition.history.queues.perDependencies)
  visit(context, "composition.history.queues.totalDependencies",
      policy.composition.history.queues.totalDependencies)
  visit(context, "composition.history.queues.reportBytes",
      policy.composition.history.queues.reportBytes)
  visit(context, "composition.history.queues.maxBytes", policy.composition.history.queues.maxBytes)
  visit(context, "composition.ready.items", policy.composition.ready.items)
  visit(context, "composition.ready.dependencies", policy.composition.ready.dependencies)
  visit(context, "composition.ready.queues.epochSlots", policy.composition.ready.queues.epochSlots)
  visit(context, "composition.ready.queues.cores", policy.composition.ready.queues.cores)
  visit(context, "composition.ready.queues.perSlot", policy.composition.ready.queues.perSlot)
  visit(context, "composition.ready.queues.totalItems", policy.composition.ready.queues.totalItems)
  visit(context, "composition.ready.queues.perDependencies",
      policy.composition.ready.queues.perDependencies)
  visit(context, "composition.ready.queues.totalDependencies",
      policy.composition.ready.queues.totalDependencies)
  visit(context, "composition.ready.queues.reportBytes",
      policy.composition.ready.queues.reportBytes)
  visit(context, "composition.ready.queues.maxBytes", policy.composition.ready.queues.maxBytes)
  visit(context, "composition.recent.headerBytes", policy.composition.recent.headerBytes)
  visit(context, "composition.recent.outputs.items", policy.composition.recent.outputs.items)
  visit(context, "composition.recent.outputs.maxBytes", policy.composition.recent.outputs.maxBytes)
  visit(context, "composition.recent.history.cores", policy.composition.recent.history.cores)
  visit(context, "composition.recent.history.blocks", policy.composition.recent.history.blocks)
  visit(context, "composition.recent.history.perBlock", policy.composition.recent.history.perBlock)
  visit(context, "composition.recent.history.totalPackages",
      policy.composition.recent.history.totalPackages)
  visit(context, "composition.recent.history.peaks", policy.composition.recent.history.peaks)
  visit(context, "composition.recent.history.maxBytes", policy.composition.recent.history.maxBytes)
  visit(context, "composition.times.statistics.rounds", policy.composition.times.statistics.rounds)
  visit(context, "composition.times.statistics.gasRows",
      policy.composition.times.statistics.gasRows)
  visit(context, "composition.times.statistics.transfers",
      policy.composition.times.statistics.transfers)
  visit(context, "composition.times.statistics.reports",
      policy.composition.times.statistics.reports)
  visit(context, "composition.times.statistics.digests",
      policy.composition.times.statistics.digests)
  visit(context, "composition.times.statistics.services",
      policy.composition.times.statistics.services)
  visit(context, "composition.times.accounts.services", policy.composition.times.accounts.services)
  visit(context, "composition.times.accounts.writes", policy.composition.times.accounts.writes)
  visit(context, "composition.times.accounts.bytes", policy.composition.times.accounts.bytes)
  visit(context, "composition.validators.chapterBytes", policy.composition.validators.chapterBytes)
  visit(context, "composition.validators.validators", policy.composition.validators.validators)
  visit(context, "composition.validators.services", policy.composition.validators.services)
  visit(context, "composition.validators.componentBytes",
      policy.composition.validators.componentBytes)
  visit(context, "composition.validators.preimages", policy.composition.validators.preimages)
  visit(context, "composition.validators.preimageBytes",
      policy.composition.validators.preimageBytes)
  visit(context, "composition.validators.projection.rows",
      policy.composition.validators.projection.rows)
  visit(context, "composition.validators.projection.assurances",
      policy.composition.validators.projection.assurances)
  visit(context, "composition.validators.projection.reporters",
      policy.composition.validators.projection.reporters)
  visit(context, "composition.validators.projection.comparisons",
      policy.composition.validators.projection.comparisons)
  visit(context, "composition.activity.componentBytes", policy.composition.activity.componentBytes)
  visit(context, "composition.activity.preimages.items",
      policy.composition.activity.preimages.items)
  visit(context, "composition.activity.preimages.perBlob",
      policy.composition.activity.preimages.perBlob)
  visit(context, "composition.activity.preimages.totalBlobBytes",
      policy.composition.activity.preimages.totalBlobBytes)
  visit(context, "composition.activity.incoming", policy.composition.activity.incoming)
  visit(context, "composition.activity.available", policy.composition.activity.available)
  visit(context, "composition.activity.digests", policy.composition.activity.digests)
  visit(context, "composition.activity.assurances", policy.composition.activity.assurances)
  visit(context, "composition.activity.provisions", policy.composition.activity.provisions)
  visit(context, "composition.activity.accumulation", policy.composition.activity.accumulation)
  visit(context, "composition.activity.services", policy.composition.activity.services)
  visit(context, "composition.activity.activityBytes", policy.composition.activity.activityBytes)
  visit(context, "composition.preimages.items", policy.composition.preimages.items)
  visit(context, "composition.preimages.bytes", policy.composition.preimages.bytes)
  visit(context, "composition.authorization.guarantees",
      policy.composition.authorization.guarantees)
  visit(context, "composition.authorization.inputHashes",
      policy.composition.authorization.inputHashes)
  visit(context, "composition.authorization.inputBytes",
      policy.composition.authorization.inputBytes)
  visit(context, "composition.authorization.outputHashes",
      policy.composition.authorization.outputHashes)
  visit(context, "composition.authorization.outputBytes",
      policy.composition.authorization.outputBytes)
  visit(context, "composition.consensus.chapterBytes", policy.composition.consensus.chapterBytes)
  visit(context, "composition.consensus.totalBytes", policy.composition.consensus.totalBytes)
  visit(context, "stream.readBytes", policy.stream.readBytes)
  visit(context, "stream.writeBytes", policy.stream.writeBytes)
  visit(context, "stream.timeout", policy.stream.timeout)
  visit(context, "attemptTimeout", policy.attemptTimeout)
