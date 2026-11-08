# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optional assurance startup profiles require explicit complete resource/chain geometry, storage mode and network policies; omitted files activate nothing and contain no private seed.

import std/[strutils, syncio]
import ./[assurance_broadcast, assurance_acquirer, assurance_distribution]
import ./proof/[assurance_storage, assurance_acquisition, network_read]
import ./work_policy/types
import ../jamnp-s/[assurance_duty, assurance_record, assurance_store, assurance_schedule,
  assurance_possession, assurance_fetch, assurance_distribution as distribution_rules,
  availability_proof, availability_read]
import ../codec/[bounded, assurances]
import ../codec/state/[safrole, consensus]

type
  NodeAssuranceSettings* = object ## Plain serialization inputs grant no activation capability; duty/proof are shared canonical controls and child acquisition/signing duty fields are replaced by them.
    mode*, startupMs*, period*: uint64
    topology*: SafroleStateConfig
    duty*: AssuranceDutyLimits
    proof*: AvailabilityMerkleLimits
    storeEntries*, storeScanEntries*, storeBytes*, recordBytes*: uint64
    acquisition*: AssuranceAcquisitionLimits
    acquisitionRequests*, acquisitionDials*, acquisitionBytes*: uint64
    acquisitionPeerMs*, acquisitionJobMs*, acquisitionRoundMs*, acquisitionRetryMs*,
      acquisitionAttempts*: uint64
    signing*: AssurancePossessionLimits
    plannedBytes*, restoreIoBytes*, restoreWorkspaceBytes*: ByteLimit
    reply*: AvailabilityReadLimits
    batchSources*: ElementLimit
    receiptEntries*, receiptMs*: uint64
    broadcastRequests*, broadcastDials*, broadcastBytes*, broadcastParallel*, broadcastPeerMs*,
      broadcastJobMs*: uint64
  NodeAssurancePolicy* = object ## Only a completely parsed profile exposes ready immutable controller and namespace settings.
    ready: bool
    settings: NodeAssuranceSettings
    storage: AssuranceStoreLimits
    reads: AssuranceReadLimits
    acquisition: AssuranceAcquisitionPolicy
    receipt: AssuranceReceiptPolicy
    broadcast: AssuranceBroadcastPolicy
  NodeAssurancePolicyResult* = object ## Failure contains only a bounded diagnostic and cannot enable a prefix of the validator lifecycle.
    case status: WorkPolicyError
    of None: completed: NodeAssurancePolicy
    else: field: string
include ./work_policy/parser
const AssurancePolicyHeader = "ragnarok-assurance-policy-v1"
const AssurancePolicyBytes = 32768

