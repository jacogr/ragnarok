# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Attach complete code availability to original qualified logical provenance at its own selected child's slot.
import ../state/[current_logical, current_state, code_availability]
import ../codec/state_requests
type
  LogicalCodeAvailability* = object ## Logical identity and original-current compact code observations cannot be independently substituted.
    initialized: bool
    logical: CurrentLogicalState
    codes: StateCodeAvailability
  LogicalCodeError* {.pure.} = enum ## Missing logical provenance and exact complete-code refusal remain distinct.
    Uninitialized, None, InvalidLogical, CodeFailure
  LogicalCodeResult* = object ## Failed audit exposes no successful paired prefix or default availability catalogue.
    case status: LogicalCodeError
    of None: completed: LogicalCodeAvailability
    of CodeFailure: codeReason: CodeAvailabilityResult[StateCodeAvailability]
    else: discard # Default and missing original source grant no code owner.
func error*(outcome: LogicalCodeResult): LogicalCodeError =
  ## Observe the selected immutable stage without granting its payload.
  outcome.status
func value*(outcome: LogicalCodeResult): LogicalCodeAvailability {.inline,
    requires: outcome.status == LogicalCodeError.None.} =
  ## Retain only the fully audited original-source pair.
  outcome.completed
func codeFailure*(outcome: LogicalCodeResult): CodeAvailabilityResult[
    StateCodeAvailability] {.inline, requires: outcome.status == LogicalCodeError.CodeFailure.} =
  ## Preserve genuine selected code quota, linkage, content and backend causes.
  outcome.codeReason
proc auditLogicalCodeAvailability*(source: CurrentLogicalState,
    limits: CodeAvailabilityLimits): LogicalCodeResult =
  ## Derive time and complete inventory from the same original producer, never caller policy rates or a revalidated companion compact owner.
  let original = source.currentLogicalSource
  if original.error != CurrentLogicalError.None: return LogicalCodeResult(
      status: LogicalCodeError.InvalidLogical)
  let context = source.currentLogicalContext.value
  let codes = auditCodeAvailability(original.value.currentStateInventory.value, RequestSlot(
      context.slot), limits)
  if codes.error != CodeAvailabilityError.None: return LogicalCodeResult(
      status: LogicalCodeError.CodeFailure, codeReason: codes)
  LogicalCodeResult(status: LogicalCodeError.None, completed: LogicalCodeAvailability(
      initialized: true, logical: source, codes: codes.value))
proc logicalCodeSource*(source: LogicalCodeAvailability): CurrentLogicalState {.requires: source.initialized.} =
  ## Retain original producer/profile/raw-key provenance only from a completed availability pair.
  source.logical
proc logicalCodeTable*(source: LogicalCodeAvailability): StateCodeAvailability {.requires: source.initialized.} =
  ## Retain only the original-current compact table; the independently revalidated raw-key companion remains distinct.
  source.codes
