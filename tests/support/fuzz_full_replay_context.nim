# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit finite full-profile test policy uses341 cores,1023 validators and600 slots without replacing source-derived GP facts.
import ./fuzz_guest_replay_context
import ../../src/app/fuzz_backend
import ../../src/chain/genesis
import ../../src/codec/[bounded, assurances, header, tickets, work_digest, state_authorization, state_privileges]
import ../../src/state/[guarantors, report_policy]

proc fuzzFullReplayConfig*(): FuzzBackendConfig =
  ## Return an independently owned full-geometry policy; trusted Parameters and all expected maps are supplied separately.
  result = fuzzGuestReplayConfig()
  result.forkStates = ElementLimit(8) # Match the actual target sibling window; Tiny references retain their own two-state policy.
  var frame = result.candidate.reporting.admission.frame
  frame.cores = CoreCount(341)
  frame.validators = ValidatorCount(1023)
  frame.epochSlots = EpochSlots(600)
  frame.ticketLimit = TicketLimit(16)
  result.candidate.reporting.admission.frame = frame
  result.wire.frame = frame
  result.wire.bytes = ByteLimit(16777216)
  result.wire.state = genesisStoreLimits()
  result.wire.state.writes = ElementLimit(1000)
  result.wire.state.writeValueBytes = ByteLimit(4194304)
  var roster = result.candidate.reporting.reports.credentials.assignments.roster
  roster.cores = frame.cores
  roster.validators = ElementLimit(1023)
  roster.maxBytes = ByteLimit(400000)
  result.candidate.reporting.reports.credentials.assignments.roster = roster
  result.candidate.reporting.reports.credentials.assignments.epochSlots = frame.epochSlots
  result.candidate.reporting.reports.credentials.assignments.rotationSlots = GuarantorRotationSlots(10)
  let authorization = AuthorizationConfig(cores: frame.cores,
    maxHashes: ElementLimit(27280), maxBytes: ByteLimit(1000000))
  result.candidate.reporting.reports.policy.pools = authorization
  result.candidate.reporting.reports.policy.reportGas = ReportGasLimit(10000000)
  var historyLimits = result.candidate.completion.composition.recent.history
  historyLimits.cores = frame.cores
  historyLimits.perBlock = ElementLimit(341) # One reported package per full-profile core can enter a block.
  historyLimits.totalPackages = ElementLimit(2728) # Eight retained blocks can each carry all341 package/root pairs.
  historyLimits.maxBytes = ByteLimit(262144) # The complete eight-block dictionary and bounded MMR belt fit below256KiB.
  result.candidate.reporting.reports.anchors.history = historyLimits
  result.candidate.reporting.reports.ancestors.header.cores = frame.cores
  result.candidate.reporting.reports.ancestors.header.authorValidators = frame.validators
  result.candidate.reporting.reports.ancestors.header.epochSlots = frame.epochSlots
  var availability = result.candidate.reporting.reports.packages.availability
  availability.guarantee.cores = frame.cores
  availability.guarantee.validators = frame.validators
  availability.maxPresent = ElementLimit(341)
  result.candidate.reporting.reports.packages.availability = availability
  var queues = result.candidate.reporting.reports.packages.queues
  queues.cores = frame.cores
  queues.epochSlots = frame.epochSlots
  result.candidate.reporting.reports.packages.queues = queues
  result.candidate.reporting.safrole.state.validators = roster
  result.candidate.reporting.safrole.state.epochSlots = frame.epochSlots
  result.candidate.reporting.safrole.state.maxAccumulator = ElementLimit(600)
  result.candidate.reporting.safrole.tailStart = EpochSlots(500)
  result.candidate.reporting.safrole.blockTickets = frame.ticketLimit
  result.candidate.reporting.disputes.rosters = roster
  result.candidate.reporting.disputes.epochSlots = frame.epochSlots
  result.candidate.reporting.disputes.availability = availability
  result.candidate.reporting.availability.rosters = roster
  result.candidate.reporting.availability.assignments = availability
  result.candidate.reporting.availability.availableReports = ElementLimit(341)
  result.candidate.queue.queues = queues
  let privileges = PrivilegeConfig(cores: frame.cores, maxAlways: ElementLimit(2),
      maxBytes: ByteLimit(4096))
  result.candidate.round.privileges = privileges
  result.candidate.round.reportGas = Gas(10000000)
  result.candidate.round.blockGas = Gas(3500000000)
  var contexts = result.candidate.completion.execution.initial.guests.contexts
  contexts.validators = frame.validators
  contexts.queues = authorization
  contexts.staging = roster
  contexts.privileges = privileges
  contexts.totalBytes = ByteLimit(2000000)
  result.candidate.completion.execution.initial.guests.contexts = contexts
  result.candidate.completion.execution.execution.round.guests.contexts = contexts
  var globals = result.candidate.completion.execution.initial.globals
  globals.roles.privileges = privileges
  globals.roles.totalBytes = ByteLimit(8192)
  globals.roles.checks = ElementLimit(4096) # Every full core position consumes an original-owner role predicate.
  globals.queues = authorization
  globals.staging = roster
  globals.totalBytes = ByteLimit(4194304)
  result.candidate.completion.execution.initial.globals = globals
  result.candidate.completion.execution.execution.round.globals = globals
  result.candidate.completion.composition.ready.queues = queues
  result.candidate.completion.composition.recent.history = historyLimits
  result.candidate.completion.composition.finalization.history.queues = queues
  result.candidate.completion.composition.validators.chapterBytes = ByteLimit(400000)
  result.candidate.completion.composition.validators.validators = ElementLimit(1023)
  result.candidate.completion.composition.validators.componentBytes = ByteLimit(200000)
  result.candidate.completion.composition.validators.projection.rows = ElementLimit(2046)
  result.candidate.completion.composition.validators.projection.assurances = ElementLimit(1023)
  result.candidate.completion.composition.validators.projection.reporters = ElementLimit(1023)
  result.candidate.completion.composition.validators.projection.comparisons = ElementLimit(1046529)
  result.candidate.completion.composition.activity.componentBytes = ByteLimit(200000)
  result.candidate.completion.composition.activity.activityBytes = ByteLimit(100000)
  result.candidate.completion.composition.activity.incoming = ElementLimit(
      341) # All full-core guarantees can contribute refinement activity.
  result.candidate.completion.composition.activity.digests = ElementLimit(
      5456) # GP allows at most16 work items in each of341 reports.
  result.candidate.completion.composition.activity.available = ElementLimit(341)
  result.candidate.completion.composition.activity.assurances = ElementLimit(1023)
  result.candidate.completion.composition.authorization.guarantees = ElementLimit(
      341) # Every full-core guarantee can consume its authorizer.
  result.candidate.completion.composition.authorization.inputHashes = authorization.maxHashes
  result.candidate.completion.composition.authorization.inputBytes = authorization.maxBytes
  result.candidate.completion.composition.authorization.outputHashes = ElementLimit(2728)
  result.candidate.completion.composition.authorization.outputBytes = ByteLimit(100000)
  result.candidate.completion.composition.consensus.chapterBytes = ByteLimit(400000)
  result.candidate.completion.composition.consensus.totalBytes = ByteLimit(2000000)
