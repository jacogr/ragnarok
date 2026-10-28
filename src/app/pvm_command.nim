# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Standalone artifact file IO and bounded host-free execution; caller owns diagnostics and process lifetime.
import ./options
import ../pvm/[artifact, machine, step, gas]

proc runPvmCode*(options: Options, diagnostic: var string): bool =
  ## Execute exactly one export with no inferred host imports, listeners or implicit backend substitution.
  diagnostic = ""
  let loaded = loadArtifact(options.pvmCodePath)
  if loaded.error != ArtifactError.None:
    diagnostic = "PVM_CODE_FAILED artifact=" & $loaded.error
    return false
  let artifact = loaded.value
  let machine = initialMachine(artifact, options.pvmEntry, MachineGas(options.pvmGas))
  if machine.error != ArtifactError.None:
    diagnostic = "PVM_CODE_FAILED entry=" & $machine.error
    return false
  let prepared = newPreparedProgram(programOf(artifact), defaultPreparedLimits(),
      options.pvmBackend)
  if prepared.error != PreparationError.None:
    diagnostic = "PVM_CODE_FAILED preparation=" & $prepared.error
    return false
  let executed = execute(machine.value, ExecutionStepLimit(options.pvmSteps), prepared.value)
  if executed.error != StepError.None:
    diagnostic = "PVM_CODE_FAILED execution=" & $executed.error
    return false
  let outcome = executed.value
  let cpu = machineInfo(outcome.machine).value
  diagnostic = "requested=" & $options.pvmBackend & " actual=" & $outcome.backend &
      " exit=" & $outcome.exit & " gas=" & $uint64(cpu.gas)
  if outcome.exit == StepExit.Host:
    diagnostic = "PVM_CODE_FAILED " & diagnostic & " unbound-host=" & $uint64(outcome.hostCall)
    return false # Application-specific imports require an explicit caller-owned host implementation.
  if outcome.exit != StepExit.Halt:
    diagnostic = "PVM_CODE_FAILED " & diagnostic
    return false
  diagnostic = "PVM_CODE_OK " & diagnostic
  true
