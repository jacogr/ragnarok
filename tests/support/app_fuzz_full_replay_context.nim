# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit finite full-profile test policy uses341 cores,1023 validators and600 slots without replacing source-derived GP facts.
import ./app_fuzz_guest_replay_context
import ../../src/app/fuzz_backend as app_fuzz_backend
import ../../src/chain/genesis as chain_genesis
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/header as codec_header
import ../../src/codec/tickets as codec_tickets
import ../../src/codec/work_digest as codec_work_digest
import ../../src/codec/state_authorization as codec_state_authorization
import ../../src/codec/state_privileges as codec_state_privileges
import ../../src/state/guarantors as state_guarantors
import ../../src/state/report_policy as state_report_policy
import ../../src/state/report_anchors as state_report_anchors

proc profileReplayConfig(cores, validators, slots, tickets, rotation, tail,
    blockGas: uint64): FuzzBackendConfig =
  ## Return an independently owned full-geometry policy; trusted Parameters and all expected maps are supplied separately.
  result = fuzzGuestReplayConfig()
  result.forkStates = ElementLimit(8) # Match the actual target sibling window; Tiny references retain their own two-state policy.
  var frame = result.candidate.reporting.admission.frame
  frame.cores = CoreCount(cores)
  frame.validators = ValidatorCount(validators)
  frame.epochSlots = EpochSlots(slots)
  frame.ticketLimit = TicketLimit(tickets)
  result.candidate.reporting.admission.frame = frame
  result.wire.frame = frame
  result.wire.bytes = ByteLimit(16777216)
  result.wire.state = genesisStoreLimits()
  result.wire.state.writes = ElementLimit(1000)
  result.wire.state.writeValueBytes = ByteLimit(4194304)
  var roster = result.candidate.reporting.reports.credentials.assignments.roster
  roster.cores = frame.cores
  roster.validators = ElementLimit(validators)
  roster.maxBytes = ByteLimit(400000)
  result.candidate.reporting.reports.credentials.assignments.roster = roster
  result.candidate.reporting.reports.credentials.assignments.epochSlots = frame.epochSlots
  result.candidate.reporting.reports.credentials.assignments.rotationSlots = GuarantorRotationSlots(rotation)
  let authorization = AuthorizationConfig(cores: frame.cores,
    maxHashes: ElementLimit(cores * 80), maxBytes: ByteLimit(1000000))
  result.candidate.reporting.reports.policy.pools = authorization
  result.candidate.reporting.reports.policy.reportGas = ReportGasLimit(10000000)
  var historyLimits = result.candidate.completion.composition.recent.history
  historyLimits.cores = frame.cores
  historyLimits.perBlock = ElementLimit(cores) # One reported package per full-profile core can enter a block.
  historyLimits.totalPackages = ElementLimit(cores *
      8) # Eight retained blocks can each carry all341 package/root pairs.
  historyLimits.maxBytes = ByteLimit(262144) # The complete eight-block dictionary and bounded MMR belt fit below256KiB.
  result.candidate.reporting.reports.anchors.history = historyLimits
  result.candidate.reporting.reports.ancestors.header.cores = frame.cores
  result.candidate.reporting.reports.ancestors.header.authorValidators = frame.validators
  result.candidate.reporting.reports.ancestors.header.epochSlots = frame.epochSlots
  var availability = result.candidate.reporting.reports.packages.availability
  availability.guarantee.cores = frame.cores
  availability.guarantee.validators = frame.validators
  availability.maxPresent = ElementLimit(cores)
  result.candidate.reporting.reports.packages.availability = availability
  var queues = result.candidate.reporting.reports.packages.queues
  queues.cores = frame.cores
  queues.epochSlots = frame.epochSlots
  result.candidate.reporting.reports.packages.queues = queues
  result.candidate.reporting.safrole.state.validators = roster
  result.candidate.reporting.safrole.state.epochSlots = frame.epochSlots
  result.candidate.reporting.safrole.state.maxAccumulator = ElementLimit(slots)
  result.candidate.reporting.safrole.tailStart = EpochSlots(tail)
  result.candidate.reporting.safrole.blockTickets = frame.ticketLimit
  result.candidate.reporting.disputes.rosters = roster
  result.candidate.reporting.disputes.epochSlots = frame.epochSlots
  result.candidate.reporting.disputes.availability = availability
  result.candidate.reporting.availability.rosters = roster
  result.candidate.reporting.availability.assignments = availability
  result.candidate.reporting.availability.availableReports = ElementLimit(cores)
  result.candidate.queue.queues = queues
  let privileges = PrivilegeConfig(cores: frame.cores, maxAlways: ElementLimit(2),
      maxBytes: ByteLimit(4096))
  result.candidate.round.privileges = privileges
  result.candidate.round.reportGas = Gas(10000000)
  result.candidate.round.blockGas = Gas(blockGas)
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
  result.candidate.completion.composition.validators.validators = ElementLimit(validators)
  result.candidate.completion.composition.validators.componentBytes = ByteLimit(200000)
  result.candidate.completion.composition.validators.projection.rows = ElementLimit(validators * 2)
  result.candidate.completion.composition.validators.projection.assurances = ElementLimit(validators)
  result.candidate.completion.composition.validators.projection.reporters = ElementLimit(validators)
  result.candidate.completion.composition.validators.projection.comparisons = ElementLimit(
      validators * validators)
  result.candidate.completion.composition.activity.componentBytes = ByteLimit(200000)
  result.candidate.completion.composition.activity.activityBytes = ByteLimit(100000)
  result.candidate.completion.composition.activity.incoming = ElementLimit(
      341) # All full-core guarantees can contribute refinement activity.
  result.candidate.completion.composition.activity.digests = ElementLimit(
      5456) # GP allows at most16 work items in each of341 reports.
  result.candidate.completion.composition.activity.available = ElementLimit(cores)
  result.candidate.completion.composition.activity.assurances = ElementLimit(validators)
  result.candidate.completion.composition.authorization.guarantees = ElementLimit(
      341) # Every full-core guarantee can consume its authorizer.
  result.candidate.completion.composition.authorization.inputHashes = authorization.maxHashes
  result.candidate.completion.composition.authorization.inputBytes = authorization.maxBytes
  result.candidate.completion.composition.authorization.outputHashes = ElementLimit(cores * 8)
  result.candidate.completion.composition.authorization.outputBytes = ByteLimit(100000)
  result.candidate.completion.composition.consensus.chapterBytes = ByteLimit(400000)
  result.candidate.completion.composition.consensus.totalBytes = ByteLimit(2000000)

proc fuzzFullReplayConfig*(): FuzzBackendConfig =
  ## Preserve the existing Full profile and every historical resource ceiling.
  profileReplayConfig(341, 1023, 600, 16, 10, 500, 3500000000'u64)

proc fuzzNetworkReplayConfig*(): FuzzBackendConfig =
  ## Issue215 geometry retains explicit finite host bounds; expected Parameters remain independently supplied.
  result = profileReplayConfig(85, 255, 60, 4, 5, 50, 875000000)
  result.candidate.reporting.reports.anchors.lookupAge = LookupAge(600)
  result.candidate.reporting.reports.ancestors.headers = ElementLimit(601)
  result.candidate.reporting.reports.ancestors.maxBytes = ByteLimit(16777216)
