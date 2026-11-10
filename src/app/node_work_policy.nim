# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Versioned explicit node work startup: v1 remains unsigned; selecting the complete v2 profile enables bounded guaranteeing with the actual TLS identity.

import std/[strutils, syncio]
import ./work_policy
import ./work_policy/types
import ./[work_exchange, work_distribution, node as application_node]
import ../jamnp-s/[work_sharing, work_recovery, work_distribution as distribution_rules,
  guarantor_store, availability_read]
import ../jamnp-s/[work_submission, work_duty]
import ../state/input_refinement
import ../codec/bounded
import ../pvm/backend
import ../lib/logging

const
  GuarantorPolicyHeader = "ragnarok-work-policy-v2"
  GuarantorPolicyFields = 194 ## Includes one bounded unknown-field diagnostic beyond every required scalar.
type
  NodeWorkSettings* = object ## Plain explicit serialization inputs carry no private key, live source, or activation capability.
    admission*: WorkSubmissionLimits
    execution*: InputRefinementLimits
    duty*: WorkDutyLimits
    timeoutMs*: uint64
    sharing*: WorkSharingLimits
    storage*: GuarantorStorageLimits
    serving*: AvailabilityReadLimits
    recovery*: WorkRecoveryLimits
    recoveryTimeoutMs*: uint64
    guaranteeBytes*, exchangeTimeoutMs*, peerTimeoutMs*, graceMs*: uint64
    deliveryWireBytes*, deliveryTargets*, deliveryEntries*, deliveryBytes*: uint64
    deliveryTimeoutMs*, deliveryPeerTimeoutMs*, deliveryParallel*: uint64
    acquisitionAttempts*, acquisitionTimeoutMs*, acquisitionReplyBytes*: uint64
  NodeWorkPolicy* = object ## Only a complete parsed version selects ready controllers; the default cannot enable submission or signing.
    ready, guaranteeing: bool
    dispatch: WorkDispatchPolicy
    exchange: WorkExchangePolicy
    distribution: WorkDistributionPolicy
    acquisition: WorkAcquisitionPolicy
    recovery: WorkRecoveryPolicy
  NodeWorkSetupError* {.pure.} = enum ## Startup identifies the refused bounded controller without exposing private key or policy contents.
    None, InvalidPolicy, Submission, Acquisition, Recovery, Exchange, Distribution
  NodeWorkPolicyResult* = object ## Failed profiles expose only bounded diagnostics, never a partially enabled controller.
    case status: WorkPolicyError
    of None: completed: NodeWorkPolicy
    else: field: string
include ./work_policy/parser
include ./work_policy/fields
include ./work_policy/guarantor_fields

func error*(outcome: NodeWorkPolicyResult): WorkPolicyError =
  ## Read the selected immutable status before accessing activation data.
  outcome.status

func value*(outcome: NodeWorkPolicyResult): NodeWorkPolicy {.requires: outcome.status ==
    WorkPolicyError.None.} =
  ## Only complete version-specific validation exposes startup policy.
  outcome.completed

func fieldName*(outcome: NodeWorkPolicyResult): string {.requires: outcome.status !=
    WorkPolicyError.None.} =
  ## Diagnostics identify only a bounded field name, never key or policy file contents.
  outcome.field

func valid*(policy: NodeWorkPolicy): bool =
  ## No file or a default value never activates work handlers.
  policy.ready

func guaranteeing*(policy: NodeWorkPolicy): bool =
  ## Legacy v1 remains unsigned even when its submission policy is ready.
  policy.ready and policy.guaranteeing

func dispatchPolicy*(policy: NodeWorkPolicy): WorkDispatchPolicy {.requires: policy.ready.} =
  ## Submission limits remain the same explicit values used by both local and shared work.
  policy.dispatch

func exchangePolicy*(policy: NodeWorkPolicy): WorkExchangePolicy {.requires: policy.ready and
    policy.guaranteeing.} =
  ## This accessor cannot expose an unsigned profile as ready signing configuration.
  policy.exchange

