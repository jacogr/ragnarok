# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Attach one prepared accumulation service's ordered inputs to a PVM fetch context.
## Exposes bounded withInvocationFetch and guarded results; it neither executes nor certifies a block.

import ../codec/[bounded, natural, c2_records, composite]
import ../pvm/host_fetch
import ./accumulation_inputs

type
  ## Adapter failures distinguish invalid selections from local resource refusals and encoding errors.
  InvocationFetchError* {.pure.} = enum
    Uninitialized, None, InvalidContext, InvalidInputs, InvalidIndex, LimitExceeded, EncodingFailure
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

## Select one service ordinal and preserve its transfer-before-operand input order exactly.
## Preflight all records and aggregate bytes before copying payloads or allocating descriptors.
## Temporary copied payloads are bounded by the list budget; final storage belongs to FetchContext.
## Pure prepared inputs do not certify block provenance, account eligibility, transfer credit or execution.
proc withInvocationFetch*(context: FetchContext, inputs: PreparedAccumulationInputs,
    service: InvocationServiceIndex, limits: FetchAccumulationLimits): InvocationFetchResult =
  ## Return a typed refusal without exposing a partially converted source or attached context.
  template fail(reason: InvocationFetchError) =
    return InvocationFetchResult(status: reason)
  let checked = withFetchAccumulation(context, FetchPresence.Absent, [], limits)
  if checked.error != FetchError.None:
    fail(InvocationFetchError.InvalidContext) # Clearing a temporary handle validates the base without copying.
  let selected = inputs.invocationServiceAt(service)
  if selected.error != AccumulationInputError.None:
    if selected.error == AccumulationInputError.InvalidIndex:
      fail(InvocationFetchError.InvalidIndex) # Full-width ordinal validation occurs before any narrowing.
    fail(InvocationFetchError.InvalidInputs) # Default input plans cannot fabricate an empty service.
  let info = selected.value
  # Private preparation counts are nonnegative host ints; their sum fits uint64 before host narrowing.
  let count = uint64(info.transfers) + uint64(info.operands)
  if count > uint64(limits.items) or count > uint64(high(int) div sizeof(AccumulationSource)):
    fail(InvocationFetchError.LimitExceeded) # Bound source descriptors as well as input traversal.
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  var total = uint64(natural.encode(JamNatural(count)).len)
  if total > maximum:
    fail(InvocationFetchError.LimitExceeded) # Allowance-only services still need the empty-list count.
  for i in 0..<int(count):
    # The immutable plan guarantees valid input owners and stable order across both passes.
    let input = inputs.invocationInputAt(service, InvocationInputIndex(i)).value
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
    let input = inputs.invocationInputAt(service, InvocationInputIndex(i)).value
    case input.kind
    of AccumulationKind.Transfer:
      sources[i] = transferSource(input.transfer) # Preserve all fixed transfer fields verbatim.
    of AccumulationKind.Operand:
      let owner = input.operand # Keep the payload owner alive through all copies.
      let metadata = operandInfo(owner).value
      var source = AccumulationOperand(packageHash: metadata.packageHash,
        segmentRoot: metadata.segmentRoot, authorizer: metadata.authorizer,
        payloadHash: metadata.payloadHash, gas: metadata.gas,
        authTrace: newSeq[byte](metadata.authBytes))
      if metadata.output.kind == WorkKind.Success:
        # Empty success retains its result discriminator and canonical zero-length blob framing.
        var payload = newSeq[byte](metadata.output.length)
        if copyOperandOutput(owner, payload).error != RecordError.None:
          fail(InvocationFetchError.EncodingFailure) # Never publish an incomplete copied result.
        source.output = successfulOperandOutput(payload)
      else:
        # Error variants retain their exact reason and never acquire a fabricated success payload.
        source.output = failedOperandOutput(metadata.output.kind)
      if copyOperandTrace(owner, source.authTrace).error != RecordError.None:
        fail(InvocationFetchError.EncodingFailure) # No partial authorization trace may escape.
      sources[i] = operandSource(source)
  let attached = withFetchAccumulation(context, FetchPresence.Present, sources, limits)
  if attached.error != FetchError.None:
    if attached.error == FetchError.LimitExceeded:
      fail(InvocationFetchError.LimitExceeded) # Preserve the host capture's local policy classification.
    fail(InvocationFetchError.EncodingFailure) # Unexpected codec refusal remains a local typed error.
  InvocationFetchResult(status: InvocationFetchError.None, completed: attached.value)
