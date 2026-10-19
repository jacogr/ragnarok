# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Attach one prepared accumulation service's ordered inputs to a PVM fetch context.
## Exposes bounded explicit-plan attachment and machine-derived fetch assembly with guarded results.
## Neither path executes a service or certifies a block.

import ../codec/[bounded, natural, c2_records, composite]
import ../pvm/host_fetch
import ../chain/parameters
import ./[accumulation_inputs, accumulation_service, accumulation_invocation, accumulation_machine]

type
  ## Adapter failures distinguish invalid selections from local resource refusals and encoding errors.
  InvocationFetchError* {.pure.} = enum
    Uninitialized, None, InvalidContext, InvalidInputs, InvalidIndex, LimitExceeded,
      EncodingFailure,
    InvalidMachine, InvalidParameters
  ## Success owns a complete immutable fetch context; no partial attachment is exposed on failure.
  InvocationFetchResult* = object
    case status: InvocationFetchError
    of None:
      completed: FetchContext # Extract only through the selected-success accessor.
    else:
      discard                 # Failed/default alternatives contain no context.

## Inspect the adapter's outcome without exposing writable result storage.
func error*(outcome: InvocationFetchResult): InvocationFetchError = outcome.status
## Retain the complete context independently of every preparation handle.
func value*(outcome: InvocationFetchResult): FetchContext {.inline,
    requires: outcome.status == InvocationFetchError.None.} = outcome.completed

## Private stable selection chooses either a validated plan group or its already-bound service.
## Only the explicit-plan API supplies an ordinal; the machine path uses serviceInputAt exclusively.
type FetchSelection = object
  bound: bool
  inputs: PreparedAccumulationInputs
  index: InvocationServiceIndex
  service: PreparedAccumulationService

## Retain one input after the caller has validated the selection and its complete input count.
proc selectedInput(source: FetchSelection, index: InvocationInputIndex): InvocationInput =
  if source.bound:
    # The prepared service owns the group identity; callers cannot substitute another ordinal.
    source.service.serviceInputAt(index).value
  else:
    # Explicit-plan preparation already proved this group and each index below its input count.
    source.inputs.invocationInputAt(source.index, index).value

## Preflight and encode one immutable selected sequence using a single shared conversion path.
## Callers validate the base and selection; temporary payload copies are bounded by the wire budget.
proc captureSelection(context: FetchContext, source: FetchSelection, count: uint64,
    limits: FetchAccumulationLimits): InvocationFetchResult =
  ## Refuse atomically without exposing a partially converted or encoded input list.
  template fail(reason: InvocationFetchError) =
    return InvocationFetchResult(status: reason)
  if count > uint64(limits.items) or count > uint64(high(int) div sizeof(AccumulationSource)):
    fail(InvocationFetchError.LimitExceeded) # Bound source descriptors as well as input traversal.
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  var total = uint64(natural.encode(JamNatural(count)).len)
  if total > maximum:
    fail(InvocationFetchError.LimitExceeded) # Allowance-only services still need the empty-list count.
  for i in 0..<int(count):
    # The immutable plan guarantees valid input owners and stable order across both passes.
    let input = selectedInput(source, InvocationInputIndex(i))
    let measured = (if input.kind == AccumulationKind.Transfer:
      accumulationInputSize(transferSource(input.transfer), limits.operand)
      else: ownedOperandSize(input.operand, limits.operand))
    if measured.error != RecordError.None:
      if measured.error == RecordError.LimitExceeded or measured.error ==
          RecordError.LengthOverflow:
        fail(InvocationFetchError.LimitExceeded) # Reapply stricter operand budgets before payload copies.
      fail(InvocationFetchError.EncodingFailure) # An invalid record cannot become protocol absence.
    if uint64(measured.value) > maximum-total:
      fail(InvocationFetchError.LimitExceeded) # Prove the aggregate addition before performing it.
    total += uint64(measured.value)
  var sources = newSeq[AccumulationSource](int(count))
  for i in 0..<sources.len:
    # Conversion borrows only immutable owners and publishes nothing until the final attachment succeeds.
    let input = selectedInput(source, InvocationInputIndex(i))
    case input.kind
    of AccumulationKind.Transfer:
      sources[i] = transferSource(input.transfer) # Preserve all fixed transfer fields verbatim.
    of AccumulationKind.Operand:
      let owner = input.operand # Keep the payload owner alive through all copies.
      let metadata = operandInfo(owner).value
      var operand = AccumulationOperand(packageHash: metadata.packageHash,
        segmentRoot: metadata.segmentRoot, authorizer: metadata.authorizer,
        payloadHash: metadata.payloadHash, gas: metadata.gas,
        authTrace: newSeq[byte](metadata.authBytes))
      if metadata.output.kind == WorkKind.Success:
        # Empty success retains its result discriminator and canonical zero-length blob framing.
        var payload = newSeq[byte](metadata.output.length)
        if copyOperandOutput(owner, payload).error != RecordError.None:
          fail(InvocationFetchError.EncodingFailure) # Never publish an incomplete copied result.
        operand.output = successfulOperandOutput(payload)
      else:
        # Error variants retain their exact reason and never acquire a fabricated success payload.
        operand.output = failedOperandOutput(metadata.output.kind)
      if copyOperandTrace(owner, operand.authTrace).error != RecordError.None:
        fail(InvocationFetchError.EncodingFailure) # No partial authorization trace may escape.
      sources[i] = operandSource(operand)
  let attached = withFetchAccumulation(context, FetchPresence.Present, sources, limits)
  if attached.error != FetchError.None:
    if attached.error == FetchError.LimitExceeded:
      fail(InvocationFetchError.LimitExceeded) # Preserve the host capture's local policy classification.
    fail(InvocationFetchError.EncodingFailure) # Unexpected codec refusal remains a local typed error.
  InvocationFetchResult(status: InvocationFetchError.None, completed: attached.value)

