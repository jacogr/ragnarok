# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict result and input-alternative contract probes for invocation preparation.
## Command-line modes must terminate at the selected-success/variant guard, never expose defaults.

import std/cmdline
import ../../src/state/[accumulation_inputs, accumulation_operands, accumulation_queue]
import ../../src/codec/[bounded, c2_records, state_workqueues, header]

## Construct an actual copied transfer input solely for the wrong-operand variant probe.
proc transferInput(): InvocationInput =
  let config = AccumulationQueueConfig(queues: WorkQueueConfig(cores: CoreCount(2),
    epochSlots: EpochSlots(1), maxBytes: ByteLimit(1000)))
  let queue = planAccumulationQueues([], [0'u8], [0'u8], HeaderSlot(0), config).value
  let operands = prepareAccumulationOperands(queue, AccumulationReportPrefix(0),
    default(AccumulationOperandConfig)).value
  let inputs = prepareAccumulationInputs(operands, [DeferredTransfer()], [],
    AccumulationInputConfig(inputs: ElementLimit(1), services: ElementLimit(1))).value
  inputs.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(0)).value

# Dynamic refusal/default selection keeps result contract failures observable at runtime.
let outcome = if paramStr(1) == "refused":
  prepareAccumulationInputs(default(PreparedAccumulationOperands), [], [], default(AccumulationInputConfig))
else: default(AccumulationInputResult[PreparedAccumulationInputs]) # No successful payload.

# Runtime choice prevents a literal default variant from being rejected during compilation instead.
let input = if paramStr(1) == "operand": transferInput()
else: default(InvocationInput) # The transfer probe selects the operand alternative dynamically.
let owner = default(PreparedAccumulationInputs)
case paramStr(1)
of "count": discard owner.invocationServiceCount.value # No fabricated empty groups.
of "service": discard owner.invocationServiceAt(InvocationServiceIndex(0)).value # No default metadata.
of "input": discard owner.invocationInputAt(InvocationServiceIndex(0), InvocationInputIndex(
    0)).value # No default input.
of "source": discard owner.invocationOperands.value # No default report-prefix provenance.
of "transfer": discard input.transfer # Operand alternative carries no transfer.
of "operand": discard input.operand # Actual transfer carries no operand owner.
else: discard outcome.value # Default/refused results must fail their success contract.