template assurancePolicyFields(values, context, visit: untyped) {.untyped.} =
  ## One declaration retains exact scalar names for complete parsing and independent operator-file emission.
  visit(context, "mode", values.mode)
  visit(context, "startupMs", values.startupMs)
  visit(context, "period", values.period)
  visit(context, "topology.validators.cores", values.topology.validators.cores)
  visit(context, "topology.validators.validators", values.topology.validators.validators)
  visit(context, "topology.validators.maxBytes", values.topology.validators.maxBytes)
  visit(context, "topology.epochSlots", values.topology.epochSlots)
  visit(context, "topology.maxAccumulator", values.topology.maxAccumulator)
  visit(context, "topology.maxBytes", values.topology.maxBytes)
  visit(context, "duty.chapterBytes", values.duty.chapterBytes)
  visit(context, "duty.readBytes", values.duty.readBytes)
  visit(context, "duty.reports", values.duty.reports)
  visit(context, "duty.requests", values.duty.requests)
  visit(context, "proof.bytes", values.proof.bytes)
  visit(context, "proof.hashes", values.proof.hashes)
  visit(context, "proof.hashBytes", values.proof.hashBytes)
  visit(context, "storeEntries", values.storeEntries)
  visit(context, "storeScanEntries", values.storeScanEntries)
  visit(context, "storeBytes", values.storeBytes)
  visit(context, "recordBytes", values.recordBytes)
  visit(context, "acquisition.wireBytes", values.acquisition.wireBytes)
  visit(context, "acquisition.workspaceBytes", values.acquisition.workspaceBytes)
  visit(context, "acquisitionRequests", values.acquisitionRequests)
  visit(context, "acquisitionDials", values.acquisitionDials)
  visit(context, "acquisitionBytes", values.acquisitionBytes)
  visit(context, "acquisitionPeerMs", values.acquisitionPeerMs)
  visit(context, "acquisitionJobMs", values.acquisitionJobMs)
  visit(context, "acquisitionRoundMs", values.acquisitionRoundMs)
  visit(context, "acquisitionRetryMs", values.acquisitionRetryMs)
  visit(context, "acquisitionAttempts", values.acquisitionAttempts)
  visit(context, "signing.shards", values.signing.shards)
  visit(context, "signing.hashes", values.signing.hashes)
  visit(context, "signing.ioBytes", values.signing.ioBytes)
  visit(context, "signing.hashBytes", values.signing.hashBytes)
  visit(context, "signing.workspaceBytes", values.signing.workspaceBytes)
  visit(context, "plannedBytes", values.plannedBytes)
  visit(context, "restoreIoBytes", values.restoreIoBytes)
  visit(context, "restoreWorkspaceBytes", values.restoreWorkspaceBytes)
  visit(context, "reply.computation.bytes", values.reply.computation.bytes)
  visit(context, "reply.computation.hashes", values.reply.computation.hashes)
  visit(context, "reply.computation.hashBytes", values.reply.computation.hashBytes)
  visit(context, "reply.wireBytes", values.reply.wireBytes)
  visit(context, "batchSources", values.batchSources)
  visit(context, "receiptEntries", values.receiptEntries)
  visit(context, "receiptMs", values.receiptMs)
  visit(context, "broadcastRequests", values.broadcastRequests)
  visit(context, "broadcastDials", values.broadcastDials)
  visit(context, "broadcastBytes", values.broadcastBytes)
  visit(context, "broadcastParallel", values.broadcastParallel)
  visit(context, "broadcastPeerMs", values.broadcastPeerMs)
  visit(context, "broadcastJobMs", values.broadcastJobMs)

func error*(outcome: NodeAssurancePolicyResult): WorkPolicyError =
  ## Inspect the selected failure before accessing a completed activation policy.
  outcome.status

func value*(outcome: NodeAssurancePolicyResult): NodeAssurancePolicy {.requires: outcome.status ==
    WorkPolicyError.None.} =
  ## Only whole schema and child validation grants ready startup configuration.
  outcome.completed

func fieldName*(outcome: NodeAssurancePolicyResult): string {.requires: outcome.status !=
    WorkPolicyError.None.} =
  ## Diagnostics never contain policy file contents or private credentials.
  outcome.field

func valid*(policy: NodeAssurancePolicy): bool =
  ## Defaults enable neither disk I/O nor network/private-key operations.
  policy.ready

func refused(reason: WorkPolicyError, field = ""): NodeAssurancePolicyResult =
  ## No refusal carries a partially constructed activation policy.
  NodeAssurancePolicyResult(status: reason, field: field)

proc encodeNodeAssurancePolicy*(values: NodeAssuranceSettings): string =
  ## Emit explicit supplied scalars; no private key, inferred defaults or source root is serialized.
  result = AssurancePolicyHeader & "\n"
  assurancePolicyFields(values, result, writeField)

func storageLimits*(policy: NodeAssurancePolicy): AssuranceStoreLimits {.requires: policy.ready.} =
  ## Independent namespace limits do not permit any opening by themselves.
  policy.storage

func storageMode*(policy: NodeAssurancePolicy): AssuranceStorageMode {.requires: policy.ready.} =
  ## Only explicit zero/open or one/create survives parsing; no automatic existence fallback is used.
  if policy.settings.mode == 1: AssuranceStorageMode.Create else: AssuranceStorageMode.Open

