# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind the GP guarantorsig transcript to one original complete computed report.

import ../../codec/bounded
import ../../crypto/[primitives, guarantee]
import ./report as computed_report

type
  ComputedGuaranteeError* {.pure.} = enum ## Refusals carry no signing transcript or partial candidate owner.
    Uninitialized, None, InvalidSource, LimitExceeded, BackendFailure
  ComputedGuaranteeData = ref object ## Immutable acyclic sharing preserves the exact computed report and fixed signing bytes.
    report: ComputedWorkReport
    message: GuaranteeMessage
  ComputedGuaranteeTranscript* = object ## This handle certifies transcript provenance, never signing eligibility or credentials.
    data: nil ComputedGuaranteeData
  ComputedGuaranteeResult*[T] = object ## Only selected success contains an extractable payload.
    case status: ComputedGuaranteeError
    of None:
      completed: T
    else:
      discard                          # Defaults and refusals expose reasons alone.

func error*[T](outcome: ComputedGuaranteeResult[T]): ComputedGuaranteeError =
  ## Inspect the refusal without granting writable status access.
  outcome.status
func value*[T](outcome: ComputedGuaranteeResult[T]): T
    {.requires: outcome.status == ComputedGuaranteeError.None.} =
  ## Optimized contracts guard every selected success extraction.
  outcome.completed
proc computedGuaranteeReport*(transcript: ComputedGuaranteeTranscript): ComputedGuaranteeResult[
    ComputedWorkReport] =
  ## Share the exact original immutable report, including its execution and availability provenance.
  let data = transcript.data
  if data == nil: return ComputedGuaranteeResult[ComputedWorkReport](
      status: ComputedGuaranteeError.Uninitialized)
  ComputedGuaranteeResult[ComputedWorkReport](status: ComputedGuaranteeError.None,
      completed: data.report)
proc computedGuaranteeMessage*(transcript: ComputedGuaranteeTranscript): ComputedGuaranteeResult[
    GuaranteeMessage] =
  ## Copy fixed nominal domain/hash bytes; callers cannot mutate the retained transcript.
  let data = transcript.data
  if data == nil: return ComputedGuaranteeResult[GuaranteeMessage](
      status: ComputedGuaranteeError.Uninitialized)
  ComputedGuaranteeResult[GuaranteeMessage](status: ComputedGuaranteeError.None,
      completed: data.message)
proc prepareComputedGuarantee*(report: ComputedWorkReport,
    limit: ByteLimit): ComputedGuaranteeResult[ComputedGuaranteeTranscript] =
  ## Preflight temporary wire plus retained message before copying or hashing the original report once.
  let info = report.computedReportInfo
  if info.error != ComputedReportError.None:
    return ComputedGuaranteeResult[ComputedGuaranteeTranscript](
        status: ComputedGuaranteeError.InvalidSource) # No invented empty report.
  let budget = uint64(limit)
  if budget < 45:
    return ComputedGuaranteeResult[ComputedGuaranteeTranscript](
        status: ComputedGuaranteeError.LimitExceeded) # Prove subtraction first.
  if info.value.length > budget-45:
    return ComputedGuaranteeResult[ComputedGuaranteeTranscript](
        status: ComputedGuaranteeError.LimitExceeded) # No copy or primitive attempt on refusal.
  let wire = report.computedReportBytes.value
  let message = guaranteeMessage(wire)
  if message.error != CryptoError.None:
    return ComputedGuaranteeResult[ComputedGuaranteeTranscript](
        status: ComputedGuaranteeError.BackendFailure) # Do not retain any candidate on failure.
  ComputedGuaranteeResult[ComputedGuaranteeTranscript](status: ComputedGuaranteeError.None,
    completed: ComputedGuaranteeTranscript(data: ComputedGuaranteeData(report: report,
        message: message.value)))