## Select one service ordinal and preserve its transfer-before-operand input order exactly.
## Borrow only immutable owners; validate the whole list before copying blobs. Pure prepared inputs
## do not certify block provenance, account eligibility, transfer credit or execution.
proc withInvocationFetch*(context: FetchContext, inputs: PreparedAccumulationInputs,
    service: InvocationServiceIndex, limits: FetchAccumulationLimits): InvocationFetchResult =
  let checked = withFetchAccumulation(context, FetchPresence.Absent, [], limits)
  if checked.error != FetchError.None:
    # Preserve base-context validation precedence without mutating the supplied handle.
    return InvocationFetchResult(status: InvocationFetchError.InvalidContext)
  let selected = inputs.invocationServiceAt(service)
  if selected.error != AccumulationInputError.None:
    if selected.error == AccumulationInputError.InvalidIndex:
      # Full-width ordinal validation occurs before any native narrowing.
      return InvocationFetchResult(status: InvocationFetchError.InvalidIndex)
    return InvocationFetchResult(status: InvocationFetchError.InvalidInputs) # No fabricated empty group.
  let info = selected.value
  # Two nonnegative host-int counts fit in uint64; descriptor policy checks the narrower allocation.
  let count = uint64(info.transfers) + uint64(info.operands)
  captureSelection(context, FetchSelection(bound: false, inputs: inputs, index: service), count, limits)

## Assemble all accumulation fetch families from the machine's own prepared invocation.
## Configured parameters are explicit; entropy and ordered inputs cannot be independently replaced.
## No source handle or borrowed span must survive return; the complete context owns immutable bytes.
proc machineFetchContext*(prepared: PreparedAccumulationMachine, parameters: Parameters,
    limits: FetchAccumulationLimits): InvocationFetchResult =
  let bootstrap = prepared.machineBootstrap
  if bootstrap.error != AccumulationMachineError.None:
    # Default machines cannot authorize a synthetic fetch environment.
    return InvocationFetchResult(status: InvocationFetchError.InvalidMachine)
  if not parameters.valid:
    # Reject missing configuration before walking or copying invocation inputs.
    return InvocationFetchResult(status: InvocationFetchError.InvalidParameters)
  let invocation = bootstrap.value
  let entropy = FetchEntropy(array[32, byte](invocation.bootstrapInfo.value.entropy))
  let base = captureFetchContext(FetchPresence.Present, entropy, FetchPresence.Absent, [],
    FetchTraceLimit(0)).value
  let configured = withFetchParameters(base, parameters).value
  let service = invocation.bootstrapService.value
  let info = service.serviceInfo.value
  # Preserve the exact prepared input count, including transfers if service preparation supports them.
  let count = uint64(info.transfers) + uint64(info.operands)
  captureSelection(configured, FetchSelection(bound: true, service: service), count, limits)