func startupTimeoutMs*(policy: NodeAssurancePolicy): uint64 {.requires: policy.ready.} =
  ## One finite namespace-startup deadline covers the bounded complete scan.
  policy.settings.startupMs

func readLimits*(policy: NodeAssurancePolicy): AssuranceReadLimits {.requires: policy.ready.} =
  ## Durable serving has independently explicit whole-request restore and reply limits.
  policy.reads

func acquisitionPolicy*(policy: NodeAssurancePolicy): AssuranceAcquisitionPolicy {.requires: policy.ready.} =
  ## CE137 acquisition uses the parsed whole-round reservations.
  policy.acquisition

func receiptPolicy*(policy: NodeAssurancePolicy): AssuranceReceiptPolicy {.requires: policy.ready.} =
  ## Incoming candidates remain unadmitted, independently bounded objects.
  policy.receipt

func broadcastPolicy*(policy: NodeAssurancePolicy): AssuranceBroadcastPolicy {.requires: policy.ready.} =
  ## Timed delivery cannot substitute a default signing or routing policy.
  policy.broadcast

func matches*(policy: NodeAssurancePolicy, geometry: SafroleStateConfig, period: uint64): bool =
  ## An operator file cannot silently select a different chain profile than the actual complete Services source.
  policy.ready and policy.settings.period == period and
    uint64(policy.settings.topology.validators.cores) == uint64(geometry.validators.cores) and
    uint64(policy.settings.topology.validators.validators) == uint64(
        geometry.validators.validators) and
    uint64(policy.settings.topology.epochSlots) == uint64(geometry.epochSlots)

