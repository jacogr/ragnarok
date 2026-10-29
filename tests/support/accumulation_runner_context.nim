# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit tiny-profile runner policy for genuine admitted test rounds; does not replace guest execution.

import ../../src/chain/parameters
import ../../src/codec/[bounded, c2_records]
import ../../src/pvm/[initialize, machine, program, step, gas, host_fetch]
import ../../src/state/accumulation/[runner as accumulation_runner,
    invocation as accumulation_invocation]
import ./[accumulation_execution_context, pvm_accumulation_context, accumulation_batch_context]

proc runnerParameters*(cores = 2'u64, epoch = 12'u64, queue = 80'u64,
    code = 512'u64): Parameters =
  ## Override literal Appendix B fixed-width positions in the maximal independent parameter fixture.
  var wire = encodeParameters(pvmParameters())
  for field in [(24, 2, cores), (30, 4, epoch), (82, 2, queue), (98, 4, code), (118, 4, epoch)]:
    for index in 0..<field[1]:
      wire[field[0]+index] = byte((field[2] shr (8*index)) and 255) # Width-limited literal fixture fields.
  decodeParameters(wire).value

proc runnerLimits*(): AccumulationRunnerLimits =
  ## Independent engine/capture/effect budgets match the existing manual fixture oracle.
  var contexts = pvmContextConfig()
  contexts.privileges = executionRoundConfig().privileges
  AccumulationRunnerLimits(completion: executionLimits(), preimageBytes: ByteLimit(1024),
    probes: ServiceProbeLimit(1), initialization: InitializationLimits(
      envelope: InitializationByteLimit(512), program: ProgramByteLimit(256),
      jumps: JumpCountLimit(0), pages: PageLimit(5)), contexts: contexts,
    fetch: FetchAccumulationLimits(items: ElementLimit(1), bytes: ByteLimit(512),
      operand: OperandLimits(maxBytes: ByteLimit(512))), copyBytes: MemoryByteLimit(32),
    steps: ExecutionStepLimit(20), calls: HostCallLimit(4), cycles: GasCycleLimit(1000))

proc runnerProgram*(ending: BatchEnding): seq[byte] =
  ## Service code framing prepends the zero-length metadata prefix to a real authored guest envelope.
  result = @[0'u8]
  for octet in batchEnvelope(ending):
    result.add(octet) # Preserve the envelope exactly, without a production skip or verdict hook.
