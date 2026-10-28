# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture an existing generic proof query from exact complete logical producer provenance under independent selected-view retention admission.
import ./proof_query as app_proof_query
import ../state/current_logical as state_current_logical
import ../state/accumulation_current_update as state_accumulation_current_update
import ../state/proof_plan as state_proof_plan
import ../chain/provider as chain_provider
import ../chain/genesis as chain_genesis
import ../codec/bounded as codec_bounded
type
  LogicalProofLimits* = object ## Whole selected-view copying and existing full-map/path/wire/hash query work retain separate ceilings.
    blocks*: ElementLimit
    viewBytes*: ByteLimit
    query*: ProofQueryLimits
  LogicalProofError* {.pure.} = enum ## Missing logical source, selected-view resource refusal and actual generic capture causes stay distinct.
    Uninitialized, None, InvalidLogical, LimitExceeded, QueryFailure
  LogicalProofResult* = object ## No failed admission exposes a query or selected snapshot prefix.
    case status: LogicalProofError
    of None: completed: ProofQuery
    of QueryFailure: queryReason: ProofQueryResult[ProofQuery]
    else: discard              # Defaults, missing source and retention refusals have no executable payload.
func error*(outcome: LogicalProofResult): LogicalProofError =
  ## Observe the selected immutable stage without granting its payload.
  outcome.status
func value*(outcome: LogicalProofResult): ProofQuery {.inline, requires: outcome.status ==
    LogicalProofError.None.} =
  ## Retain only the existing bounded generic query; caller independently chooses root trust and worker scheduling.
  outcome.completed
func queryFailure*(outcome: LogicalProofResult): ProofQueryResult[ProofQuery] {.inline,
    requires: outcome.status == LogicalProofError.QueryFailure.} =
  ## Preserve original generic map, plan, wire and hash-work admission failures.
  outcome.queryReason
proc captureLogicalProofQuery*(source: CurrentLogicalState, plan: StateProofPlan,
    limits: LogicalProofLimits): LogicalProofResult =
  ## Cached original view extents precede all heavy view/index copying; every canonical alias must be host-available during capture.
  let retention = source.currentLogicalViewInfo
  if retention.error != CurrentLogicalError.None:
    return LogicalProofResult(status: LogicalProofError.InvalidLogical)
  if uint64(retention.value.owners) > uint64(limits.blocks) or retention.value.bytes > min(uint64(
      limits.viewBytes), uint64(high(int))):
    return LogicalProofResult(status: LogicalProofError.LimitExceeded)
  let selected = source.currentLogicalUpdate.value.currentUpdateView.bestBlock
  let query = captureProofQuery(selected, plan, limits.query)
  if query.error != ProofQueryError.None:
    return LogicalProofResult(status: LogicalProofError.QueryFailure, queryReason: query)
  LogicalProofResult(status: LogicalProofError.None, completed: query.value)