proc decodeNodeAssurancePolicy*(text: string): NodeAssurancePolicyResult =
  ## Parse every scalar and reject duplicate/missing/unknown fields before constructing any ready child.
  var input = parsePolicyInput(text, AssurancePolicyHeader, AssurancePolicyBytes, 52)
  if input.error != WorkPolicyError.None: return refused(input.error, input.field)
  var values = default(NodeAssuranceSettings)
  assurancePolicyFields(values, input, readField)
  if input.error notin [WorkPolicyError.None, WorkPolicyError.MissingField]: return refused(
      input.error, input.field)
  for entry in input.values:
    if not entry.used: return refused(WorkPolicyError.UnknownField, entry.name)
  if input.error != WorkPolicyError.None: return refused(input.error, input.field)
  if values.mode > 1: return refused(WorkPolicyError.InvalidPolicy, "mode")
  if values.startupMs < 1 or values.startupMs > 600000: return refused(
      WorkPolicyError.InvalidPolicy, "startupMs")
  # Check each original field so its range proof survives conversion below.
  if values.acquisitionPeerMs < 1 or values.acquisitionPeerMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "acquisitionPeerMs")
  if values.acquisitionJobMs < 1 or values.acquisitionJobMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "acquisitionJobMs")
  if values.receiptMs < 1 or values.receiptMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "receiptMs")
  if values.broadcastPeerMs < 1 or values.broadcastPeerMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "broadcastPeerMs")
  if values.broadcastJobMs < 1 or values.broadcastJobMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "broadcastJobMs")
  if values.acquisitionRoundMs < 1 or values.acquisitionRoundMs > 600000:
    return refused(WorkPolicyError.InvalidPolicy, "acquisitionRoundMs")
  if values.acquisitionRetryMs < 1 or values.acquisitionRetryMs > 600000:
    return refused(WorkPolicyError.InvalidPolicy, "acquisitionRetryMs")
  if values.acquisitionAttempts < 1 or values.acquisitionAttempts > 3: return refused(
      WorkPolicyError.InvalidPolicy, "acquisitionAttempts")
  if values.broadcastParallel < 1 or values.broadcastParallel > 64: return refused(
      WorkPolicyError.InvalidPolicy, "broadcastParallel")
  if values.receiptEntries < 1 or values.receiptEntries > 1023: return refused(
      WorkPolicyError.InvalidPolicy, "receiptEntries")
  let count = uint64(values.topology.validators.validators)
  if count < 6 or count > 1023: return refused(WorkPolicyError.InvalidPolicy, "topology.validators.validators")
  values.acquisition.duty = values.duty
  values.acquisition.verification = values.proof
  values.signing.duty = values.duty
  let storage = AssuranceStoreLimits(entries: ElementLimit(values.storeEntries),
      scanEntries: ElementLimit(values.storeScanEntries),
    bytes: ByteLimit(values.storeBytes), record: AssuranceRecordLimits(bytes: ByteLimit(
        values.recordBytes), verification: values.proof))
  let reads = AssuranceReadLimits(restore: AssuranceRestoreLimits(verification: values.proof,
    ioBytes: values.restoreIoBytes, workspaceBytes: values.restoreWorkspaceBytes),
    reply: values.reply, batchSources: values.batchSources)
  let planning = AssuranceScheduleLimits(duty: values.duty, topology: values.topology,
      plannedBytes: values.plannedBytes)
  let acquisition = assuranceAcquisitionPolicy(AssuranceFetchLimits(duty: values.duty,
      plannedBytes: values.plannedBytes),
    values.acquisition, ElementLimit(values.acquisitionRequests), ElementLimit(
        values.acquisitionDials), ByteLimit(values.acquisitionBytes),
    peerTimeoutMs = range[1..120000](int(values.acquisitionPeerMs)), jobTimeoutMs = range[
        1..120000](int(values.acquisitionJobMs)),
    roundTimeoutMs = range[1..600000](int(values.acquisitionRoundMs)), retryMs = range[1..600000](
        int(values.acquisitionRetryMs)),
    attempts = range[1..3](int(values.acquisitionAttempts)))
  let receipt = assuranceReceiptPolicy(AssuranceDistributionLimits(duty: values.duty,
      wireBytes: ByteLimit(139)),
    range[1..1023](int(values.receiptEntries)), range[1..1023](int(count)), range[1..120000](int(
        values.receiptMs)))
  let broadcast = assuranceBroadcastPolicy(planning, values.signing, values.period,
    ElementLimit(values.broadcastRequests), ElementLimit(values.broadcastDials), ByteLimit(
        values.broadcastBytes),
    parallel = range[1..64](int(values.broadcastParallel)), peerTimeoutMs = range[1..120000](int(
        values.broadcastPeerMs)),
    jobTimeoutMs = range[1..120000](int(values.broadcastJobMs)))
  if not storage.valid or not reads.valid or not acquisition.valid or not receipt.valid or
      not broadcast.valid:
    return refused(WorkPolicyError.InvalidPolicy)
  NodeAssurancePolicyResult(status: WorkPolicyError.None, completed: NodeAssurancePolicy(
    ready: true,
    settings: values, storage: storage, reads: reads, acquisition: acquisition, receipt: receipt,
    broadcast: broadcast))

proc loadNodeAssurancePolicy*(path: string): NodeAssurancePolicyResult {.raises.} =
  ## A bounded file read and complete close precede any Services, socket, archive or private-key activation.
  try:
    var file: File = nil
    if path.len == 0 or path.len > 4096 or path.find(char(0)) >= 0: return refused(
        WorkPolicyError.FileFailure)
    if not open(file, path, fmRead): return refused(WorkPolicyError.FileFailure)
    defer: close(file)
    var text = newString(AssurancePolicyBytes+1)
    let buffer = text.beginStore(text.len)
    let count = readBuffer(file, cast[pointer](buffer), text.len)
    text.endStore()
    if count < 0: return refused(WorkPolicyError.FileFailure)
    if count > AssurancePolicyBytes: return refused(WorkPolicyError.LimitExceeded)
    text.setLen(count)
    return decodeNodeAssurancePolicy(text)
  except:
    return refused(WorkPolicyError.FileFailure)