func distributionPolicy*(policy: NodeWorkPolicy): WorkDistributionPolicy {.requires: policy.ready and
    policy.guaranteeing.} =
  ## Complete v2 enables bounded receipt and delivery using the same explicit eligibility policy.
  policy.distribution

func acquisitionPolicy*(policy: NodeWorkPolicy): WorkAcquisitionPolicy {.requires: policy.ready and
    policy.guaranteeing.} =
  ## CE133 original-segment acquisition never borrows network defaults.
  policy.acquisition

func recoveryPolicy*(policy: NodeWorkPolicy): WorkRecoveryPolicy {.requires: policy.ready and
    policy.guaranteeing.} =
  ## Original-assurer recovery has independent explicit CPU and network ceilings.
  policy.recovery

func refused(reason: WorkPolicyError, field = ""): NodeWorkPolicyResult =
  ## No unsuccessful path carries a ready dispatcher or signer setup.
  NodeWorkPolicyResult(status: reason, field: field)

proc encodeGuarantorPolicy*(settings: NodeWorkSettings): string =
  ## Emission lists every input value; it neither supplies budgets nor loads private keys.
  result = GuarantorPolicyHeader & "\n"
  guarantorPolicyFields(settings, result, writeField)

proc decodeNodeWorkPolicy*(text: string, logging = default(LogWriter)): NodeWorkPolicyResult =
  ## Exact declared versions share lexical validation; there is no header guessing or partially configured fallback.
  if text.len > WorkPolicyBytes: return refused(WorkPolicyError.LimitExceeded)
  let newline = text.find('\n')
  let first = if newline < 0: text elif newline == 0: "" else: text.substr(0, newline-1)
  if first == "ragnarok-work-policy-v1":
    let legacy = decodeWorkPolicy(text, logging)
    if legacy.error != WorkPolicyError.None: return refused(legacy.error, legacy.fieldName)
    return NodeWorkPolicyResult(status: WorkPolicyError.None,
      completed: NodeWorkPolicy(ready: true, dispatch: legacy.value))
  var input = parsePolicyInput(text, GuarantorPolicyHeader, WorkPolicyBytes, GuarantorPolicyFields)
  if input.error != WorkPolicyError.None: return refused(input.error, input.field)
  var values = default(NodeWorkSettings)
  guarantorPolicyFields(values, input, readField)
  if input.error notin [WorkPolicyError.None, WorkPolicyError.MissingField]: return refused(
      input.error, input.field)
  for entry in input.values:
    if not entry.used: return refused(WorkPolicyError.UnknownField, entry.name)
  if input.error != WorkPolicyError.None: return refused(input.error, input.field)
  # Validate the original fields so later range conversions retain their proofs.
  if values.timeoutMs < 1 or values.timeoutMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "timeoutMs")
  if values.exchangeTimeoutMs < 1 or values.exchangeTimeoutMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "exchangeTimeoutMs")
  if values.peerTimeoutMs < 1 or values.peerTimeoutMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "peerTimeoutMs")
  if values.deliveryTimeoutMs < 1 or values.deliveryTimeoutMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "deliveryTimeoutMs")
  if values.deliveryPeerTimeoutMs < 1 or values.deliveryPeerTimeoutMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "deliveryPeerTimeoutMs")
  if values.acquisitionTimeoutMs < 1 or values.acquisitionTimeoutMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "acquisitionTimeoutMs")
  if values.recoveryTimeoutMs < 1 or values.recoveryTimeoutMs > 120000:
    return refused(WorkPolicyError.InvalidPolicy, "recovery.timeoutMs")
  if values.graceMs < 2000 or values.graceMs > 120000 or values.exchangeTimeoutMs <= values.graceMs:
    return refused(WorkPolicyError.InvalidPolicy, "graceMs")
  if values.deliveryEntries < 1 or values.deliveryEntries > 64:
    return refused(WorkPolicyError.InvalidPolicy, "deliveryEntries")
  if values.deliveryParallel < 1 or values.deliveryParallel > 64:
    return refused(WorkPolicyError.InvalidPolicy, "deliveryParallel")
  if values.acquisitionAttempts < 1 or values.acquisitionAttempts > 1023:
    return refused(WorkPolicyError.InvalidPolicy, "acquisitionAttempts")
  values.admission.authorization.logging = logging
  values.execution.authorization.logging = logging
  values.execution.refinement.refinement.invocation.logging = logging
  values.sharing.submission = values.admission
  values.sharing.execution = values.execution
  values.recovery.timeoutMs = int(values.recoveryTimeoutMs)
  let dispatch = workDispatchPolicy(values.admission, values.execution, values.duty,
    range[1..120000](int(values.timeoutMs)))
  let exchange = workExchangePolicy(values.sharing, ByteLimit(values.guaranteeBytes),
    values.storage, values.serving, timeoutMs = range[2001..120000](int(values.exchangeTimeoutMs)),
    peerTimeoutMs = range[1..120000](int(values.peerTimeoutMs)),
    graceMs = range[2000..120000](int(values.graceMs)))
  let distribution = workDistributionPolicy(WorkDistributionLimits(
    eligibility: values.sharing.eligibility,
    wireBytes: ByteLimit(values.deliveryWireBytes), targets: ElementLimit(values.deliveryTargets)),
    range[1..64](int(values.deliveryEntries)), ByteLimit(values.deliveryBytes),
    timeoutMs = range[1..120000](int(values.deliveryTimeoutMs)),
    peerTimeoutMs = range[1..120000](int(values.deliveryPeerTimeoutMs)),
    parallel = range[1..64](int(values.deliveryParallel)), deliver = true)
  let acquisition = workAcquisitionPolicy(range[1..1023](int(values.acquisitionAttempts)),
    range[1..120000](int(values.acquisitionTimeoutMs)), ByteLimit(values.acquisitionReplyBytes))
  let recovery = workRecoveryPolicy(values.recovery)
  if not dispatch.valid or not exchange.valid or not distribution.valid or not acquisition.valid or
      not recovery.valid:
    return refused(WorkPolicyError.InvalidPolicy)
  NodeWorkPolicyResult(status: WorkPolicyError.None, completed: NodeWorkPolicy(ready: true,
    guaranteeing: true, dispatch: dispatch, exchange: exchange, distribution: distribution,
    acquisition: acquisition, recovery: recovery))

