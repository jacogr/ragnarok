# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen explicit current v1 resource schema; no runtime reflection or legacy ceiling inference.

template currentPolicyFields(policy, context, visit: untyped) {.untyped.} =
  ## Visit each reviewed current leaf exactly once for atomic assignment and complete serialization.
  visit(context, "schedule.peers",
      policy.schedule.peers)
  visit(context, "schedule.attempts",
      policy.schedule.attempts)
  visit(context, "schedule.retryDelay",
      policy.schedule.retryDelay)
  visit(context, "input.blockBytes",
      policy.input.blockBytes)
  visit(context, "input.ancestorBytes",
      policy.input.ancestorBytes)
  visit(context, "input.ancestors",
      policy.input.ancestors)
  visit(context, "input.discoverAncestors",
      policy.input.discoverAncestors)
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
  visit(context, "candidate.queue.queues.epochSlots",
      policy.candidate.queue.queues.epochSlots)
  visit(context, "candidate.queue.queues.cores",
      policy.candidate.queue.queues.cores)
  visit(context, "candidate.queue.queues.perSlot",
      policy.candidate.queue.queues.perSlot)
  visit(context, "candidate.queue.queues.totalItems",
      policy.candidate.queue.queues.totalItems)
  visit(context, "candidate.queue.queues.perDependencies",
      policy.candidate.queue.queues.perDependencies)
  visit(context, "candidate.queue.queues.totalDependencies",
      policy.candidate.queue.queues.totalDependencies)
  visit(context, "candidate.queue.queues.reportBytes",
      policy.candidate.queue.queues.reportBytes)
  visit(context, "candidate.queue.queues.maxBytes",
      policy.candidate.queue.queues.maxBytes)
  visit(context, "candidate.queue.items",
      policy.candidate.queue.items)
  visit(context, "candidate.queue.dependencies",
      policy.candidate.queue.dependencies)
  visit(context, "candidate.round.reportGas",
      policy.candidate.round.reportGas)
  visit(context, "candidate.round.blockGas",
      policy.candidate.round.blockGas)
  visit(context, "candidate.round.privileges.cores",
      policy.candidate.round.privileges.cores)
  visit(context, "candidate.round.privileges.maxAlways",
      policy.candidate.round.privileges.maxAlways)
  visit(context, "candidate.round.privileges.maxBytes",
      policy.candidate.round.privileges.maxBytes)
  visit(context, "candidate.round.operands.reports",
      policy.candidate.round.operands.reports)
  visit(context, "candidate.round.operands.operands",
      policy.candidate.round.operands.operands)
  visit(context, "candidate.round.operands.services",
      policy.candidate.round.operands.services)
  visit(context, "candidate.round.operands.totalBlobBytes",
      policy.candidate.round.operands.totalBlobBytes)
  visit(context, "candidate.round.operands.totalBytes",
      policy.candidate.round.operands.totalBytes)
  visit(context, "candidate.round.operands.operand.outputBytes",
      policy.candidate.round.operands.operand.outputBytes)
  visit(context, "candidate.round.operands.operand.authBytes",
      policy.candidate.round.operands.operand.authBytes)
  visit(context, "candidate.round.operands.operand.totalBlobBytes",
      policy.candidate.round.operands.operand.totalBlobBytes)
  visit(context, "candidate.round.operands.operand.maxBytes",
      policy.candidate.round.operands.operand.maxBytes)
  visit(context, "candidate.round.inputs.inputs",
      policy.candidate.round.inputs.inputs)
  visit(context, "candidate.round.inputs.allowances",
      policy.candidate.round.inputs.allowances)
  visit(context, "candidate.round.inputs.services",
      policy.candidate.round.inputs.services)
  visit(context, "candidate.completion.execution.initial.guests.services",
      policy.candidate.completion.execution.initial.guests.services)
  visit(context, "candidate.completion.execution.initial.guests.preimageBytes",
      policy.candidate.completion.execution.initial.guests.preimageBytes)
  visit(context, "candidate.completion.execution.initial.guests.probes",
      policy.candidate.completion.execution.initial.guests.probes)
  visit(context, "candidate.completion.execution.initial.guests.initialization.envelope",
      policy.candidate.completion.execution.initial.guests.initialization.envelope)
  visit(context, "candidate.completion.execution.initial.guests.initialization.program",
      policy.candidate.completion.execution.initial.guests.initialization.program)
  visit(context, "candidate.completion.execution.initial.guests.initialization.jumps",
      policy.candidate.completion.execution.initial.guests.initialization.jumps)
  visit(context, "candidate.completion.execution.initial.guests.initialization.pages",
      policy.candidate.completion.execution.initial.guests.initialization.pages)
  visit(context, "candidate.completion.execution.initial.guests.contexts.validators",
      policy.candidate.completion.execution.initial.guests.contexts.validators)
  visit(context, "candidate.completion.execution.initial.guests.contexts.queues.cores",
      policy.candidate.completion.execution.initial.guests.contexts.queues.cores)
  visit(context, "candidate.completion.execution.initial.guests.contexts.queues.maxHashes",
      policy.candidate.completion.execution.initial.guests.contexts.queues.maxHashes)
  visit(context, "candidate.completion.execution.initial.guests.contexts.queues.maxBytes",
      policy.candidate.completion.execution.initial.guests.contexts.queues.maxBytes)
  visit(context, "candidate.completion.execution.initial.guests.contexts.staging.cores",
      policy.candidate.completion.execution.initial.guests.contexts.staging.cores)
  visit(context, "candidate.completion.execution.initial.guests.contexts.staging.validators",
      policy.candidate.completion.execution.initial.guests.contexts.staging.validators)
  visit(context, "candidate.completion.execution.initial.guests.contexts.staging.maxBytes",
      policy.candidate.completion.execution.initial.guests.contexts.staging.maxBytes)
  visit(context, "candidate.completion.execution.initial.guests.contexts.privileges.cores",
      policy.candidate.completion.execution.initial.guests.contexts.privileges.cores)
  visit(context, "candidate.completion.execution.initial.guests.contexts.privileges.maxAlways",
      policy.candidate.completion.execution.initial.guests.contexts.privileges.maxAlways)
  visit(context, "candidate.completion.execution.initial.guests.contexts.privileges.maxBytes",
      policy.candidate.completion.execution.initial.guests.contexts.privileges.maxBytes)
  visit(context, "candidate.completion.execution.initial.guests.contexts.totalBytes",
      policy.candidate.completion.execution.initial.guests.contexts.totalBytes)
  visit(context, "candidate.completion.execution.initial.guests.fetch.items",
      policy.candidate.completion.execution.initial.guests.fetch.items)
  visit(context, "candidate.completion.execution.initial.guests.fetch.bytes",
      policy.candidate.completion.execution.initial.guests.fetch.bytes)
  visit(context, "candidate.completion.execution.initial.guests.fetch.operand.outputBytes",
      policy.candidate.completion.execution.initial.guests.fetch.operand.outputBytes)
  visit(context, "candidate.completion.execution.initial.guests.fetch.operand.authBytes",
      policy.candidate.completion.execution.initial.guests.fetch.operand.authBytes)
  visit(context, "candidate.completion.execution.initial.guests.fetch.operand.totalBlobBytes",
      policy.candidate.completion.execution.initial.guests.fetch.operand.totalBlobBytes)
  visit(context, "candidate.completion.execution.initial.guests.fetch.operand.maxBytes",
      policy.candidate.completion.execution.initial.guests.fetch.operand.maxBytes)
  visit(context, "candidate.completion.execution.initial.guests.copyBytes",
      policy.candidate.completion.execution.initial.guests.copyBytes)
  visit(context, "candidate.completion.execution.initial.guests.steps",
      policy.candidate.completion.execution.initial.guests.steps)
  visit(context, "candidate.completion.execution.initial.guests.calls",
      policy.candidate.completion.execution.initial.guests.calls)
  visit(context, "candidate.completion.execution.initial.guests.cycles",
      policy.candidate.completion.execution.initial.guests.cycles)
  visit(context, "candidate.completion.execution.initial.guests.provisions.items",
      policy.candidate.completion.execution.initial.guests.provisions.items)
  visit(context, "candidate.completion.execution.initial.guests.provisions.perBlob",
      policy.candidate.completion.execution.initial.guests.provisions.perBlob)
  visit(context, "candidate.completion.execution.initial.guests.provisions.totalBlobBytes",
      policy.candidate.completion.execution.initial.guests.provisions.totalBlobBytes)
  visit(context, "candidate.completion.execution.initial.guests.transfers",
      policy.candidate.completion.execution.initial.guests.transfers)
  visit(context, "candidate.completion.execution.initial.guests.accountWriteKeys",
      policy.candidate.completion.execution.initial.guests.accountWriteKeys)
  visit(context, "candidate.completion.execution.initial.guests.createdAccounts",
      policy.candidate.completion.execution.initial.guests.createdAccounts)
  visit(context, "candidate.completion.execution.initial.guests.deletedAccounts",
      policy.candidate.completion.execution.initial.guests.deletedAccounts)
  visit(context, "candidate.completion.execution.initial.guests.modifiedAccounts",
      policy.candidate.completion.execution.initial.guests.modifiedAccounts)
  visit(context, "candidate.completion.execution.initial.guests.accountWriteFacts",
      policy.candidate.completion.execution.initial.guests.accountWriteFacts)
  visit(context, "candidate.completion.execution.initial.guests.annulment.outcomes",
      policy.candidate.completion.execution.initial.guests.annulment.outcomes)
  visit(context, "candidate.completion.execution.initial.guests.annulment.modified",
      policy.candidate.completion.execution.initial.guests.annulment.modified)
  visit(context, "candidate.completion.execution.initial.guests.annulment.checks",
      policy.candidate.completion.execution.initial.guests.annulment.checks)
  visit(context, "candidate.completion.execution.initial.guests.coverage.services",
      policy.candidate.completion.execution.initial.guests.coverage.services)
  visit(context, "candidate.completion.execution.initial.guests.coverage.executed",
      policy.candidate.completion.execution.initial.guests.coverage.executed)
  visit(context, "candidate.completion.execution.initial.guests.coverage.skipped",
      policy.candidate.completion.execution.initial.guests.coverage.skipped)
  visit(context, "candidate.completion.execution.initial.guests.coverage.absent",
      policy.candidate.completion.execution.initial.guests.coverage.absent)
  visit(context, "candidate.completion.execution.initial.guests.coverage.checks",
      policy.candidate.completion.execution.initial.guests.coverage.checks)
  visit(context, "candidate.completion.execution.initial.guests.coverage.gas",
      policy.candidate.completion.execution.initial.guests.coverage.gas)
  visit(context, "candidate.completion.execution.initial.accounts.entries",
      policy.candidate.completion.execution.initial.accounts.entries)
  visit(context, "candidate.completion.execution.initial.accounts.providers",
      policy.candidate.completion.execution.initial.accounts.providers)
  visit(context, "candidate.completion.execution.initial.accounts.selection.accounts",
      policy.candidate.completion.execution.initial.accounts.selection.accounts)
  visit(context, "candidate.completion.execution.initial.accounts.selection.outcomes",
      policy.candidate.completion.execution.initial.accounts.selection.outcomes)
  visit(context, "candidate.completion.execution.initial.accounts.selection.checks",
      policy.candidate.completion.execution.initial.accounts.selection.checks)
  visit(context, "candidate.completion.execution.initial.accounts.selection.skipped",
      policy.candidate.completion.execution.initial.accounts.selection.skipped)
  visit(context, "candidate.completion.execution.initial.accounts.creation.outcomes",
      policy.candidate.completion.execution.initial.accounts.creation.outcomes)
  visit(context, "candidate.completion.execution.initial.accounts.creation.creations",
      policy.candidate.completion.execution.initial.accounts.creation.creations)
  visit(context, "candidate.completion.execution.initial.accounts.creation.accounts",
      policy.candidate.completion.execution.initial.accounts.creation.accounts)
  visit(context, "candidate.completion.execution.initial.accounts.creation.checks",
      policy.candidate.completion.execution.initial.accounts.creation.checks)
  visit(context, "candidate.completion.execution.initial.accounts.writes.accounts",
      policy.candidate.completion.execution.initial.accounts.writes.accounts)
  visit(context, "candidate.completion.execution.initial.accounts.writes.facts",
      policy.candidate.completion.execution.initial.accounts.writes.facts)
  visit(context, "candidate.completion.execution.initial.accounts.writes.writes",
      policy.candidate.completion.execution.initial.accounts.writes.writes)
  visit(context, "candidate.completion.execution.initial.accounts.writes.checks",
      policy.candidate.completion.execution.initial.accounts.writes.checks)
  visit(context, "candidate.completion.execution.initial.accounts.writes.valueBytes",
      policy.candidate.completion.execution.initial.accounts.writes.valueBytes)
  visit(context, "candidate.completion.execution.initial.provisions.contexts",
      policy.candidate.completion.execution.initial.provisions.contexts)
  visit(context, "candidate.completion.execution.initial.provisions.values.items",
      policy.candidate.completion.execution.initial.provisions.values.items)
  visit(context, "candidate.completion.execution.initial.provisions.values.perBlob",
      policy.candidate.completion.execution.initial.provisions.values.perBlob)
  visit(context, "candidate.completion.execution.initial.provisions.values.totalBlobBytes",
      policy.candidate.completion.execution.initial.provisions.values.totalBlobBytes)
  visit(context, "candidate.completion.execution.initial.provisions.encodedBytes",
      policy.candidate.completion.execution.initial.provisions.encodedBytes)
  visit(context, "candidate.completion.execution.initial.globals.roles.privileges.cores",
      policy.candidate.completion.execution.initial.globals.roles.privileges.cores)
  visit(context, "candidate.completion.execution.initial.globals.roles.privileges.maxAlways",
      policy.candidate.completion.execution.initial.globals.roles.privileges.maxAlways)
  visit(context, "candidate.completion.execution.initial.globals.roles.privileges.maxBytes",
      policy.candidate.completion.execution.initial.globals.roles.privileges.maxBytes)
  visit(context, "candidate.completion.execution.initial.globals.roles.outcomes",
      policy.candidate.completion.execution.initial.globals.roles.outcomes)
  visit(context, "candidate.completion.execution.initial.globals.roles.checks",
      policy.candidate.completion.execution.initial.globals.roles.checks)
  visit(context, "candidate.completion.execution.initial.globals.roles.totalBytes",
      policy.candidate.completion.execution.initial.globals.roles.totalBytes)
  visit(context, "candidate.completion.execution.initial.globals.queues.cores",
      policy.candidate.completion.execution.initial.globals.queues.cores)
  visit(context, "candidate.completion.execution.initial.globals.queues.maxHashes",
      policy.candidate.completion.execution.initial.globals.queues.maxHashes)
  visit(context, "candidate.completion.execution.initial.globals.queues.maxBytes",
      policy.candidate.completion.execution.initial.globals.queues.maxBytes)
  visit(context, "candidate.completion.execution.initial.globals.staging.cores",
      policy.candidate.completion.execution.initial.globals.staging.cores)
  visit(context, "candidate.completion.execution.initial.globals.staging.validators",
      policy.candidate.completion.execution.initial.globals.staging.validators)
  visit(context, "candidate.completion.execution.initial.globals.staging.maxBytes",
      policy.candidate.completion.execution.initial.globals.staging.maxBytes)
  visit(context, "candidate.completion.execution.initial.globals.totalBytes",
      policy.candidate.completion.execution.initial.globals.totalBytes)
  visit(context, "candidate.completion.execution.initial.outputs.outcomes",
      policy.candidate.completion.execution.initial.outputs.outcomes)
  visit(context, "candidate.completion.execution.initial.outputs.log.items",
      policy.candidate.completion.execution.initial.outputs.log.items)
  visit(context, "candidate.completion.execution.initial.outputs.log.maxBytes",
      policy.candidate.completion.execution.initial.outputs.log.maxBytes)
  visit(context, "candidate.completion.execution.initial.transfers.sources",
      policy.candidate.completion.execution.initial.transfers.sources)
  visit(context, "candidate.completion.execution.initial.transfers.transfers",
      policy.candidate.completion.execution.initial.transfers.transfers)
  visit(context, "candidate.completion.execution.initial.transfers.memoBytes",
      policy.candidate.completion.execution.initial.transfers.memoBytes)
  visit(context, "candidate.completion.execution.initial.pending.sources",
      policy.candidate.completion.execution.initial.pending.sources)
  visit(context, "candidate.completion.execution.initial.pending.transfers",
      policy.candidate.completion.execution.initial.pending.transfers)
  visit(context, "candidate.completion.execution.initial.pending.memoBytes",
      policy.candidate.completion.execution.initial.pending.memoBytes)
  visit(context, "candidate.completion.execution.planning.reports",
      policy.candidate.completion.execution.planning.reports)
  visit(context, "candidate.completion.execution.planning.digests",
      policy.candidate.completion.execution.planning.digests)
  visit(context, "candidate.completion.execution.planning.operands.reports",
      policy.candidate.completion.execution.planning.operands.reports)
  visit(context, "candidate.completion.execution.planning.operands.operands",
      policy.candidate.completion.execution.planning.operands.operands)
  visit(context, "candidate.completion.execution.planning.operands.services",
      policy.candidate.completion.execution.planning.operands.services)
  visit(context, "candidate.completion.execution.planning.operands.totalBlobBytes",
      policy.candidate.completion.execution.planning.operands.totalBlobBytes)
  visit(context, "candidate.completion.execution.planning.operands.totalBytes",
      policy.candidate.completion.execution.planning.operands.totalBytes)
  visit(context, "candidate.completion.execution.planning.operands.operand.outputBytes",
      policy.candidate.completion.execution.planning.operands.operand.outputBytes)
  visit(context, "candidate.completion.execution.planning.operands.operand.authBytes",
      policy.candidate.completion.execution.planning.operands.operand.authBytes)
  visit(context, "candidate.completion.execution.planning.operands.operand.totalBlobBytes",
      policy.candidate.completion.execution.planning.operands.operand.totalBlobBytes)
  visit(context, "candidate.completion.execution.planning.operands.operand.maxBytes",
      policy.candidate.completion.execution.planning.operands.operand.maxBytes)
  visit(context, "candidate.completion.execution.planning.inputs.inputs",
      policy.candidate.completion.execution.planning.inputs.inputs)
  visit(context, "candidate.completion.execution.planning.inputs.allowances",
      policy.candidate.completion.execution.planning.inputs.allowances)
  visit(context, "candidate.completion.execution.planning.inputs.services",
      policy.candidate.completion.execution.planning.inputs.services)
  visit(context, "candidate.completion.execution.planning.partition.transfers",
      policy.candidate.completion.execution.planning.partition.transfers)
  visit(context, "candidate.completion.execution.planning.partition.services",
      policy.candidate.completion.execution.planning.partition.services)
  visit(context, "candidate.completion.execution.planning.partition.checks",
      policy.candidate.completion.execution.planning.partition.checks)
  visit(context, "candidate.completion.execution.execution.entries",
      policy.candidate.completion.execution.execution.entries)
  visit(context, "candidate.completion.execution.execution.round.guests.services",
      policy.candidate.completion.execution.execution.round.guests.services)
  visit(context, "candidate.completion.execution.execution.round.guests.preimageBytes",
      policy.candidate.completion.execution.execution.round.guests.preimageBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.probes",
      policy.candidate.completion.execution.execution.round.guests.probes)
  visit(context, "candidate.completion.execution.execution.round.guests.initialization.envelope",
      policy.candidate.completion.execution.execution.round.guests.initialization.envelope)
  visit(context, "candidate.completion.execution.execution.round.guests.initialization.program",
      policy.candidate.completion.execution.execution.round.guests.initialization.program)
  visit(context, "candidate.completion.execution.execution.round.guests.initialization.jumps",
      policy.candidate.completion.execution.execution.round.guests.initialization.jumps)
  visit(context, "candidate.completion.execution.execution.round.guests.initialization.pages",
      policy.candidate.completion.execution.execution.round.guests.initialization.pages)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.validators",
      policy.candidate.completion.execution.execution.round.guests.contexts.validators)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.queues.cores",
      policy.candidate.completion.execution.execution.round.guests.contexts.queues.cores)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.queues.maxHashes",
      policy.candidate.completion.execution.execution.round.guests.contexts.queues.maxHashes)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.queues.maxBytes",
      policy.candidate.completion.execution.execution.round.guests.contexts.queues.maxBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.staging.cores",
      policy.candidate.completion.execution.execution.round.guests.contexts.staging.cores)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.staging.validators",
      policy.candidate.completion.execution.execution.round.guests.contexts.staging.validators)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.staging.maxBytes",
      policy.candidate.completion.execution.execution.round.guests.contexts.staging.maxBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.privileges.cores",
      policy.candidate.completion.execution.execution.round.guests.contexts.privileges.cores)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.privileges.maxAlways",
      policy.candidate.completion.execution.execution.round.guests.contexts.privileges.maxAlways)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.privileges.maxBytes",
      policy.candidate.completion.execution.execution.round.guests.contexts.privileges.maxBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.contexts.totalBytes",
      policy.candidate.completion.execution.execution.round.guests.contexts.totalBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.fetch.items",
      policy.candidate.completion.execution.execution.round.guests.fetch.items)
  visit(context, "candidate.completion.execution.execution.round.guests.fetch.bytes",
      policy.candidate.completion.execution.execution.round.guests.fetch.bytes)
  visit(context, "candidate.completion.execution.execution.round.guests.fetch.operand.outputBytes",
      policy.candidate.completion.execution.execution.round.guests.fetch.operand.outputBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.fetch.operand.authBytes",
      policy.candidate.completion.execution.execution.round.guests.fetch.operand.authBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.fetch.operand.totalBlobBytes",
      policy.candidate.completion.execution.execution.round.guests.fetch.operand.totalBlobBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.fetch.operand.maxBytes",
      policy.candidate.completion.execution.execution.round.guests.fetch.operand.maxBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.copyBytes",
      policy.candidate.completion.execution.execution.round.guests.copyBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.steps",
      policy.candidate.completion.execution.execution.round.guests.steps)
  visit(context, "candidate.completion.execution.execution.round.guests.calls",
      policy.candidate.completion.execution.execution.round.guests.calls)
  visit(context, "candidate.completion.execution.execution.round.guests.cycles",
      policy.candidate.completion.execution.execution.round.guests.cycles)
  visit(context, "candidate.completion.execution.execution.round.guests.provisions.items",
      policy.candidate.completion.execution.execution.round.guests.provisions.items)
  visit(context, "candidate.completion.execution.execution.round.guests.provisions.perBlob",
      policy.candidate.completion.execution.execution.round.guests.provisions.perBlob)
  visit(context, "candidate.completion.execution.execution.round.guests.provisions.totalBlobBytes",
      policy.candidate.completion.execution.execution.round.guests.provisions.totalBlobBytes)
  visit(context, "candidate.completion.execution.execution.round.guests.transfers",
      policy.candidate.completion.execution.execution.round.guests.transfers)
  visit(context, "candidate.completion.execution.execution.round.guests.accountWriteKeys",
      policy.candidate.completion.execution.execution.round.guests.accountWriteKeys)
  visit(context, "candidate.completion.execution.execution.round.guests.createdAccounts",
      policy.candidate.completion.execution.execution.round.guests.createdAccounts)
  visit(context, "candidate.completion.execution.execution.round.guests.deletedAccounts",
      policy.candidate.completion.execution.execution.round.guests.deletedAccounts)
  visit(context, "candidate.completion.execution.execution.round.guests.modifiedAccounts",
      policy.candidate.completion.execution.execution.round.guests.modifiedAccounts)
  visit(context, "candidate.completion.execution.execution.round.guests.accountWriteFacts",
      policy.candidate.completion.execution.execution.round.guests.accountWriteFacts)
  visit(context, "candidate.completion.execution.execution.round.guests.annulment.outcomes",
      policy.candidate.completion.execution.execution.round.guests.annulment.outcomes)
  visit(context, "candidate.completion.execution.execution.round.guests.annulment.modified",
      policy.candidate.completion.execution.execution.round.guests.annulment.modified)
  visit(context, "candidate.completion.execution.execution.round.guests.annulment.checks",
      policy.candidate.completion.execution.execution.round.guests.annulment.checks)
  visit(context, "candidate.completion.execution.execution.round.guests.coverage.services",
      policy.candidate.completion.execution.execution.round.guests.coverage.services)
  visit(context, "candidate.completion.execution.execution.round.guests.coverage.executed",
      policy.candidate.completion.execution.execution.round.guests.coverage.executed)
  visit(context, "candidate.completion.execution.execution.round.guests.coverage.skipped",
      policy.candidate.completion.execution.execution.round.guests.coverage.skipped)
  visit(context, "candidate.completion.execution.execution.round.guests.coverage.absent",
      policy.candidate.completion.execution.execution.round.guests.coverage.absent)
  visit(context, "candidate.completion.execution.execution.round.guests.coverage.checks",
      policy.candidate.completion.execution.execution.round.guests.coverage.checks)
  visit(context, "candidate.completion.execution.execution.round.guests.coverage.gas",
      policy.candidate.completion.execution.execution.round.guests.coverage.gas)
  visit(context, "candidate.completion.execution.execution.round.accounts.entries",
      policy.candidate.completion.execution.execution.round.accounts.entries)
  visit(context, "candidate.completion.execution.execution.round.accounts.providers",
      policy.candidate.completion.execution.execution.round.accounts.providers)
  visit(context, "candidate.completion.execution.execution.round.accounts.selection.accounts",
      policy.candidate.completion.execution.execution.round.accounts.selection.accounts)
  visit(context, "candidate.completion.execution.execution.round.accounts.selection.outcomes",
      policy.candidate.completion.execution.execution.round.accounts.selection.outcomes)
  visit(context, "candidate.completion.execution.execution.round.accounts.selection.checks",
      policy.candidate.completion.execution.execution.round.accounts.selection.checks)
  visit(context, "candidate.completion.execution.execution.round.accounts.selection.skipped",
      policy.candidate.completion.execution.execution.round.accounts.selection.skipped)
  visit(context, "candidate.completion.execution.execution.round.accounts.creation.outcomes",
      policy.candidate.completion.execution.execution.round.accounts.creation.outcomes)
  visit(context, "candidate.completion.execution.execution.round.accounts.creation.creations",
      policy.candidate.completion.execution.execution.round.accounts.creation.creations)
  visit(context, "candidate.completion.execution.execution.round.accounts.creation.accounts",
      policy.candidate.completion.execution.execution.round.accounts.creation.accounts)
  visit(context, "candidate.completion.execution.execution.round.accounts.creation.checks",
      policy.candidate.completion.execution.execution.round.accounts.creation.checks)
  visit(context, "candidate.completion.execution.execution.round.accounts.writes.accounts",
      policy.candidate.completion.execution.execution.round.accounts.writes.accounts)
  visit(context, "candidate.completion.execution.execution.round.accounts.writes.facts",
      policy.candidate.completion.execution.execution.round.accounts.writes.facts)
  visit(context, "candidate.completion.execution.execution.round.accounts.writes.writes",
      policy.candidate.completion.execution.execution.round.accounts.writes.writes)
  visit(context, "candidate.completion.execution.execution.round.accounts.writes.checks",
      policy.candidate.completion.execution.execution.round.accounts.writes.checks)
  visit(context, "candidate.completion.execution.execution.round.accounts.writes.valueBytes",
      policy.candidate.completion.execution.execution.round.accounts.writes.valueBytes)
  visit(context, "candidate.completion.execution.execution.round.provisions.contexts",
      policy.candidate.completion.execution.execution.round.provisions.contexts)
  visit(context, "candidate.completion.execution.execution.round.provisions.values.items",
      policy.candidate.completion.execution.execution.round.provisions.values.items)
  visit(context, "candidate.completion.execution.execution.round.provisions.values.perBlob",
      policy.candidate.completion.execution.execution.round.provisions.values.perBlob)
  visit(context, "candidate.completion.execution.execution.round.provisions.values.totalBlobBytes",
      policy.candidate.completion.execution.execution.round.provisions.values.totalBlobBytes)
  visit(context, "candidate.completion.execution.execution.round.provisions.encodedBytes",
      policy.candidate.completion.execution.execution.round.provisions.encodedBytes)
  visit(context, "candidate.completion.execution.execution.round.globals.roles.privileges.cores",
      policy.candidate.completion.execution.execution.round.globals.roles.privileges.cores)
  visit(context, "candidate.completion.execution.execution.round.globals.roles.privileges.maxAlways",
      policy.candidate.completion.execution.execution.round.globals.roles.privileges.maxAlways)
  visit(context, "candidate.completion.execution.execution.round.globals.roles.privileges.maxBytes",
      policy.candidate.completion.execution.execution.round.globals.roles.privileges.maxBytes)
  visit(context, "candidate.completion.execution.execution.round.globals.roles.outcomes",
      policy.candidate.completion.execution.execution.round.globals.roles.outcomes)
  visit(context, "candidate.completion.execution.execution.round.globals.roles.checks",
      policy.candidate.completion.execution.execution.round.globals.roles.checks)
  visit(context, "candidate.completion.execution.execution.round.globals.roles.totalBytes",
      policy.candidate.completion.execution.execution.round.globals.roles.totalBytes)
  visit(context, "candidate.completion.execution.execution.round.globals.queues.cores",
      policy.candidate.completion.execution.execution.round.globals.queues.cores)
  visit(context, "candidate.completion.execution.execution.round.globals.queues.maxHashes",
      policy.candidate.completion.execution.execution.round.globals.queues.maxHashes)
  visit(context, "candidate.completion.execution.execution.round.globals.queues.maxBytes",
      policy.candidate.completion.execution.execution.round.globals.queues.maxBytes)
  visit(context, "candidate.completion.execution.execution.round.globals.staging.cores",
      policy.candidate.completion.execution.execution.round.globals.staging.cores)
  visit(context, "candidate.completion.execution.execution.round.globals.staging.validators",
      policy.candidate.completion.execution.execution.round.globals.staging.validators)
  visit(context, "candidate.completion.execution.execution.round.globals.staging.maxBytes",
      policy.candidate.completion.execution.execution.round.globals.staging.maxBytes)
  visit(context, "candidate.completion.execution.execution.round.globals.totalBytes",
      policy.candidate.completion.execution.execution.round.globals.totalBytes)
  visit(context, "candidate.completion.execution.execution.round.outputs.outcomes",
      policy.candidate.completion.execution.execution.round.outputs.outcomes)
  visit(context, "candidate.completion.execution.execution.round.outputs.log.items",
      policy.candidate.completion.execution.execution.round.outputs.log.items)
  visit(context, "candidate.completion.execution.execution.round.outputs.log.maxBytes",
      policy.candidate.completion.execution.execution.round.outputs.log.maxBytes)
  visit(context, "candidate.completion.execution.execution.round.transfers.sources",
      policy.candidate.completion.execution.execution.round.transfers.sources)
  visit(context, "candidate.completion.execution.execution.round.transfers.transfers",
      policy.candidate.completion.execution.execution.round.transfers.transfers)
  visit(context, "candidate.completion.execution.execution.round.transfers.memoBytes",
      policy.candidate.completion.execution.execution.round.transfers.memoBytes)
  visit(context, "candidate.completion.execution.execution.round.pending.sources",
      policy.candidate.completion.execution.execution.round.pending.sources)
  visit(context, "candidate.completion.execution.execution.round.pending.transfers",
      policy.candidate.completion.execution.execution.round.pending.transfers)
  visit(context, "candidate.completion.execution.execution.round.pending.memoBytes",
      policy.candidate.completion.execution.execution.round.pending.memoBytes)
  visit(context, "candidate.completion.composition.statistics.entries",
      policy.candidate.completion.composition.statistics.entries)
  visit(context, "candidate.completion.composition.statistics.providers",
      policy.candidate.completion.composition.statistics.providers)
  visit(context, "candidate.completion.composition.statistics.operands",
      policy.candidate.completion.composition.statistics.operands)
  visit(context, "candidate.completion.composition.statistics.transfers",
      policy.candidate.completion.composition.statistics.transfers)
  visit(context, "candidate.completion.composition.statistics.services",
      policy.candidate.completion.composition.statistics.services)
  visit(context, "candidate.completion.composition.statistics.gas",
      policy.candidate.completion.composition.statistics.gas)
  visit(context, "candidate.completion.composition.accounts.services",
      policy.candidate.completion.composition.accounts.services)
  visit(context, "candidate.completion.composition.accounts.metadataBytes",
      policy.candidate.completion.composition.accounts.metadataBytes)
  visit(context, "candidate.completion.composition.finalization.outputs.entries",
      policy.candidate.completion.composition.finalization.outputs.entries)
  visit(context, "candidate.completion.composition.finalization.outputs.outcomes",
      policy.candidate.completion.composition.finalization.outputs.outcomes)
  visit(context, "candidate.completion.composition.finalization.outputs.log.items",
      policy.candidate.completion.composition.finalization.outputs.log.items)
  visit(context, "candidate.completion.composition.finalization.outputs.log.maxBytes",
      policy.candidate.completion.composition.finalization.outputs.log.maxBytes)
  visit(context, "candidate.completion.composition.finalization.history.reports",
      policy.candidate.completion.composition.finalization.history.reports)
  visit(context, "candidate.completion.composition.finalization.history.queues.epochSlots",
      policy.candidate.completion.composition.finalization.history.queues.epochSlots)
  visit(context, "candidate.completion.composition.finalization.history.queues.cores",
      policy.candidate.completion.composition.finalization.history.queues.cores)
  visit(context, "candidate.completion.composition.finalization.history.queues.perSlot",
      policy.candidate.completion.composition.finalization.history.queues.perSlot)
  visit(context, "candidate.completion.composition.finalization.history.queues.totalItems",
      policy.candidate.completion.composition.finalization.history.queues.totalItems)
  visit(context, "candidate.completion.composition.finalization.history.queues.perDependencies",
      policy.candidate.completion.composition.finalization.history.queues.perDependencies)
  visit(context, "candidate.completion.composition.finalization.history.queues.totalDependencies",
      policy.candidate.completion.composition.finalization.history.queues.totalDependencies)
  visit(context, "candidate.completion.composition.finalization.history.queues.reportBytes",
      policy.candidate.completion.composition.finalization.history.queues.reportBytes)
  visit(context, "candidate.completion.composition.finalization.history.queues.maxBytes",
      policy.candidate.completion.composition.finalization.history.queues.maxBytes)
  visit(context, "candidate.completion.composition.ready.items",
      policy.candidate.completion.composition.ready.items)
  visit(context, "candidate.completion.composition.ready.dependencies",
      policy.candidate.completion.composition.ready.dependencies)
  visit(context, "candidate.completion.composition.ready.queues.epochSlots",
      policy.candidate.completion.composition.ready.queues.epochSlots)
  visit(context, "candidate.completion.composition.ready.queues.cores",
      policy.candidate.completion.composition.ready.queues.cores)
  visit(context, "candidate.completion.composition.ready.queues.perSlot",
      policy.candidate.completion.composition.ready.queues.perSlot)
  visit(context, "candidate.completion.composition.ready.queues.totalItems",
      policy.candidate.completion.composition.ready.queues.totalItems)
  visit(context, "candidate.completion.composition.ready.queues.perDependencies",
      policy.candidate.completion.composition.ready.queues.perDependencies)
  visit(context, "candidate.completion.composition.ready.queues.totalDependencies",
      policy.candidate.completion.composition.ready.queues.totalDependencies)
  visit(context, "candidate.completion.composition.ready.queues.reportBytes",
      policy.candidate.completion.composition.ready.queues.reportBytes)
  visit(context, "candidate.completion.composition.ready.queues.maxBytes",
      policy.candidate.completion.composition.ready.queues.maxBytes)
  visit(context, "candidate.completion.composition.recent.headerBytes",
      policy.candidate.completion.composition.recent.headerBytes)
  visit(context, "candidate.completion.composition.recent.outputs.items",
      policy.candidate.completion.composition.recent.outputs.items)
  visit(context, "candidate.completion.composition.recent.outputs.maxBytes",
      policy.candidate.completion.composition.recent.outputs.maxBytes)
  visit(context, "candidate.completion.composition.recent.history.cores",
      policy.candidate.completion.composition.recent.history.cores)
  visit(context, "candidate.completion.composition.recent.history.blocks",
      policy.candidate.completion.composition.recent.history.blocks)
  visit(context, "candidate.completion.composition.recent.history.perBlock",
      policy.candidate.completion.composition.recent.history.perBlock)
  visit(context, "candidate.completion.composition.recent.history.totalPackages",
      policy.candidate.completion.composition.recent.history.totalPackages)
  visit(context, "candidate.completion.composition.recent.history.peaks",
      policy.candidate.completion.composition.recent.history.peaks)
  visit(context, "candidate.completion.composition.recent.history.maxBytes",
      policy.candidate.completion.composition.recent.history.maxBytes)
  visit(context, "candidate.completion.composition.validators.chapterBytes",
      policy.candidate.completion.composition.validators.chapterBytes)
  visit(context, "candidate.completion.composition.validators.validators",
      policy.candidate.completion.composition.validators.validators)
  visit(context, "candidate.completion.composition.validators.services",
      policy.candidate.completion.composition.validators.services)
  visit(context, "candidate.completion.composition.validators.componentBytes",
      policy.candidate.completion.composition.validators.componentBytes)
  visit(context, "candidate.completion.composition.validators.preimages",
      policy.candidate.completion.composition.validators.preimages)
  visit(context, "candidate.completion.composition.validators.preimageBytes",
      policy.candidate.completion.composition.validators.preimageBytes)
  visit(context, "candidate.completion.composition.validators.projection.rows",
      policy.candidate.completion.composition.validators.projection.rows)
  visit(context, "candidate.completion.composition.validators.projection.assurances",
      policy.candidate.completion.composition.validators.projection.assurances)
  visit(context, "candidate.completion.composition.validators.projection.reporters",
      policy.candidate.completion.composition.validators.projection.reporters)
  visit(context, "candidate.completion.composition.validators.projection.comparisons",
      policy.candidate.completion.composition.validators.projection.comparisons)
  visit(context, "candidate.completion.composition.activity.componentBytes",
      policy.candidate.completion.composition.activity.componentBytes)
  visit(context, "candidate.completion.composition.activity.preimages.items",
      policy.candidate.completion.composition.activity.preimages.items)
  visit(context, "candidate.completion.composition.activity.preimages.perBlob",
      policy.candidate.completion.composition.activity.preimages.perBlob)
  visit(context, "candidate.completion.composition.activity.preimages.totalBlobBytes",
      policy.candidate.completion.composition.activity.preimages.totalBlobBytes)
  visit(context, "candidate.completion.composition.activity.incoming",
      policy.candidate.completion.composition.activity.incoming)
  visit(context, "candidate.completion.composition.activity.available",
      policy.candidate.completion.composition.activity.available)
  visit(context, "candidate.completion.composition.activity.digests",
      policy.candidate.completion.composition.activity.digests)
  visit(context, "candidate.completion.composition.activity.assurances",
      policy.candidate.completion.composition.activity.assurances)
  visit(context, "candidate.completion.composition.activity.provisions",
      policy.candidate.completion.composition.activity.provisions)
  visit(context, "candidate.completion.composition.activity.accumulation",
      policy.candidate.completion.composition.activity.accumulation)
  visit(context, "candidate.completion.composition.activity.services",
      policy.candidate.completion.composition.activity.services)
  visit(context, "candidate.completion.composition.activity.activityBytes",
      policy.candidate.completion.composition.activity.activityBytes)
  visit(context, "candidate.completion.composition.preimages.items",
      policy.candidate.completion.composition.preimages.items)
  visit(context, "candidate.completion.composition.preimages.bytes",
      policy.candidate.completion.composition.preimages.bytes)
  visit(context, "candidate.completion.composition.authorization.guarantees",
      policy.candidate.completion.composition.authorization.guarantees)
  visit(context, "candidate.completion.composition.authorization.inputHashes",
      policy.candidate.completion.composition.authorization.inputHashes)
  visit(context, "candidate.completion.composition.authorization.inputBytes",
      policy.candidate.completion.composition.authorization.inputBytes)
  visit(context, "candidate.completion.composition.authorization.outputHashes",
      policy.candidate.completion.composition.authorization.outputHashes)
  visit(context, "candidate.completion.composition.authorization.outputBytes",
      policy.candidate.completion.composition.authorization.outputBytes)
  visit(context, "candidate.completion.composition.consensus.chapterBytes",
      policy.candidate.completion.composition.consensus.chapterBytes)
  visit(context, "candidate.completion.composition.consensus.totalBytes",
      policy.candidate.completion.composition.consensus.totalBytes)
  visit(context, "candidate.headerBytes",
      policy.candidate.headerBytes)
  visit(context, "stream.readBytes",
      policy.stream.readBytes)
  visit(context, "stream.writeBytes",
      policy.stream.writeBytes)
  visit(context, "stream.timeout",
      policy.stream.timeout)
  visit(context, "attemptTimeout",
      policy.attemptTimeout)
