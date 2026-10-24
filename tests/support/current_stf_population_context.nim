# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit three-core policies separate bounded decoding capacity from actual six/nine-validator chapter populations.
import ../../src/app/candidate
import ../../src/chain/parameters
import ../../src/codec/[bounded, state_safrole, composite, assurances]
import ./[current_consecutive_context, accumulation_current_chain_context]

proc populationParameters*(): Parameters =
  ## Preserve the frozen execution tuple except the full E2 core-count field at offset24.
  var wire = encodeParameters(currentChainSettings())
  wire[24] = 3
  wire[25] = 0
  decodeParameters(wire).value

proc populationLimits*(): CurrentCandidateLimits =
  ## One coherent ceiling-nine profile accepts independently shaped active, previous, pending and staging rosters.
  result = currentConsecutiveLimits()
  let roster = ValidatorStateConfig(cores: CoreCount(3), validators: ElementLimit(9),
      maxBytes: ByteLimit(4096))
  result.reporting.admission.frame.cores = CoreCount(3)
  result.reporting.admission.frame.validators = ValidatorCount(9)
  result.reporting.safrole.state.validators = roster
  result.reporting.disputes.rosters = roster
  result.reporting.disputes.availability.guarantee.cores = CoreCount(3)
  result.reporting.disputes.availability.guarantee.validators = ValidatorCount(9)
  result.reporting.disputes.availability.maxPresent = ElementLimit(3)
  result.reporting.availability.rosters = roster
  result.reporting.availability.assignments = result.reporting.disputes.availability
  result.reporting.reports.credentials.assignments.roster = roster
  result.reporting.reports.policy.pools.cores = CoreCount(3)
  result.reporting.reports.policy.pools.maxHashes = ElementLimit(240)
  result.reporting.reports.policy.pools.maxBytes = ByteLimit(7680)
  result.reporting.reports.anchors.history.cores = CoreCount(3)
  result.reporting.reports.ancestors.header.cores = CoreCount(3)
  result.reporting.reports.ancestors.header.authorValidators = ValidatorCount(9)
  result.reporting.reports.packages.availability = result.reporting.disputes.availability
  result.reporting.reports.packages.queues.cores = CoreCount(3)
  result.queue.queues.cores = CoreCount(3)
  result.round.privileges.cores = CoreCount(3)
  result.completion.execution.initial.guests.contexts.validators = ValidatorCount(9)
  result.completion.execution.initial.guests.contexts.queues.cores = CoreCount(3)
  result.completion.execution.initial.guests.contexts.queues.maxHashes = ElementLimit(240)
  result.completion.execution.initial.guests.contexts.queues.maxBytes = ByteLimit(7680)
  result.completion.execution.initial.guests.contexts.staging = roster
  result.completion.execution.initial.guests.contexts.privileges.cores = CoreCount(3)
  result.completion.execution.initial.globals.roles.privileges.cores = CoreCount(3)
  result.completion.execution.initial.globals.queues = result.completion.execution.initial.guests.contexts.queues
  result.completion.execution.initial.globals.staging = roster
  result.completion.execution.execution.round = result.completion.execution.initial
  result.completion.composition.finalization.history.queues.cores = CoreCount(3)
  result.completion.composition.ready.queues.cores = CoreCount(3)
  result.completion.composition.recent.history.cores = CoreCount(3)
  result.completion.composition.validators.validators = ElementLimit(9)
  result.completion.composition.validators.chapterBytes = ByteLimit(8192)
  result.completion.composition.validators.projection.rows = ElementLimit(18)
  result.completion.composition.authorization.inputHashes = ElementLimit(240)
  result.completion.composition.authorization.inputBytes = ByteLimit(7680)
  result.completion.composition.authorization.outputHashes = ElementLimit(24)
  result.completion.composition.authorization.outputBytes = ByteLimit(771)