proc loadNodeWorkPolicy*(path: string, logging = default(
    LogWriter)): NodeWorkPolicyResult {.raises.} =
  ## Read cap+1 bytes and close before policy activation or private TLS key loading can begin.
  try:
    var file: File = nil
    if path.len == 0 or not open(file, path, fmRead): return refused(WorkPolicyError.FileFailure)
    defer: close(file)
    var text = newString(WorkPolicyBytes+1)
    let buffer = text.beginStore(text.len)
    let count = readBuffer(file, cast[pointer](buffer), text.len)
    text.endStore()
    if count < 0: return refused(WorkPolicyError.FileFailure)
    if count > WorkPolicyBytes: return refused(WorkPolicyError.LimitExceeded)
    text.setLen(count)
    return decodeNodeWorkPolicy(text, logging)
  except:
    return refused(WorkPolicyError.FileFailure) # Local I/O failure cannot activate a partial profile.

proc configureNodeWork*(owner: var ApplicationNode, policy: NodeWorkPolicy,
    certificate, privateKey: string): NodeWorkSetupError =
  ## Foreground startup applies only complete profiles before polling; caller teardown retires any failed partial setup without admitting work.
  if not policy.valid: return NodeWorkSetupError.InvalidPolicy
  if not owner.configureWork(policy.dispatchPolicy): return NodeWorkSetupError.Submission
  if policy.guaranteeing:
    # Explicit v2 alone imports the actual TLS key and enables bounded signed exchange, retained reads and automatic distribution.
    if not owner.configureWorkAcquisition(policy.acquisitionPolicy): return NodeWorkSetupError.Acquisition
    if not owner.configureWorkRecovery(policy.recoveryPolicy): return NodeWorkSetupError.Recovery
    if not owner.configureWorkExchange(policy.exchangePolicy, certificate,
        privateKey): return NodeWorkSetupError.Exchange
    if not owner.configureWorkDistribution(policy.distributionPolicy): return NodeWorkSetupError.Distribution
  NodeWorkSetupError.None
